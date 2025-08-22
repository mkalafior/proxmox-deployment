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
    echo "  --vm-id ID      VM ID for Proxmox (required)"
    echo "  --port PORT     Application port (required)"
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
    echo "  $0 service01 --vm-id 201 --port 3001"
    echo "  $0 api-service --vm-id 202 --port 8080 --subdomain api --cores 4"
    echo "  $0 worker --vm-id 203 --port 3003 --hostname background-worker"
}

# Parse command line arguments
SERVICE_NAME=""
VM_ID=""
APP_PORT=""
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

if [[ -z "$VM_ID" ]]; then
    log_error "VM ID is required (--vm-id)"
    show_help
    exit 1
fi

if [[ -z "$APP_PORT" ]]; then
    log_error "Application port is required (--port)"
    show_help
    exit 1
fi

# Set defaults for optional parameters
if [[ -z "$SERVICE_HOSTNAME" ]]; then
    SERVICE_HOSTNAME="$SERVICE_NAME"
fi

if [[ -z "$APP_SUBDOMAIN" ]]; then
    APP_SUBDOMAIN="$SERVICE_NAME"
fi

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

# Create service configuration file
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
# proxmox_node: pve2

# Custom environment variables (add as needed)
custom_env_vars: {}

# Additional ports to open in firewall (add as needed)
additional_ports: []
EOF

# Generate Ansible playbook using sed replacements
log_step "Generating Ansible playbook..."

# Copy and customize deploy.yml
cp "$TEMPLATE_DIR/deploy.yml.j2" "$DEPLOYMENT_DIR/deploy.yml"
sed -i '' "s/{{ service_name }}/$SERVICE_NAME/g" "$DEPLOYMENT_DIR/deploy.yml"

# Copy and customize group_vars/all.yml
cp "$TEMPLATE_DIR/group_vars/all.yml.j2" "$DEPLOYMENT_DIR/group_vars/all.yml"
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

# Remove the proxmox_node_override conditional block since it's commented out by default
sed -i '' '/{% if proxmox_node_override %}/,/{% endif %}/d' "$DEPLOYMENT_DIR/group_vars/all.yml"

# Remove template-specific syntax that doesn't apply
sed -i '' '/{% if custom_env_vars %}/,/{% endif %}/d' "$DEPLOYMENT_DIR/group_vars/all.yml"
sed -i '' '/{% if additional_ports %}/,/{% endif %}/d' "$DEPLOYMENT_DIR/group_vars/all.yml"

log_info "✅ Generated Ansible configuration"

# Copy templates
log_step "Copying service templates..."
cp -r "$TEMPLATE_DIR/templates/"* "$DEPLOYMENT_DIR/templates/"

# Rename the generic service template to match the service name
if [[ -f "$DEPLOYMENT_DIR/templates/hello-world-bun-app.service.j2" ]]; then
    mv "$DEPLOYMENT_DIR/templates/hello-world-bun-app.service.j2" "$DEPLOYMENT_DIR/templates/${SERVICE_NAME}.service.j2"
fi

# Generate service-specific environment file
log_step "Generating environment configuration..."
cat > "$DEPLOYMENT_DIR/env.service" << EOF
# Service-specific environment for $SERVICE_NAME
# Source this file along with global configuration

export SERVICE_NAME="$SERVICE_NAME"
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

# Load environment
if [[ -f ../../global-config/load-env.sh ]]; then
  # Preferred: project-local loader
  source ../../global-config/load-env.sh
  if ! load_clean_env "$SERVICE_NAME" "$(pwd)"; then
      log_error "Failed to load clean environment"
      exit 1
  fi
else
  # Fallback: use global CLI env if present
  if [[ -f "$HOME/.pxdcli/env.global" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.pxdcli/env.global"
  fi
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
    
    # Show access information
    if [[ -f "vm_ip.txt" ]]; then
        VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')
        echo ""
        echo "🎉 $SERVICE_NAME is now running!"
        echo "   Local URL: http://${VM_IP}:${APP_PORT}"
        echo "   Health Check: http://${VM_IP}:${APP_PORT}/health"
        if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
            echo "   Public URL: https://${APP_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"
        fi
        echo ""
        echo "🔧 Management:"
        echo "   Status: ./manage.sh status"
        echo "   Logs: ./manage.sh logs"
        echo "   SSH: ssh -i ~/.ssh/id_proxmox root@${VM_IP}"
    fi
else
    log_error "$SERVICE_NAME deployment failed"
    exit 1
fi
EOF

chmod +x "$DEPLOYMENT_DIR/deploy.sh"

# Create manage script
cat > "$DEPLOYMENT_DIR/manage.sh" << 'EOF'
#!/bin/bash

# Service management script
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
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SSH_KEY_PATH="$HOME/.ssh/id_proxmox"

# Check if deployment exists
if [[ ! -f "vm_ip.txt" ]]; then
    log_error "No deployment found for $SERVICE_NAME. Run ./deploy.sh first"
    exit 1
fi

VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')

# Source environment configuration
if [[ -f "env.service" ]]; then
    source env.service
fi

show_help() {
    echo "$SERVICE_NAME Management Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  status    - Show service status"
    echo "  logs      - Show service logs"
    echo "  restart   - Restart the service"
    echo "  system    - Show system information"
    echo "  info      - Show deployment information"
    echo "  help      - Show this help message"
    echo ""
}

check_vm_access() {
    if ! ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no root@${VM_IP} "echo 'OK'" &>/dev/null; then
        log_error "Cannot connect to $SERVICE_NAME VM at ${VM_IP}"
        exit 1
    fi
}

detect_service_info() {
    SERVICE_TYPE="$(grep -E '^service_type:' service-config.yml 2>/dev/null | awk -F: '{print $2}' | xargs || true)"
    if [[ -z "${SERVICE_TYPE}" ]]; then SERVICE_TYPE="nodejs"; fi
    RUNTIME_VARIANT_CFG="$(grep -E '^(runtime_variant|db_type):' service-config.yml 2>/dev/null | head -n1 | awk -F: '{print $2}' | xargs || true)"
    APP_UNIT_NAME="$(grep -E '^app_service_name:' service-config.yml 2>/dev/null | awk -F: '{print $2}' | xargs || true)"
    if [[ -z "${APP_UNIT_NAME}" ]]; then APP_UNIT_NAME="$SERVICE_NAME"; fi
}

restart_units() {
    detect_service_info
    # Load restart units from service-type script if present
    local units_str=""
    local type_dir="$(cd "${SCRIPT_DIR}/../../deployment-templates/service-types" && pwd)"
    if [[ -n "${SERVICE_TYPE}" && -f "${type_dir}/${SERVICE_TYPE}/restart.sh" ]]; then
      units_str="$(bash "${type_dir}/${SERVICE_TYPE}/restart.sh")"
    else
      units_str="${APP_UNIT_NAME}"
    fi
    read -r -a units <<< "$units_str"

    log_info "Restarting units: ${units[*]}"
    for u in "${units[@]}"; do
      ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no root@${VM_IP} "systemctl restart $u && systemctl status $u --no-pager | head -n 8" || {
        log_error "Failed to restart unit: $u"; exit 1;
      }
    done
    log_info "Restart completed"
}

show_status() {
    log_info "$SERVICE_NAME Status (VM: ${VM_IP})"
    echo ""
    
    ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no root@${VM_IP} "
        echo '🔍 Service Status:'
        systemctl status $SERVICE_NAME --no-pager || echo 'Service not found'
        echo ''
        echo '🌐 Network Status:'
        ss -tlnp | grep :${APP_PORT:-3000} || echo 'Port not listening'
        echo ''
        echo '💾 System Resources:'
        free -h
        echo ''
        df -h /
    "
}

show_logs() {
    log_info "$SERVICE_NAME Logs (VM: ${VM_IP})"
    echo ""
    
    ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no root@${VM_IP} "
        echo '📝 Recent Application Logs:'
        journalctl -u $SERVICE_NAME --no-pager -n 50
    "
}

restart_service() {
    log_info "Restarting $SERVICE_NAME (VM: ${VM_IP})"
    # Prepare a minimal, transient inventory and run service-type restart playbook if present
    TYPE_DIR="${SCRIPT_DIR}/../../deployment-templates/service-types"
    SERVICE_TYPE_CFG=$(grep -E '^service_type:' service-config.yml 2>/dev/null | awk -F: '{print $2}' | xargs || true)
    RESTART_PLAY=""
    if [[ -n "${SERVICE_TYPE_CFG}" && -f "${TYPE_DIR}/${SERVICE_TYPE_CFG}/restart.yml.j2" ]]; then
        # Render restart playbook by simple token replacement (service_name)
        TMP_RESTART="/tmp/${SERVICE_NAME}-restart.yml"
        sed "s/{{ service_name }}/${SERVICE_NAME}/g" "${TYPE_DIR}/${SERVICE_TYPE_CFG}/restart.yml.j2" > "$TMP_RESTART"
        # Create transient inventory
        cat > /tmp/inventory.ini <<EOF_INV
[proxmox_containers]
${VM_IP} ansible_user=root ansible_ssh_private_key_file=${SSH_KEY_PATH}
EOF_INV
        ansible-playbook -i /tmp/inventory.ini "$TMP_RESTART" -e "@group_vars/all.yml"
        rm -f "$TMP_RESTART" /tmp/inventory.ini
        log_info "Restart via Ansible completed"
    else
        # Fallback to unit-based restart
        restart_units
    fi
}

show_system_info() {
    log_info "$SERVICE_NAME System Information (VM: ${VM_IP})"
    echo ""
    
    ssh -i "${SSH_KEY_PATH}" root@${VM_IP} "
        echo '🖥️  System Information:'
        uname -a
        echo ''
        echo '🕒 Uptime:'
        uptime
        echo ''
        echo '💾 Memory Usage:'
        free -h
        echo ''
        echo '💽 Disk Usage:'
        df -h
        echo ''
        echo '🔄 Running Processes:'
        ps aux | grep -E '(bun|node|$SERVICE_NAME)' | grep -v grep || echo 'No application processes found'
    "
}

show_deployment_info() {
    echo "📋 $SERVICE_NAME Deployment Information"
    echo "======================================="
    echo ""
    echo "VM IP: ${VM_IP}"
    
    if [[ -f "env.service" ]]; then
        source env.service
        echo "Application Port: ${APP_PORT}"
        echo "Service Name: ${SERVICE_NAME}"
        
        if [[ -f "../../global-config/env.proxmox.global" ]]; then
            source ../../global-config/env.proxmox.global
            if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
                echo "Public URL: https://${APP_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"
            fi
        fi
    fi
    
    echo ""
    echo "🔗 Quick Links:"
    echo "  Local: http://${VM_IP}:${APP_PORT:-3000}"
    echo "  Health: http://${VM_IP}:${APP_PORT:-3000}/health"
    echo ""
    echo "🔧 Management:"
    echo "  SSH: ssh -i ~/.ssh/id_proxmox root@${VM_IP}"
    echo "  Logs: ./manage.sh logs"
    echo "  Status: ./manage.sh status"
    echo "  Restart: ./manage.sh restart"
}

# Main execution
case "${1:-help}" in
    status)
        check_vm_access
        show_status
        ;;
    logs)
        check_vm_access
        show_logs
        ;;
    restart)
        check_vm_access
        restart_service
        ;;
    system)
        check_vm_access
        show_system_info
        ;;
    info)
        show_deployment_info
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
EOF

chmod +x "$DEPLOYMENT_DIR/manage.sh"

# Create cleanup script
cat > "$DEPLOYMENT_DIR/cleanup.sh" << 'EOF'
#!/bin/bash

# Service cleanup script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="$(basename "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🧹 Cleanup $SERVICE_NAME Deployment"
echo "===================================="

# Load configurations
if [[ -f "../../global-config/env.proxmox.global" ]]; then
    source ../../global-config/env.proxmox.global
fi

if [[ -f "env.service" ]]; then
    source env.service
fi

if [[ ! -f "vm_ip.txt" ]]; then
    log_warn "No deployment found for $SERVICE_NAME"
    exit 0
fi

VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')

echo "⚠️  This will permanently delete:"
echo "   • VM/Container with ID: ${VM_ID}"
echo "   • All data in the container"
echo "   • Service configuration"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r

if [[ "$REPLY" != "yes" ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

log_info "Stopping container..."

# Stop container
STOP_RESPONSE=$(curl -k -s -X POST \
  -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
  "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/lxc/${VM_ID}/status/stop" 2>/dev/null || echo '{"errors":["Failed to stop"]}')

if echo "$STOP_RESPONSE" | grep -q '"data"'; then
    log_info "Container stopped successfully"
else
    log_warn "Container may already be stopped"
fi

sleep 5

log_info "Removing container..."

# Remove container
DELETE_RESPONSE=$(curl -k -s -X DELETE \
  -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
  "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/lxc/${VM_ID}" 2>/dev/null || echo '{"errors":["Failed to delete"]}')

if echo "$DELETE_RESPONSE" | grep -q '"data"'; then
    log_info "Container removed successfully"
else
    log_error "Failed to remove container - it may not exist"
fi

# Clean up local files
rm -f vm_ip.txt

log_info "✅ $SERVICE_NAME cleanup completed"
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
echo "   • manage.sh           - Management script"
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
 
