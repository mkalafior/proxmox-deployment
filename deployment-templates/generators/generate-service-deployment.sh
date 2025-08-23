#!/bin/bash

# Service Deployment Generator
# Usage: ./generate-service-deployment.sh <service-name> [options]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Proxmox API functions
fetch_proxmox_nodes() {
    if [[ -z "${PROXMOX_HOST:-}" ]]; then
        log_error "PROXMOX_HOST not set. Please configure your Proxmox connection."
        exit 1
    fi

    if [[ -z "${TOKEN_ID:-}" || -z "${TOKEN_SECRET:-}" ]]; then
        log_error "TOKEN_ID and TOKEN_SECRET not set. Please configure your Proxmox API token."
        exit 1
    fi

    log_step "Fetching available Proxmox nodes..."

    local response
    response=$(curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
        "https://${PROXMOX_HOST}:8006/api2/json/nodes" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to connect to Proxmox API"
        exit 1
    fi

    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.data[] | "\(.node)"' 2>/dev/null || echo ""
    else
        # Fallback parsing without jq
        echo "$response" | grep -o '"node":"[^"]*"' | cut -d'"' -f4 || echo ""
    fi
}

fetch_vm_ids_from_node() {
    local node="$1"

    if [[ -z "$node" ]]; then
        log_error "Node name is required"
        return 1
    fi

    log_step "Fetching VM IDs from node $node..."

    local response
    response=$(curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
        "https://${PROXMOX_HOST}:8006/api2/json/nodes/$node/qemu" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to fetch VMs from node $node"
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.data[] | "\(.vmid)"' 2>/dev/null | sort -n || echo ""
    else
        # Fallback parsing without jq
        echo "$response" | grep -o '"vmid":[0-9]*' | cut -d':' -f2 | sort -n || echo ""
    fi
}

find_first_available_vmid() {
    local node="$1"
    local used_vmids
    local vmid=100  # Start from VMID 100

    # Get all used VMIDs from the node
    used_vmids=$(fetch_vm_ids_from_node "$node")

    # Convert to array
    local used_array=()
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" =~ ^[0-9]+$ ]]; then
            used_array+=("$line")
        fi
    done <<< "$used_vmids"

    # Find first available VMID starting from 100
    while [[ $vmid -lt 10000 ]]; do
        local found=false
        if [[ ${#used_array[@]} -gt 0 ]]; then
            for used in "${used_array[@]}"; do
                if [[ "$vmid" == "$used" ]]; then
                    found=true
                    break
                fi
            done
        fi

        if [[ "$found" == "false" ]]; then
            echo "$vmid"
            return 0
        fi

        ((vmid++))
    done

    log_error "No available VMID found (all IDs 100-9999 are in use)"
    return 1
}

select_proxmox_node() {
    local nodes
    nodes=$(fetch_proxmox_nodes)

    if [[ -z "$nodes" ]]; then
        log_error "No Proxmox nodes found or unable to connect"
        exit 1
    fi

    # Convert to array
    local node_array=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            node_array+=("$line")
        fi
    done <<< "$nodes"

    if [[ ${#node_array[@]} -eq 1 ]]; then
        log_info "Using single available node: ${node_array[0]}"
        echo "${node_array[0]}"
        return 0
    fi

    echo ""
    echo "Available Proxmox nodes:"
    for i in "${!node_array[@]}"; do
        echo "  $((i+1)). ${node_array[$i]}"
    done
    echo ""

    local choice
    while true; do
        read -p "Select node (1-${#node_array[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#node_array[@]} ]]; then
            echo "${node_array[$((choice-1))]}"
            return 0
        else
            echo "Invalid choice. Please select a number between 1 and ${#node_array[@]}."
        fi
    done
}

# Default configuration
DEFAULT_VM_CORES=2
DEFAULT_VM_MEMORY=2048
DEFAULT_VM_DISK_SIZE=20
DEFAULT_VM_STORAGE="local-lvm"
DEFAULT_APP_USER="appuser"
DEFAULT_DNS_SERVER="192.168.1.11"
DEFAULT_DNS_DOMAIN="proxmox.local"

show_help() {
    echo "Service Deployment Generator"
    echo ""
    echo "Usage: $0 <service-name> [options]"
    echo ""
    echo "Arguments:"
    echo "  service-name    Name of the service to generate deployment for"
    echo ""
    echo "Options:"
    echo "  --port PORT     Application port (required)"
    echo "  --node NODE     Proxmox node (optional, will prompt for selection)"
    echo "  --vm-id ID      VM ID for Proxmox (optional, will auto-select first available)"
    echo "  --subdomain SUB Cloudflare subdomain (optional)"
    echo "  --hostname HOST Service hostname for DNS (optional, defaults to service-name)"
    echo "  --cores N       CPU cores (default: $DEFAULT_VM_CORES)"
    echo "  --memory MB     Memory in MB (default: $DEFAULT_VM_MEMORY)"
    echo "  --disk GB       Disk size in GB (default: $DEFAULT_VM_DISK_SIZE)"
    echo "  --user USER     Application user (default: $DEFAULT_APP_USER)"
    echo "  --force         Overwrite existing deployment"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 service01 --port 3001"
    echo "  $0 api-service --port 8080 --subdomain api --cores 4"
    echo "  $0 worker --port 3003 --node proxmox-node1 --hostname background-worker"
}

# Parse command line arguments
SERVICE_NAME=""
VM_ID=""
APP_PORT=""
PROXMOX_NODE=""
APP_SUBDOMAIN=""
SERVICE_HOSTNAME=""
VM_CORES="$DEFAULT_VM_CORES"
VM_MEMORY="$DEFAULT_VM_MEMORY"
VM_DISK_SIZE="$DEFAULT_VM_DISK_SIZE"
APP_USER="$DEFAULT_APP_USER"
FORCE_OVERWRITE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --vm-id)
            VM_ID="$2"
            shift 2
            ;;
        --port)
            APP_PORT="$2"
            shift 2
            ;;
        --node)
            PROXMOX_NODE="$2"
            shift 2
            ;;
        --subdomain)
            APP_SUBDOMAIN="$2"
            shift 2
            ;;
        --hostname)
            SERVICE_HOSTNAME="$2"
            shift 2
            ;;
        --cores)
            VM_CORES="$2"
            shift 2
            ;;
        --memory)
            VM_MEMORY="$2"
            shift 2
            ;;
        --disk)
            VM_DISK_SIZE="$2"
            shift 2
            ;;
        --user)
            APP_USER="$2"
            shift 2
            ;;
        --force)
            FORCE_OVERWRITE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$SERVICE_NAME" ]]; then
                SERVICE_NAME="$1"
            else
                log_error "Unexpected argument: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVICE_NAME" ]]; then
    log_error "Service name is required"
    show_help
    exit 1
fi

if [[ -z "$APP_PORT" ]]; then
    log_error "Application port is required (--port)"
    show_help
    exit 1
fi

# Load environment configuration if available
if [[ -f "$HOME/.pxdcli/env.global" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.pxdcli/env.global"
fi

# Handle node selection
if [[ -z "$PROXMOX_NODE" ]]; then
    PROXMOX_NODE=$(select_proxmox_node)
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
fi

# Handle VM ID selection
if [[ -z "$VM_ID" ]]; then
    VM_ID=$(find_first_available_vmid "$PROXMOX_NODE")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    log_info "Auto-selected VM ID: $VM_ID on node $PROXMOX_NODE"
else
    log_info "Using specified VM ID: $VM_ID on node $PROXMOX_NODE"
fi

# Set defaults for optional parameters
if [[ -z "$SERVICE_HOSTNAME" ]]; then
    SERVICE_HOSTNAME="$SERVICE_NAME"
fi

# Note: leave APP_SUBDOMAIN as provided (can be empty to disable Cloudflare subdomain)

# Validate service name format
if [[ ! "$SERVICE_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
    log_error "Service name must contain only lowercase letters, numbers, and hyphens"
    log_error "Must start and end with alphanumeric characters"
    exit 1
fi

# Roots: support global templates and external target projects
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TEMPLATES_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATES_ROOT="${TEMPLATES_ROOT:-${DEFAULT_TEMPLATES_ROOT}}"
TEMPLATES_BASE="${TEMPLATES_ROOT}/deployment-templates"

TARGET_PROJECT_ROOT="${PROJECT_ROOT_OVERRIDE:-${TEMPLATES_ROOT%/deployment-templates}}"

if [[ ! -f "$TEMPLATES_BASE/base/deploy.yml.j2" ]]; then
    log_error "Cannot find deployment templates at $TEMPLATES_BASE/base/deploy.yml.j2"
    exit 1
fi

# Set up paths
DEPLOYMENT_DIR="$TARGET_PROJECT_ROOT/deployments/$SERVICE_NAME"
SERVICE_DIR="$TARGET_PROJECT_ROOT/services/$SERVICE_NAME"
TEMPLATE_DIR="$TEMPLATES_BASE/base"

echo "🚀 Service Deployment Generator"
echo "==============================="
echo ""
echo "📋 Configuration:"
echo "   Service Name: $SERVICE_NAME"
echo "   Proxmox Node: $PROXMOX_NODE"
echo "   VM ID: $VM_ID"
echo "   App Port: $APP_PORT"
echo "   Subdomain: $APP_SUBDOMAIN"
echo "   Hostname: $SERVICE_HOSTNAME"
echo "   VM Cores: $VM_CORES"
echo "   VM Memory: ${VM_MEMORY}MB"
echo "   VM Disk: ${VM_DISK_SIZE}GB"
echo "   App User: $APP_USER"
echo ""

# Check if deployment already exists
if [[ -d "$DEPLOYMENT_DIR" ]] && [[ "$FORCE_OVERWRITE" != "true" ]]; then
    log_warn "Deployment directory already exists: $DEPLOYMENT_DIR"
    echo ""
    read -p "Overwrite existing deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Generation cancelled"
        exit 0
    fi
fi

# Create service directory if it doesn't exist
if [[ ! -d "$SERVICE_DIR" ]]; then
    log_step "Creating service directory: $SERVICE_DIR"
    mkdir -p "$SERVICE_DIR"
    
    # Create a basic package.json for the service
    cat > "$SERVICE_DIR/package.json" << EOF
{
  "name": "$SERVICE_NAME",
  "version": "1.0.0",
  "description": "Generated service: $SERVICE_NAME",
  "main": "index.js",
  "scripts": {
    "start": "bun run index.js",
    "dev": "bun run --watch index.js"
  },
  "dependencies": {}
}
EOF

    # Create a basic index.js
    cat > "$SERVICE_DIR/index.js" << EOF
// Generated service: $SERVICE_NAME
const server = Bun.serve({
  port: process.env.PORT || $APP_PORT,
  hostname: process.env.HOST || "0.0.0.0",
  fetch(req) {
    const url = new URL(req.url);
    
    if (url.pathname === "/health") {
      return new Response(JSON.stringify({
        status: "healthy",
        service: "$SERVICE_NAME",
        timestamp: new Date().toISOString()
      }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    if (url.pathname === "/") {
      return new Response(JSON.stringify({
        message: "Hello from $SERVICE_NAME!",
        service: "$SERVICE_NAME",
        port: server.port
      }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    return new Response("Not Found", { status: 404 });
  },
});

console.log(\`🚀 $SERVICE_NAME running on http://\${server.hostname}:\${server.port}\`);
EOF

    log_info "✅ Created basic service structure in $SERVICE_DIR"
fi

# Create deployment directory
log_step "Creating deployment directory: $DEPLOYMENT_DIR"
mkdir -p "$DEPLOYMENT_DIR"/{group_vars,templates,scripts}

# Generate service-specific configuration
log_step "Generating service configuration..."

# Calculate derived values
VM_NAME="$SERVICE_NAME"
APP_DIR="/opt/$SERVICE_NAME"
APP_SERVICE_NAME="$SERVICE_NAME"
LOCAL_APP_PATH="../../services/$SERVICE_NAME"

# Ensure safe default for service type (used later if provided by caller)
SERVICE_TYPE_CFG=""

# Create service configuration file (preserve existing if present)
if [[ -f "$DEPLOYMENT_DIR/service-config.yml" ]]; then
  log_step "Preserving existing service-config.yml"
else
  cat > "$DEPLOYMENT_DIR/service-config.yml" << EOF
# Service configuration for $SERVICE_NAME
# Generated on $(date)

service_name: $SERVICE_NAME
vm_name: $VM_NAME
vm_id: $VM_ID
vm_cores: $VM_CORES
vm_memory: $VM_MEMORY
vm_disk_size: $VM_DISK_SIZE
vm_storage: $DEFAULT_VM_STORAGE
vm_network_bridge: vmbr0
vm_swap: 512
vm_unprivileged: true

app_name: $SERVICE_NAME
app_user: $APP_USER
app_dir: $APP_DIR
app_service_name: $APP_SERVICE_NAME
app_port: $APP_PORT
local_app_path: "$LOCAL_APP_PATH"

service_hostname: $SERVICE_HOSTNAME
app_subdomain: $APP_SUBDOMAIN

dns_server: $DEFAULT_DNS_SERVER
dns_domain: $DEFAULT_DNS_DOMAIN

# Proxmox node override (leave empty to use global default)
proxmox_node: $PROXMOX_NODE

# Custom environment variables (add as needed)
custom_env_vars: {}

# Additional ports to open in firewall (add as needed)
additional_ports: []
EOF
  # If the generator was invoked with a pre-defined service_type, include it
  if [[ -n "$SERVICE_TYPE_CFG" ]]; then
    echo "service_type: $SERVICE_TYPE_CFG" >> "$DEPLOYMENT_DIR/service-config.yml"
    # Add database-specific defaults if needed
    if [[ "$SERVICE_TYPE_CFG" == "database" ]]; then
      RUNTIME_VAL=$(grep -E '^(runtime_variant|db_type):' "$DEPLOYMENT_DIR/service-config.yml" | head -n1 | awk -F: '{print $2}' | xargs || echo "postgresql")
      echo "runtime_variant: ${RUNTIME_VAL}" >> "$DEPLOYMENT_DIR/service-config.yml"
      echo "db_type: ${RUNTIME_VAL}" >> "$DEPLOYMENT_DIR/service-config.yml"
      # Only add db_name/user/pass if missing
      grep -q '^db_name:' "$DEPLOYMENT_DIR/service-config.yml" || echo "db_name: $SERVICE_NAME" >> "$DEPLOYMENT_DIR/service-config.yml"
      grep -q '^db_user:' "$DEPLOYMENT_DIR/service-config.yml" || echo "db_user: $SERVICE_NAME" >> "$DEPLOYMENT_DIR/service-config.yml"
      if ! grep -q '^db_password:' "$DEPLOYMENT_DIR/service-config.yml"; then
        if command -v openssl >/dev/null 2>&1; then
          GENPW=$(openssl rand -base64 24 | tr -d '\n')
        else
          GENPW=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
        fi
        echo "db_password: \"$GENPW\"" >> "$DEPLOYMENT_DIR/service-config.yml"
      fi
    fi
  fi
fi

# Generate Ansible playbook using sed replacements
log_step "Generating Ansible playbook..."

# Prefer service-type specific templates if available
SERVICE_TYPE_CFG=""
if [[ -f "$DEPLOYMENT_DIR/service-config.yml" ]]; then
    SERVICE_TYPE_CFG=$(grep -E '^service_type:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || true)
fi
TYPE_TEMPLATE_DIR="$TEMPLATES_BASE/service-types/${SERVICE_TYPE_CFG}"

# Choose deploy template
DEPLOY_TEMPLATE_FILE="$TEMPLATE_DIR/deploy.yml.j2"
if [[ -n "$SERVICE_TYPE_CFG" && -f "$TYPE_TEMPLATE_DIR/deploy.yml.j2" ]]; then
    DEPLOY_TEMPLATE_FILE="$TYPE_TEMPLATE_DIR/deploy.yml.j2"
fi

# Copy and customize deploy.yml
cp "$DEPLOY_TEMPLATE_FILE" "$DEPLOYMENT_DIR/deploy.yml"
sed -i '' "s/{{ service_name }}/$SERVICE_NAME/g" "$DEPLOYMENT_DIR/deploy.yml"

# Choose group_vars template (prefer service-type specific)
GROUP_VARS_TEMPLATE_FILE="$TEMPLATE_DIR/group_vars/all.yml.j2"
if [[ -n "$SERVICE_TYPE_CFG" && -f "$TYPE_TEMPLATE_DIR/group_vars/all.yml.j2" ]]; then
    GROUP_VARS_TEMPLATE_FILE="$TYPE_TEMPLATE_DIR/group_vars/all.yml.j2"
fi

# Copy and customize group_vars/all.yml
cp "$GROUP_VARS_TEMPLATE_FILE" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ service_name }}/$SERVICE_NAME/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ vm_name }}/$VM_NAME/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ vm_id }}/$VM_ID/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ vm_cores | default(2) }}/$VM_CORES/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ vm_memory | default(2048) }}/$VM_MEMORY/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ vm_disk_size | default(20) }}/$VM_DISK_SIZE/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ vm_storage | default('local-lvm') }}/$DEFAULT_VM_STORAGE/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ vm_network_bridge | default('vmbr0') }}/vmbr0/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ vm_swap | default(512) }}/512/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ vm_unprivileged | default(true) }}/true/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ app_user | default('appuser') }}/$APP_USER/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s|{{ app_dir }}|$APP_DIR|g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ app_service_name }}/$APP_SERVICE_NAME/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ app_port }}/$APP_PORT/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s|{{ local_app_path }}|$LOCAL_APP_PATH|g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ service_hostname }}/$SERVICE_HOSTNAME/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ dns_server | default('192.168.1.11') }}/$DEFAULT_DNS_SERVER/g" "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' "s/{{ dns_domain | default('proxmox.local') }}/$DEFAULT_DNS_DOMAIN/g" "$DEPLOYMENT_DIR/group_vars/all.yml"

# Handle proxmox_node configuration
if [[ -n "$PROXMOX_NODE" ]]; then
    # Replace the proxmox_node in the template if it exists
    sed -i '' "s/proxmox_node: .*/proxmox_node: $PROXMOX_NODE/" "$DEPLOYMENT_DIR/group_vars/all.yml"
else
    # Remove the proxmox_node_override conditional block since it's commented out by default
    sed -i '' '/{% if proxmox_node_override %}/,/{% endif %}/d' "$DEPLOYMENT_DIR/group_vars/all.yml"
fi

# Remove template-specific syntax that doesn't apply
sed -i '' '/{% if custom_env_vars %}/,/{% endif %}/d' "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' '/{% if additional_ports %}/,/{% endif %}/d' "$DEPLOYMENT_DIR/group_vars/all.yml"

# Ensure helper to write key/values in group vars
ensure_kv() {
    local key="$1"; shift
    local value="$1"; shift
    if grep -q "^${key}:" "$DEPLOYMENT_DIR/group_vars/all.yml"; then
        sed -i '' "s|^${key}:.*|${key}: ${value}|" "$DEPLOYMENT_DIR/group_vars/all.yml"
    else
        printf "%s: %s\n" "${key}" "${value}" >> "$DEPLOYMENT_DIR/group_vars/all.yml"
    fi
}

# Inject variables per service type
if [[ "$SERVICE_TYPE_CFG" == "database" ]]; then
    DB_NAME_VAL=$(grep -E '^db_name:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || echo "$SERVICE_NAME")
    DB_USER_VAL=$(grep -E '^db_user:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || echo "$SERVICE_NAME")
    DB_PASS_VAL=$(grep -E '^db_password:' "$DEPLOYMENT_DIR/service-config.yml" | cut -d: -f2- | xargs || true)
    RUNTIME_VAL=$(grep -E '^(runtime_variant|db_type):' "$DEPLOYMENT_DIR/service-config.yml" | head -n1 | awk -F: '{print $2}' | xargs || echo "postgresql")
    ensure_kv "service_type" "database"
    ensure_kv "runtime_variant" "${RUNTIME_VAL}"
    ensure_kv "db_type" "${RUNTIME_VAL}"
    ensure_kv "db_name" "${DB_NAME_VAL}"
    ensure_kv "db_user" "${DB_USER_VAL}"
    if grep -q "^db_password:" "$DEPLOYMENT_DIR/group_vars/all.yml"; then
        sed -i '' "s|^db_password:.*|db_password: \"${DB_PASS_VAL}\"|" "$DEPLOYMENT_DIR/group_vars/all.yml"
    else
        printf "db_password: \"%s\"\n" "${DB_PASS_VAL}" >> "$DEPLOYMENT_DIR/group_vars/all.yml"
    fi
else
    # Non-database: write concrete service_type, default to nodejs if unset
    if [[ -z "$SERVICE_TYPE_CFG" ]]; then
        SERVICE_TYPE_CFG="nodejs"
    fi
    ensure_kv "service_type" "$SERVICE_TYPE_CFG"
    if [[ "$SERVICE_TYPE_CFG" == "nodejs" ]]; then
        RUNTIME_VAL=$(grep -E '^(nodejs_runtime|runtime_variant):' "$DEPLOYMENT_DIR/service-config.yml" | head -n1 | awk -F: '{print $2}' | xargs || echo "bun")
        ensure_kv "nodejs_runtime" "${RUNTIME_VAL}"
    fi
fi

log_info "✅ Generated Ansible configuration"

# Copy templates
log_step "Copying service templates..."
cp -r "$TEMPLATE_DIR/templates/"* "$DEPLOYMENT_DIR/templates/"

# Rename the generic service template to match the service name
if [[ -f "$DEPLOYMENT_DIR/templates/hello-world-bun-app.service.j2" ]]; then
    mv "$DEPLOYMENT_DIR/templates/hello-world-bun-app.service.j2" "$DEPLOYMENT_DIR/templates/${SERVICE_NAME}.service.j2"
fi

# Adjust systemd unit for NodeJS runtime=node
if [[ -f "$DEPLOYMENT_DIR/service-config.yml" ]]; then
  svc_type=$(grep -E '^service_type:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || true)
  runtime=$(grep -E '^(nodejs_runtime|runtime_variant):' "$DEPLOYMENT_DIR/service-config.yml" | head -n1 | awk -F: '{print $2}' | xargs || true)
  if [[ "$svc_type" == "nodejs" && "$runtime" == "node" ]]; then
    sed -i '' 's|^Description=.*|Description={{ app_name }} - Node Application|' "$DEPLOYMENT_DIR/templates/${SERVICE_NAME}.service.j2" || true
    sed -i '' 's|^ExecStart=.*|ExecStart=/usr/bin/node index.js|' "$DEPLOYMENT_DIR/templates/${SERVICE_NAME}.service.j2" || true
  fi
fi

# Generate service-specific environment file
log_step "Generating environment configuration..."
cat > "$DEPLOYMENT_DIR/env.service" << EOF
# Service-specific environment for $SERVICE_NAME
# Source this file along with global configuration

export SERVICE_NAME="$SERVICE_NAME"
export PROXMOX_NODE="$PROXMOX_NODE"
export VM_ID="$VM_ID"
export APP_PORT="$APP_PORT"
export APP_SUBDOMAIN="$APP_SUBDOMAIN"
export SERVICE_HOSTNAME="$SERVICE_HOSTNAME"

# Override global settings if needed
# export VM_CORES="$VM_CORES"
# export VM_MEMORY="$VM_MEMORY"
EOF

# Create inventory file
log_step "Creating inventory file..."
cat > "$DEPLOYMENT_DIR/inventory.yml" << EOF
---
# Dynamic inventory for $SERVICE_NAME - will be populated during deployment
all:
  children:
    proxmox_vms:
      hosts:
        # VMs will be added here dynamically during deployment
    proxmox_servers:
      hosts:
        # Proxmox host will be added here if needed
EOF

# Copy and customize shell scripts
log_step "Generating management scripts..."

# Create deploy script
cat > "$DEPLOYMENT_DIR/deploy.sh" << 'EOF'
#!/bin/bash

# Service-specific deployment script
set -euo pipefail

# Get script directory and service name
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="$(basename "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "🚀 Deploying $SERVICE_NAME"
echo "=========================="

# Check if we're in the right directory
if [[ ! -f "deploy.yml" ]]; then
    log_error "Please run this script from the service deployment directory"
    exit 1
fi

# Load global CLI env and service overrides
if [[ -f "$HOME/.pxdcli/env.global" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.pxdcli/env.global"
fi
if [[ -f ./env.service ]]; then
  # shellcheck disable=SC1091
  source ./env.service
fi

# Extract key values from service-config.yml if unset
if [[ -f "service-config.yml" ]]; then
  VM_ID="${VM_ID:-$(grep -E '^vm_id:' service-config.yml | awk -F: '{print $2}' | xargs || true)}"
  APP_PORT="${APP_PORT:-$(grep -E '^app_port:' service-config.yml | awk -F: '{print $2}' | xargs || true)}"
  SERVICE_HOSTNAME="${SERVICE_HOSTNAME:-$(grep -E '^service_hostname:' service-config.yml | awk -F: '{print $2}' | xargs || true)}"
fi


# Check required environment variables
if [[ -z "${PROXMOX_HOST:-}" ]]; then
    log_error "PROXMOX_HOST not configured in global settings"
    exit 1
fi

# Install required Ansible collections
log_step "Installing Ansible requirements..."
ansible-galaxy collection install community.general --force >/dev/null 2>&1

# Validate playbook
log_step "Validating deployment configuration..."
ansible-playbook deploy.yml --syntax-check >/dev/null

# Show deployment plan
echo ""
echo "🎯 Deployment Plan for $SERVICE_NAME:"
echo "   Proxmox Host: ${PROXMOX_HOST}"
echo "   VM ID: ${VM_ID}"
echo "   Application Port: ${APP_PORT}"
echo "   Service Hostname: ${SERVICE_HOSTNAME:-$SERVICE_NAME}"
if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
    echo "   Public URL: https://${APP_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"
fi
echo ""

# Run deployment
log_info "Starting deployment of $SERVICE_NAME..."
if ansible-playbook deploy.yml -v; then
    log_info "✅ $SERVICE_NAME deployment completed successfully"
    # Show access information via FQDN
    GV_FILE="group_vars/all.yml"
    if [[ -f "$GV_FILE" ]]; then
      SVC_HOST=$(grep -E '^service_hostname:' "$GV_FILE" | awk -F: '{print $2}' | xargs || true)
      DNS_DOMAIN=$(grep -E '^dns_domain:' "$GV_FILE" | awk -F: '{print $2}' | xargs || true)
      if [[ -n "$SVC_HOST" && -n "$DNS_DOMAIN" ]]; then
        FQDN="$SVC_HOST.$DNS_DOMAIN"
        echo ""
        echo "🎉 $SERVICE_NAME is now running!"
        echo "   Local URL: http://${FQDN}:${APP_PORT}"
        echo "   Health Check: http://${FQDN}:${APP_PORT}/health"
        if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
            echo "   Public URL: https://${APP_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"
        fi
        echo ""
        echo "🔧 Management (via pxdcli):"
        echo "   Status: pxdcli status ${SERVICE_NAME}"
        echo "   Logs: pxdcli logs ${SERVICE_NAME}"
        echo "   Restart: pxdcli restart ${SERVICE_NAME}"
        echo "   SSH: pxdcli ssh ${SERVICE_NAME}"
      fi
    fi
else
    log_error "$SERVICE_NAME deployment failed"
    exit 1
fi
EOF

chmod +x "$DEPLOYMENT_DIR/deploy.sh"

# Deprecated: manage.sh no longer generated; use pxdcli instead

# Create cleanup playbook and wrapper script
cp "$TEMPLATE_DIR/cleanup.yml.j2" "$DEPLOYMENT_DIR/cleanup.yml"
sed -i '' "s/{{ service_name }}/$SERVICE_NAME/g" "$DEPLOYMENT_DIR/cleanup.yml"

cat > "$DEPLOYMENT_DIR/cleanup.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="$(basename "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🧹 Cleanup $SERVICE_NAME Deployment"
echo "===================================="

if [[ -f "$HOME/.pxdcli/env.global" ]]; then
  source "$HOME/.pxdcli/env.global"
fi
if [[ -f ./env.service ]]; then
  source ./env.service
fi

if [[ ! -f ./group_vars/all.yml ]]; then
  err "group_vars/all.yml missing"
  exit 1
fi

ANSIBLE_CONFIG=${ANSIBLE_CONFIG:-./ansible.cfg}
ANSIBLE_STDOUT_CALLBACK=unixy ansible-playbook cleanup.yml -e @group_vars/all.yml
info "Cleanup playbook completed"
EOF

chmod +x "$DEPLOYMENT_DIR/cleanup.sh"

# Create requirements.yml
DB_EXTRA_COLLECTIONS=""
SERVICE_CONFIG_FILE="$DEPLOYMENT_DIR/service-config.yml"
if [[ -f "$SERVICE_CONFIG_FILE" ]]; then
  svc_type_val=$(grep -E "^service_type:" "$SERVICE_CONFIG_FILE" | awk -F: '{print $2}' | tr -d ' ' || true)
  runtime_val=$(grep -E "^(runtime_variant|db_type):" "$SERVICE_CONFIG_FILE" | awk -F: '{print $2}' | tr -d ' ' || true)
  if [[ "$svc_type_val" == "database" ]]; then
    # Always include both postgres and mysql collections for DB services
    DB_EXTRA_COLLECTIONS=$'  - name: community.postgresql\n    version: ">=3.0.0"\n  - name: community.mysql\n    version: ">=3.0.0"'
  fi
fi

cat > "$DEPLOYMENT_DIR/requirements.yml" << EOF
---
collections:
  - name: community.general
    version: ">=3.0.0"
  - name: ansible.posix
    version: ">=1.0.0"
$(if [[ -n "$DB_EXTRA_COLLECTIONS" ]]; then echo -e "$DB_EXTRA_COLLECTIONS"; fi)
EOF

# Create ansible.cfg
cat > "$DEPLOYMENT_DIR/ansible.cfg" << EOF
[defaults]
host_key_checking = False
inventory = inventory.yml
remote_user = root
private_key_file = ~/.ssh/id_proxmox
timeout = 30
gathering = smart
fact_caching = memory

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no
pipelining = True
EOF

log_info "✅ Generated deployment configuration for $SERVICE_NAME"

echo ""
echo "🎉 Service deployment generated successfully!"
echo "============================================="
echo ""
echo "📁 Generated files in $DEPLOYMENT_DIR/:"
echo "   • deploy.yml          - Ansible deployment playbook"
echo "   • group_vars/all.yml  - Service configuration"
echo "   • env.service         - Service environment variables"
echo "   • deploy.sh           - Deployment script"
echo "   • cleanup.sh          - Cleanup script"
echo "   • templates/          - Service templates"
echo ""
echo "🚀 Next steps:"
echo "   1. Review configuration: deployments/$SERVICE_NAME/service-config.yml"
echo "   2. Customize service code: services/$SERVICE_NAME/"
echo "   3. Deploy service: cd deployments/$SERVICE_NAME && ./deploy.sh"
echo ""
echo "💡 Quick deploy:"
echo "   cd deployments/$SERVICE_NAME && ./deploy.sh"
 
