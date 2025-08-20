#!/bin/bash

# Clean Environment Loader
# Prevents environment variable pollution between service configurations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[ENV]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[ENV]${NC} $1"; }
log_error() { echo -e "${RED}[ENV]${NC} $1"; }

# Function to clean service-specific environment variables
clean_service_env() {
    # List of service-specific variables that should be reset
    local service_vars=(
        "SERVICE_NAME"
        "VM_ID"
        "APP_PORT"
        "APP_SUBDOMAIN"
        "SERVICE_HOSTNAME"
        "VM_CORES"
        "VM_MEMORY"
        "VM_DISK_SIZE"
        "DB_NAME"
        "DB_USER"
        "DB_PASSWORD"
        "RUNTIME_VARIANT"
        "APP_MAIN_FILE"
    )
    
    # Unset all service-specific variables
    for var in "${service_vars[@]}"; do
        unset "$var"
    done
}

# Function to load global configuration
load_global_config() {
    local global_config_file="$1"
    
    if [[ ! -f "$global_config_file" ]]; then
        log_error "Global config file not found: $global_config_file"
        return 1
    fi
    
    log_info "Loading global configuration from $global_config_file"
    source "$global_config_file"
}

# Function to load service-specific configuration
load_service_config() {
    local service_config_file="$1"
    
    if [[ ! -f "$service_config_file" ]]; then
        log_warn "Service config file not found: $service_config_file (using defaults)"
        return 0
    fi
    
    log_info "Loading service configuration from $service_config_file"
    source "$service_config_file"
}

# Function to validate required variables
validate_env() {
    local required_vars=(
        "PROXMOX_HOST"
        "SERVICE_NAME"
        "VM_ID"
        "APP_PORT"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        # Use eval to get variable value (compatible with older bash)
        local var_value
        eval "var_value=\${${var}:-}"
        if [[ -z "$var_value" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        return 1
    fi
    
    log_info "Environment validation passed"
    return 0
}

# Function to show current environment
show_env() {
    echo ""
    echo "🔧 Current Environment:"
    echo "   Service: ${SERVICE_NAME:-not set}"
    echo "   VM ID: ${VM_ID:-not set}"
    echo "   Port: ${APP_PORT:-not set}"
    echo "   Subdomain: ${APP_SUBDOMAIN:-not set}"
    echo "   Hostname: ${SERVICE_HOSTNAME:-not set}"
    echo "   Proxmox Host: ${PROXMOX_HOST:-not set}"
    echo "   Cloudflare Domain: ${CLOUDFLARE_DOMAIN:-not set}"
    echo ""
}

# Main function to load clean environment for a service
load_clean_env() {
    local service_name="$1"
    local script_dir="$2"
    
    # Determine paths
    local global_config="${script_dir}/../../global-config/env.proxmox.global"
    local service_config="${script_dir}/env.service"
    
    # Clean previous service environment
    clean_service_env
    
    # Load configurations in order
    load_global_config "$global_config" || return 1
    load_service_config "$service_config"
    
    # Set service name if not already set
    if [[ -z "$SERVICE_NAME" && -n "$service_name" ]]; then
        export SERVICE_NAME="$service_name"
    fi
    
    # Validate environment
    validate_env || return 1
    
    # Show current environment if requested
    if [[ "${SHOW_ENV:-}" == "true" ]]; then
        show_env
    fi
    
    return 0
}

# If script is called directly (not sourced), show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Clean Environment Loader"
    echo ""
    echo "Usage: source load-env.sh && load_clean_env <service-name> <script-dir>"
    echo ""
    echo "Example:"
    echo "  source ../../global-config/load-env.sh"
    echo "  load_clean_env python-api \"\$(pwd)\""
    echo ""
    echo "Environment variables will be cleanly loaded without pollution."
fi
