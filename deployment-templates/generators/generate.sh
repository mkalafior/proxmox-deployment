#!/bin/bash

# Unified Service Generator
# Replaces: generate-multi-service.sh, generate-service-deployment.sh, create-service-from-template.sh
# Follows KISS and DRY principles

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_service() { echo -e "${CYAN}[SERVICE]${NC} $1"; }

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_ROOT="${TEMPLATES_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
TEMPLATES_BASE="${TEMPLATES_ROOT}/deployment-templates"
TARGET_PROJECT_ROOT="${PROJECT_ROOT_OVERRIDE:-${TEMPLATES_ROOT}}"

# Available service types
AVAILABLE_TYPES=(nodejs python golang database static tor-proxy)

# Default values
DEFAULT_VM_CORES=2
DEFAULT_VM_MEMORY=2048
DEFAULT_VM_DISK_SIZE=20
DEFAULT_APP_USER="appuser"

show_help() {
    echo "🚀 Unified Service Generator"
    echo "Generates both service code and deployment configuration"
    echo ""
    echo "Usage: $0 <service-name> --type <service-type> --port <port> --node <node> [options]"
    echo ""
    echo "Required:"
    echo "  service-name    Name of the service"
    echo "  --type TYPE     Service type: ${AVAILABLE_TYPES[*]}"
    echo "  --port PORT     Application port"
    echo "  --node NODE     Proxmox node name"
    echo ""
    echo "Service Options:"
    echo "  --runtime RT    Runtime variant (nodejs: node|bun, database: postgresql|mysql|redis)"
    echo "  --main-file F   Main application file (default varies by type)"
    echo ""
    echo "VM Options:"
    echo "  --vm-id ID      VM ID (auto-selected if not specified)"
    echo "  --cores N       CPU cores (default: $DEFAULT_VM_CORES)"
    echo "  --memory MB     Memory in MB (default: $DEFAULT_VM_MEMORY)"
    echo "  --disk GB       Disk size in GB (default: $DEFAULT_VM_DISK_SIZE)"
    echo ""
    echo "Other Options:"
    echo "  --subdomain SUB Cloudflare subdomain"
    echo "  --hostname HOST Service hostname (defaults to service-name)"
    echo "  --user USER     Application user (default: $DEFAULT_APP_USER)"
    echo "  --force         Overwrite existing files"
    echo "  --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 api-service --type nodejs --runtime bun --port 3000"
    echo "  $0 my-db --type database --runtime postgresql --port 5432"
    echo "  $0 frontend --type static --port 80"
}

# Parse arguments
SERVICE_NAME=""
SERVICE_TYPE=""
RUNTIME_VARIANT=""
APP_PORT=""
PROXMOX_NODE=""
VM_ID=""
VM_CORES="$DEFAULT_VM_CORES"
VM_MEMORY="$DEFAULT_VM_MEMORY"
VM_DISK_SIZE="$DEFAULT_VM_DISK_SIZE"
APP_USER="$DEFAULT_APP_USER"
APP_SUBDOMAIN=""
SERVICE_HOSTNAME=""
APP_MAIN_FILE=""
FORCE_OVERWRITE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --type) SERVICE_TYPE="$2"; shift 2 ;;
        --runtime) RUNTIME_VARIANT="$2"; shift 2 ;;
        --port) APP_PORT="$2"; shift 2 ;;
        --node) PROXMOX_NODE="$2"; shift 2 ;;
        --vm-id) VM_ID="$2"; shift 2 ;;
        --cores) VM_CORES="$2"; shift 2 ;;
        --memory) VM_MEMORY="$2"; shift 2 ;;
        --disk) VM_DISK_SIZE="$2"; shift 2 ;;
        --user) APP_USER="$2"; shift 2 ;;
        --subdomain) APP_SUBDOMAIN="$2"; shift 2 ;;
        --hostname) SERVICE_HOSTNAME="$2"; shift 2 ;;
        --main-file) APP_MAIN_FILE="$2"; shift 2 ;;
        --force) FORCE_OVERWRITE=true; shift ;;
        --help) show_help; exit 0 ;;
        -*) log_error "Unknown option: $1"; show_help; exit 1 ;;
        *) 
            if [[ -z "$SERVICE_NAME" ]]; then
                SERVICE_NAME="$1"
            else
                log_error "Unexpected argument: $1"
                exit 1
            fi
            shift ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVICE_NAME" ]]; then
    log_error "Missing required argument: service-name"
    show_help
    exit 1
fi

# Check if this is an update (existing deployment exists)  
DEPLOYMENT_DIR="$TARGET_PROJECT_ROOT/deployments/$SERVICE_NAME"
UPDATE_MODE=false
if [[ -d "$DEPLOYMENT_DIR" && -f "$DEPLOYMENT_DIR/service-config.yml" ]]; then
    UPDATE_MODE=true
    log_info "🔄 Existing deployment detected, entering update mode"
    
    # Read existing configuration from service-config.yml
    if [[ -z "$SERVICE_TYPE" ]]; then
        SERVICE_TYPE=$(grep -E '^service_type:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || true)
    fi
    if [[ -z "$APP_PORT" ]]; then
        APP_PORT=$(grep -E '^app_port:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || true)
    fi
    if [[ -z "$PROXMOX_NODE" ]]; then
        PROXMOX_NODE=$(grep -E '^proxmox_node:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || true)
    fi
    if [[ -z "$VM_ID" ]]; then
        VM_ID=$(grep -E '^vm_id:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || true)
    fi
    if [[ -z "$RUNTIME_VARIANT" ]]; then
        # Try to detect runtime variant from existing config
        if [[ "$SERVICE_TYPE" == "nodejs" ]]; then
            RUNTIME_VARIANT=$(grep -E '^nodejs_runtime:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || true)
        elif [[ "$SERVICE_TYPE" == "database" ]]; then
            RUNTIME_VARIANT=$(grep -E '^database_runtime:' "$DEPLOYMENT_DIR/service-config.yml" | awk -F: '{print $2}' | xargs || true)
        fi
    fi
    
    log_info "📋 Read from existing config: type=$SERVICE_TYPE, port=$APP_PORT, node=$PROXMOX_NODE"
fi

# Validate required arguments (only if not in update mode or values still missing)
if [[ -z "$SERVICE_TYPE" ]]; then
    log_error "Missing required argument: --type"
    show_help
    exit 1
fi

if [[ -z "$APP_PORT" ]]; then
    log_error "Missing required argument: --port"
    show_help
    exit 1
fi

if [[ -z "$PROXMOX_NODE" ]]; then
    log_error "Missing required argument: --node"
    show_help
    exit 1
fi

# Validate service type
if [[ ! " ${AVAILABLE_TYPES[*]} " =~ " ${SERVICE_TYPE} " ]]; then
    log_error "Invalid service type: $SERVICE_TYPE"
    log_error "Available types: ${AVAILABLE_TYPES[*]}"
    exit 1
fi

# Validate port is numeric
if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
    log_error "Port must be a number: $APP_PORT"
    exit 1
fi

# Set defaults
SERVICE_HOSTNAME="${SERVICE_HOSTNAME:-$SERVICE_NAME}"

# Function to get next available VM ID from Proxmox
get_next_vm_id() {
    # Check if we have required Proxmox credentials
    if [[ -z "${PROXMOX_HOST:-}" || -z "${TOKEN_ID:-}" || -z "${TOKEN_SECRET:-}" ]]; then
        log_error "Missing Proxmox credentials (PROXMOX_HOST, TOKEN_ID, TOKEN_SECRET)"
        log_error "Cannot auto-assign VM ID. Please provide --vm-id explicitly"
        return 1
    fi
    
    # Get list of existing VM IDs
    local url="https://${PROXMOX_HOST}:8006/api2/json/cluster/resources?type=vm"
    local response
    response=$(curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" "$url" 2>/dev/null)
    
    if [[ $? -ne 0 || -z "$response" ]]; then
        log_error "Failed to connect to Proxmox API at $PROXMOX_HOST"
        return 1
    fi
    
    # Extract VM IDs and find next available
    local existing_ids
    if command -v jq >/dev/null 2>&1; then
        existing_ids=$(echo "$response" | jq -r '.data[]?.vmid // empty' | sort -n)
    else
        # Fallback without jq
        existing_ids=$(echo "$response" | grep -o '"vmid":[0-9]*' | cut -d: -f2 | sort -n)
    fi
    
    # Find next available ID starting from 100
    local next_id=100
    for id in $existing_ids; do
        if [[ $next_id -eq $id ]]; then
            ((next_id++))
        elif [[ $next_id -lt $id ]]; then
            break
        fi
    done
    
    echo "$next_id"
}

# Handle VM ID - only exception to strict validation
if [[ -z "$VM_ID" ]]; then
    log_info "VM ID not provided, attempting to auto-assign..."
    VM_ID=$(get_next_vm_id)
    if [[ -z "$VM_ID" ]]; then
        log_error "Could not auto-assign VM ID. Please provide --vm-id explicitly"
        exit 1
    fi
    log_info "Auto-assigned VM ID: $VM_ID"
else
    # Validate provided VM ID is numeric
    if ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
        log_error "VM ID must be a number: $VM_ID"
        exit 1
    fi
fi

# Load service type configuration
SERVICE_CONFIG_FILE="$TEMPLATES_BASE/service-types/$SERVICE_TYPE/config.yml"
if [[ ! -f "$SERVICE_CONFIG_FILE" ]]; then
    log_error "Service type configuration not found: $SERVICE_CONFIG_FILE"
    exit 1
fi

log_info "🚀 Generating service: $SERVICE_NAME ($SERVICE_TYPE)"
log_info "   Port: $APP_PORT"
log_info "   Runtime: ${RUNTIME_VARIANT:-default}"

# Set up paths
SERVICE_DIR="$TARGET_PROJECT_ROOT/services/$SERVICE_NAME"
# DEPLOYMENT_DIR already defined earlier for update mode detection

# Create service starter files (if directory doesn't exist)
create_service_files() {
    if [[ -d "$SERVICE_DIR" ]]; then
        log_info "Service directory exists, skipping starter files: $SERVICE_DIR"
        return 0
    fi

    log_step "Creating service starter files..."
    
    local starter_dir="$TEMPLATES_BASE/service-types/$SERVICE_TYPE/starter"
    if [[ ! -d "$starter_dir" ]]; then
        log_warn "No starter templates found for $SERVICE_TYPE"
        mkdir -p "$SERVICE_DIR"
        echo "# $SERVICE_NAME ($SERVICE_TYPE)" > "$SERVICE_DIR/README.md"
        return 0
    fi

    mkdir -p "$SERVICE_DIR"
    
    # Process starter templates
    local template_vars="{\"service_name\":\"$SERVICE_NAME\",\"app_port\":\"$APP_PORT\""
    [[ -n "$RUNTIME_VARIANT" ]] && template_vars+=",\"${SERVICE_TYPE}_runtime\":\"$RUNTIME_VARIANT\""
    [[ -n "$APP_MAIN_FILE" ]] && template_vars+=",\"app_main_file\":\"$APP_MAIN_FILE\""
    template_vars+="}"

    find "$starter_dir" -name "*.j2" -type f | while read -r template_file; do
        local relative_path="${template_file#$starter_dir/}"
        local output_file="$SERVICE_DIR/${relative_path%.j2}"
        
        # Skip if file exists (don't overwrite)
        if [[ -f "$output_file" && "$FORCE_OVERWRITE" != "true" ]]; then
            log_info "  Skipping existing: $(basename "$output_file")"
            continue
        fi
        
        # Create output directory
        mkdir -p "$(dirname "$output_file")"
        
        # Process template
        if command -v j2 >/dev/null 2>&1; then
            echo "$template_vars" | j2 "$template_file" -f json -o "$output_file"
            log_info "  Created: $(basename "$output_file")"
        else
            # Fallback: simple variable substitution
            sed "s/{{ service_name }}/$SERVICE_NAME/g; s/{{ app_port }}/$APP_PORT/g" "$template_file" > "$output_file"
            log_info "  Created: $(basename "$output_file") (basic substitution)"
        fi
    done
}

# Create deployment configuration
create_deployment_config() {
    log_step "Creating deployment configuration..."
    
    mkdir -p "$DEPLOYMENT_DIR"/{templates,scripts}
    
    # Generate service-config.yml
    if [[ -f "$DEPLOYMENT_DIR/service-config.yml" && "$FORCE_OVERWRITE" != "true" ]]; then
        log_info "Preserving existing service-config.yml"
    else
        log_info "Generating service-config.yml from template..."
        
        # Create temporary variables file for Ansible
        local temp_vars_file="/tmp/service-vars-$$.yml"
        cat > "$temp_vars_file" << EOF
---
service_name: "$SERVICE_NAME"
service_type: "$SERVICE_TYPE"
service_hostname: "$SERVICE_HOSTNAME"
app_subdomain: "$APP_SUBDOMAIN"
vm_name: "$SERVICE_NAME"
vm_id: $VM_ID
vm_cores: $VM_CORES
vm_memory: $VM_MEMORY
vm_disk_size: $VM_DISK_SIZE
vm_storage: "local-lvm"
vm_network_bridge: "vmbr0"
vm_swap: 512
vm_unprivileged: true
app_name: "$SERVICE_NAME"
app_user: "$APP_USER"
app_dir: "/opt/$SERVICE_NAME"
app_service_name: "$SERVICE_NAME"
app_port: $APP_PORT
app_main_file: "${APP_MAIN_FILE:-index.js}"
local_app_path: "../../services/$SERVICE_NAME"
proxmox_node: "$PROXMOX_NODE"
runtime_variant: "${RUNTIME_VARIANT:-}"
EOF

        # Use Ansible to render the template
        ansible localhost -m template \
            -a "src=$TEMPLATES_BASE/base/templates/service-config.yml.j2 dest=$DEPLOYMENT_DIR/service-config.yml" \
            -e "@$temp_vars_file" \
            --connection=local >/dev/null 2>&1
        
        # Clean up temporary file
        rm -f "$temp_vars_file"
        
        if [[ -f "$DEPLOYMENT_DIR/service-config.yml" ]]; then
            log_info "Created service-config.yml from template"
        else
            log_error "Failed to generate service-config.yml from template"
            exit 1
        fi
    fi
    
    # Copy service-specific templates (priority)
    local service_templates_dir="$TEMPLATES_BASE/service-types/$SERVICE_TYPE"
    if [[ -d "$service_templates_dir" ]]; then
        # Copy systemd service template
        if [[ -f "$service_templates_dir/systemd.service.j2" ]]; then
            cp "$service_templates_dir/systemd.service.j2" "$DEPLOYMENT_DIR/templates/$SERVICE_NAME.service.j2"
            log_info "  ✓ Service-specific systemd template"
        fi
        
        # Copy other service-specific templates
        find "$service_templates_dir" -name "*.j2" -not -path "*/starter/*" | while read -r template; do
            local template_name=$(basename "$template")
            local target="$DEPLOYMENT_DIR/templates/$template_name"
            if [[ ! -f "$target" ]]; then
                cp "$template" "$target"
                log_info "  ✓ Service template: $template_name"
            fi
        done
    fi
    
    # Copy base templates (fallback only)
    local base_templates_dir="$TEMPLATES_BASE/base/templates"
    if [[ -d "$base_templates_dir" ]]; then
        find "$base_templates_dir" -name "*.j2" -o -name "*.yml" | while read -r template; do
            local template_name=$(basename "$template")
            local target="$DEPLOYMENT_DIR/templates/$template_name"
            if [[ ! -f "$target" ]]; then
                cp "$template" "$target"
                log_info "  ✓ Base template: $template_name"
            fi
        done
    fi
    
    # Generate deploy.yml - check for service-specific template first
    local service_deploy_template="$TEMPLATES_BASE/service-types/$SERVICE_TYPE/deploy.yml.j2"
    local base_deploy_template="$TEMPLATES_BASE/base/deploy.yml.j2"
    local merge_script="$SCRIPT_DIR/merge_templates.py"
    
    if [[ -f "$service_deploy_template" ]]; then
        # Use service-specific deploy template directly (copy as-is, uses Ansible variables)
        cp "$service_deploy_template" "$DEPLOYMENT_DIR/deploy.yml"
        log_info "Created deploy.yml (service-specific template)"
    elif [[ -f "$base_deploy_template" && -f "$merge_script" ]]; then
        # Use base template with merger for other service types
        if python3 "$merge_script" "$base_deploy_template" "$TEMPLATES_BASE/service-types/$SERVICE_TYPE" "$DEPLOYMENT_DIR/deploy.yml" "$SERVICE_NAME"; then
            log_info "Created merged deploy.yml"
        else
            log_warn "Template merging failed, using base template"
            cp "$base_deploy_template" "$DEPLOYMENT_DIR/deploy.yml"
        fi
    elif [[ -f "$base_deploy_template" ]]; then
        cp "$base_deploy_template" "$DEPLOYMENT_DIR/deploy.yml"
        log_info "Created deploy.yml (no merger available)"
    fi
    
    # Generate global-config.yml (shared across all deployments)
    local deployments_root="$(dirname "$DEPLOYMENT_DIR")"
    local global_config_path="$deployments_root/global-config.yml"
    local global_config_template="$TEMPLATES_BASE/base/global-config.yml.j2"
    
    if [[ ! -f "$global_config_path" && -f "$global_config_template" ]]; then
        log_info "Generating global-config.yml from template..."
        
        # Use Ansible to render the global config template
        ansible localhost -m template \
            -a "src=$global_config_template dest=$global_config_path" \
            --connection=local >/dev/null 2>&1
        
        if [[ -f "$global_config_path" ]]; then
            log_info "Created global-config.yml"
        else
            log_error "Failed to generate global-config.yml from template"
            exit 1
        fi
    elif [[ -f "$global_config_path" ]]; then
        log_info "Preserving existing global-config.yml"
    fi
    
    # Generate requirements.yml (base + service-specific template support)
    local base_requirements="$TEMPLATES_BASE/base/requirements.yml"
    local service_requirements_template="$service_templates_dir/requirements.yml.j2"
    local target_requirements="$DEPLOYMENT_DIR/requirements.yml"
    
    if [[ -f "$service_requirements_template" ]]; then
        # Render service-specific requirements template
        local template_vars="{\"service_name\":\"$SERVICE_NAME\",\"service_type\":\"$SERVICE_TYPE\""
        [[ -n "$RUNTIME_VARIANT" ]] && template_vars+=",\"database_runtime\":\"$RUNTIME_VARIANT\",\"${SERVICE_TYPE}_runtime\":\"$RUNTIME_VARIANT\""
        template_vars+="}"
        
        if command -v j2 >/dev/null 2>&1; then
            echo "$template_vars" | j2 "$service_requirements_template" -f json -o "$target_requirements"
            log_info "Created requirements.yml (service-specific template)"
        else
            # Fallback: basic substitution
            sed "s/{{ database_runtime }}/$RUNTIME_VARIANT/g; s/{{ ${SERVICE_TYPE}_runtime }}/$RUNTIME_VARIANT/g" "$service_requirements_template" > "$target_requirements"
            log_info "Created requirements.yml (basic substitution)"
        fi
    elif [[ -f "$base_requirements" ]]; then
        # Fall back to base requirements
        cp "$base_requirements" "$target_requirements"
        log_info "Created requirements.yml (base)"
    fi
    
    # Generate redeploy.yml using Python template merger (for code-based services)
    if [[ "$SERVICE_TYPE" =~ ^(nodejs|python|golang|static)$ ]]; then
        local redeploy_template="$TEMPLATES_BASE/base/redeploy.yml.j2"
        if [[ -f "$redeploy_template" && -f "$merge_script" ]]; then
            if python3 "$merge_script" "$redeploy_template" "$TEMPLATES_BASE/service-types/$SERVICE_TYPE" "$DEPLOYMENT_DIR/redeploy.yml" "$SERVICE_NAME"; then
                log_info "Created merged redeploy.yml"
            else
                log_warn "Redeploy template merging failed, using base template"
                cp "$redeploy_template" "$DEPLOYMENT_DIR/redeploy.yml"
            fi
        elif [[ -f "$redeploy_template" ]]; then
            cp "$redeploy_template" "$DEPLOYMENT_DIR/redeploy.yml"
            log_info "Created redeploy.yml (no merger available)"
        fi
    fi
    
    # Generate cleanup.yml using Python template merger
    local cleanup_template="$TEMPLATES_BASE/base/cleanup.yml.j2"
    if [[ -f "$cleanup_template" && -f "$merge_script" ]]; then
        if python3 "$merge_script" "$cleanup_template" "$TEMPLATES_BASE/service-types/$SERVICE_TYPE" "$DEPLOYMENT_DIR/cleanup.yml" "$SERVICE_NAME"; then
            log_info "Created merged cleanup.yml"
        else
            log_warn "Cleanup template merging failed, using base template"
            cp "$cleanup_template" "$DEPLOYMENT_DIR/cleanup.yml"
        fi
    elif [[ -f "$cleanup_template" ]]; then
        cp "$cleanup_template" "$DEPLOYMENT_DIR/cleanup.yml"
        log_info "Created cleanup.yml (no merger available)"
    fi
    
    # Create deployment scripts
    create_deployment_scripts
}

# Create deployment scripts (deploy.sh, redeploy.sh, cleanup.sh)
create_deployment_scripts() {
    log_step "Creating deployment scripts..."
    
    # Create shared environment loader
    cat > "$DEPLOYMENT_DIR/load-env.sh" << 'EOF'
#!/bin/bash
# Shared environment loading functions

# Auto-load .env files (search up directory tree)
load_env_files() {
    local search_dir="$(pwd)"
    for i in {1..3}; do
        if [[ -f "$search_dir/.env" ]]; then
            echo "🔧 Loading environment from: $search_dir/.env"
            set -a; source "$search_dir/.env"; set +a
            break
        fi
        local parent_dir="$(dirname "$search_dir")"
        if [[ "$parent_dir" == "$search_dir" ]]; then
            break
        fi
        search_dir="$parent_dir"
    done
}

# Load all environment sources
load_all_env() {
    # Load global configuration
    if [[ -f "../../global-config/env.proxmox.global" ]]; then
        source "../../global-config/env.proxmox.global"
    fi
    
    # Load .env files automatically
    load_env_files
    
    # Load service-specific configuration
    if [[ -f "env.service" ]]; then
        source "env.service"
    fi
}
EOF
    chmod +x "$DEPLOYMENT_DIR/load-env.sh"

    # Create deploy.sh script
    cat > "$DEPLOYMENT_DIR/deploy.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# ⚠️  RECOMMENDED: Use 'pxdcli deploy <service-name>' instead of calling this script directly
# This script requires proper environment variables to be loaded

# Load environment configuration
source "$(dirname "$0")/load-env.sh"
load_all_env

# Run Ansible playbook
echo "🚀 Deploying service..."
ansible-playbook -i localhost, deploy.yml
EOF
    chmod +x "$DEPLOYMENT_DIR/deploy.sh"
    log_info "Created deploy.sh"
    
    # Create redeploy.sh script (for code-based services only)
    if [[ "$SERVICE_TYPE" =~ ^(nodejs|python|golang|static)$ ]]; then
        cat > "$DEPLOYMENT_DIR/redeploy.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# ⚠️  RECOMMENDED: Use 'pxdcli redeploy <service-name>' instead of calling this script directly
# This script requires proper environment variables to be loaded

# Parse command line arguments
SKIP_BUILD=false
FORCE_REDEPLOY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-build)
            SKIP_BUILD=true
            shift
            ;;
        --force)
            FORCE_REDEPLOY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--no-build] [--force]"
            exit 1
            ;;
    esac
done

# Load environment configuration
source "$(dirname "$0")/load-env.sh"
load_all_env

# Set extra variables for Ansible
EXTRA_VARS=""
if [[ "$SKIP_BUILD" == "true" ]]; then
    EXTRA_VARS="$EXTRA_VARS -e skip_build=true"
fi
if [[ "$FORCE_REDEPLOY" == "true" ]]; then
    EXTRA_VARS="$EXTRA_VARS -e force_dependency_update=true"
fi

# Run Ansible playbook
echo "🔄 Redeploying service code..."
if [[ -f "redeploy.yml" ]]; then
    ansible-playbook -i localhost, redeploy.yml $EXTRA_VARS
else
    echo "❌ redeploy.yml not found. This service may not support code redeployment."
    exit 1
fi
EOF
        chmod +x "$DEPLOYMENT_DIR/redeploy.sh"
        log_info "Created redeploy.sh"
    fi
    
    # Create cleanup.sh script
    cat > "$DEPLOYMENT_DIR/cleanup.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# Load environment configuration
source "$(dirname "$0")/load-env.sh"
load_all_env

# Run Ansible playbook
echo "🧹 Cleaning up service..."
if [[ -f "cleanup.yml" ]]; then
    ansible-playbook -i localhost, cleanup.yml
else
    echo "❌ cleanup.yml not found."
    exit 1
fi
EOF
    chmod +x "$DEPLOYMENT_DIR/cleanup.sh"
    log_info "Created cleanup.sh"
}

# Main execution
main() {
    create_service_files
    create_deployment_config
    
    log_info "✅ Service generation complete!"
    echo ""
    echo "📁 Generated files:"
    echo "   Services: $SERVICE_DIR"
    echo "   Deployment: $DEPLOYMENT_DIR"
    echo ""
    echo "🚀 Next steps:"
    echo "   1. Customize service code: $SERVICE_DIR"
    echo "   2. Deploy: pxdcli deploy $SERVICE_NAME"
    if [[ "$SERVICE_TYPE" =~ ^(nodejs|python|golang|static)$ ]]; then
        echo "   3. Redeploy code changes: pxdcli redeploy $SERVICE_NAME"
    fi
}

main "$@"
