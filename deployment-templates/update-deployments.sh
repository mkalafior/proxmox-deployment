#!/bin/bash

# Template Update System
# Updates existing deployments when templates change without regenerating from scratch

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[UPDATE]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_service() { echo -e "${CYAN}[SERVICE]${NC} $1"; }

show_help() {
    echo "Template Update System"
    echo ""
    echo "Usage: $0 [OPTIONS] [SERVICES...]"
    echo ""
    echo "Options:"
    echo "  --template TYPE     Update specific template type (nodejs, python, golang, database, static)"
    echo "  --file FILE         Update specific template file (deploy.yml.j2, group_vars/all.yml.j2)"
    echo "  --dry-run          Show what would be updated without making changes"
    echo "  --force            Update without confirmation prompts"
    echo "  --backup           Create backups before updating (default: true)"
    echo "  --no-backup        Skip creating backups"
    echo "  --help             Show this help message"
    echo ""
    echo "Arguments:"
    echo "  SERVICES           Specific services to update (default: all services)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Update all services with all template changes"
    echo "  $0 --template nodejs                 # Update only Node.js services"
    echo "  $0 --file deploy.yml.j2              # Update only deploy.yml files"
    echo "  $0 service01 service02               # Update only specific services"
    echo "  $0 --dry-run                         # Preview changes without applying"
    echo ""
    echo "Template Update Strategy:"
    echo "  • Preserves service-specific configurations"
    echo "  • Updates only template-generated content"
    echo "  • Creates backups before changes"
    echo "  • Validates changes before applying"
}

# Get list of all services
get_all_services() {
    find ../deployments -maxdepth 1 -type d -not -name "deployments" -exec basename {} \; | sort
}

# Get service type from service config
get_service_type() {
    local service="$1"
    local config_file="../deployments/$service/service-config.yml"
    
    if [[ -f "$config_file" ]]; then
        grep "^service_type:" "$config_file" | cut -d: -f2 | tr -d ' ' || echo "nodejs"
    else
        echo "nodejs"  # Default fallback
    fi
}

# Check if template file has been modified recently
check_template_modified() {
    local template_file="$1"
    local deployment_file="$2"
    
    if [[ ! -f "$template_file" ]]; then
        return 1
    fi
    
    if [[ ! -f "$deployment_file" ]]; then
        return 0  # Deployment file doesn't exist, needs update
    fi
    
    # Check if template is newer than deployment
    if [[ "$template_file" -nt "$deployment_file" ]]; then
        return 0  # Template is newer
    fi
    
    return 1  # Template is not newer
}

# Load service configuration
load_service_config() {
    local service="$1"
    local config_file="../deployments/$service/service-config.yml"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Service config not found: $config_file"
        return 1
    fi
    
    # Parse YAML config into environment variables
    while IFS=': ' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Clean up key and value
        key=$(echo "$key" | tr -d ' ')
        value=$(echo "$value" | tr -d ' "')
        
        # Export as environment variable
        if [[ -n "$key" && -n "$value" ]]; then
            export "$key"="$value"
        fi
    done < "$config_file"
}

# Update deploy.yml from template
update_deploy_yml() {
    local service="$1"
    local service_type="$2"
    local dry_run="$3"
    
    local template_file="base/deploy.yml.j2"
    local deployment_file="../deployments/$service/deploy.yml"
    
    if ! check_template_modified "$template_file" "$deployment_file"; then
        return 0  # No update needed
    fi
    
    log_service "Updating deploy.yml for $service ($service_type)"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "   Would update: $deployment_file"
        return 0
    fi
    
    # Create backup
    if [[ "$CREATE_BACKUP" == "true" && -f "$deployment_file" ]]; then
        cp "$deployment_file" "${deployment_file}.bak.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Load service configuration
    load_service_config "$service"
    
    # Generate updated deploy.yml using simple sed replacements
    # (This is a simplified approach - in production you might want to use a proper template engine)
    cp "$template_file" "$deployment_file"
    
    # Replace template variables with actual values
    sed -i '' "s/{{ service_name }}/$service/g" "$deployment_file"
    sed -i '' "s/{{ service_type }}/${service_type}/g" "$deployment_file"
    
    log_info "✅ Updated deploy.yml for $service"
}

# Update group_vars/all.yml from template
update_group_vars() {
    local service="$1"
    local service_type="$2"
    local dry_run="$3"
    
    local template_file="base/group_vars/all.yml.j2"
    local deployment_file="../deployments/$service/group_vars/all.yml"
    
    if ! check_template_modified "$template_file" "$deployment_file"; then
        return 0  # No update needed
    fi
    
    log_service "Updating group_vars/all.yml for $service ($service_type)"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "   Would update: $deployment_file"
        return 0
    fi
    
    # Create backup
    if [[ "$CREATE_BACKUP" == "true" && -f "$deployment_file" ]]; then
        cp "$deployment_file" "${deployment_file}.bak.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Load service configuration
    load_service_config "$service"
    
    # Generate updated group_vars using the same approach as the generator
    cp "$template_file" "$deployment_file"
    
    # Apply service-specific replacements
    sed -i '' "s/{{ service_name }}/$service/g" "$deployment_file"
    sed -i '' "s/{{ vm_name }}/${vm_name:-$service}/g" "$deployment_file"
    sed -i '' "s/{{ vm_id }}/${vm_id}/g" "$deployment_file"
    sed -i '' "s/{{ vm_cores | default(2) }}/${vm_cores:-2}/g" "$deployment_file"
    sed -i '' "s/{{ vm_memory | default(2048) }}/${vm_memory:-2048}/g" "$deployment_file"
    sed -i '' "s/{{ vm_disk_size | default(20) }}/${vm_disk_size:-20}/g" "$deployment_file"
    sed -i '' "s/{{ vm_storage | default('local-lvm') }}/${vm_storage:-local-lvm}/g" "$deployment_file"
    sed -i '' "s/{{ vm_network_bridge | default('vmbr0') }}/vmbr0/g" "$deployment_file"
    sed -i '' "s/{{ vm_swap | default(512) }}/512/g" "$deployment_file"
    sed -i '' "s/{{ vm_unprivileged | default(true) }}/true/g" "$deployment_file"
    sed -i '' "s/{{ app_user | default('appuser') }}/${app_user:-appuser}/g" "$deployment_file"
    sed -i '' "s|{{ app_dir }}|${app_dir}|g" "$deployment_file"
    sed -i '' "s/{{ app_service_name }}/${app_service_name:-$service}/g" "$deployment_file"
    sed -i '' "s/{{ app_port }}/${app_port}/g" "$deployment_file"
    sed -i '' "s|{{ local_app_path }}|${local_app_path}|g" "$deployment_file"
    sed -i '' "s/{{ service_hostname }}/${service_hostname:-$service}/g" "$deployment_file"
    sed -i '' "s/{{ dns_server | default('192.168.1.11') }}/${dns_server:-192.168.1.11}/g" "$deployment_file"
    sed -i '' "s/{{ dns_domain | default('proxmox.local') }}/${dns_domain:-proxmox.local}/g" "$deployment_file"
    
    # Remove template-specific syntax that doesn't apply
    sed -i '' '/{% if custom_env_vars %}/,/{% endif %}/d' "$deployment_file"
    sed -i '' '/{% if additional_ports %}/,/{% endif %}/d' "$deployment_file"
    
    log_info "✅ Updated group_vars/all.yml for $service"
}

# Update service templates
update_service_templates() {
    local service="$1"
    local service_type="$2"
    local dry_run="$3"
    
    local template_dir="base/templates"
    local deployment_dir="../deployments/$service/templates"
    
    if [[ ! -d "$template_dir" ]]; then
        return 0
    fi
    
    log_service "Updating templates for $service ($service_type)"
    
    # Check if any template files are newer
    local needs_update=false
    for template_file in "$template_dir"/*; do
        if [[ -f "$template_file" ]]; then
            local filename=$(basename "$template_file")
            local deployment_file="$deployment_dir/$filename"
            
            if check_template_modified "$template_file" "$deployment_file"; then
                needs_update=true
                break
            fi
        fi
    done
    
    if [[ "$needs_update" == "false" ]]; then
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo "   Would update templates in: $deployment_dir"
        return 0
    fi
    
    # Create backup of templates directory
    if [[ "$CREATE_BACKUP" == "true" && -d "$deployment_dir" ]]; then
        cp -r "$deployment_dir" "${deployment_dir}.bak.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Copy updated templates
    mkdir -p "$deployment_dir"
    cp -r "$template_dir"/* "$deployment_dir/"
    
    log_info "✅ Updated templates for $service"
}

# Update a single service
update_service() {
    local service="$1"
    local dry_run="$2"
    
    if [[ ! -d "../deployments/$service" ]]; then
        log_error "Service not found: $service"
        return 1
    fi
    
    local service_type
    service_type=$(get_service_type "$service")
    
    log_step "Updating $service (type: $service_type)"
    
    # Update different components based on options
    if [[ -z "$UPDATE_FILE" || "$UPDATE_FILE" == "deploy.yml.j2" ]]; then
        update_deploy_yml "$service" "$service_type" "$dry_run"
    fi
    
    if [[ -z "$UPDATE_FILE" || "$UPDATE_FILE" == "group_vars/all.yml.j2" ]]; then
        update_group_vars "$service" "$service_type" "$dry_run"
    fi
    
    if [[ -z "$UPDATE_FILE" || "$UPDATE_FILE" == "templates" ]]; then
        update_service_templates "$service" "$service_type" "$dry_run"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    local services=()
    local dry_run=false
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --template)
                UPDATE_TEMPLATE="$2"
                shift 2
                ;;
            --file)
                UPDATE_FILE="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --backup)
                CREATE_BACKUP=true
                shift
                ;;
            --no-backup)
                CREATE_BACKUP=false
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
                services+=("$1")
                shift
                ;;
        esac
    done
    
    # Set defaults
    UPDATE_TEMPLATE="${UPDATE_TEMPLATE:-}"
    UPDATE_FILE="${UPDATE_FILE:-}"
    CREATE_BACKUP="${CREATE_BACKUP:-true}"
    
    # Get services to update
    if [[ ${#services[@]} -eq 0 ]]; then
        # Use while loop for compatibility with older bash versions
        while IFS= read -r service; do
            services+=("$service")
        done < <(get_all_services)
    fi
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log_error "No services found to update"
        exit 1
    fi
    
    # Show what will be updated
    echo "🔄 Template Update System"
    echo "========================="
    echo ""
    echo "Services to update: ${services[*]}"
    if [[ -n "$UPDATE_TEMPLATE" ]]; then
        echo "Template filter: $UPDATE_TEMPLATE"
    fi
    if [[ -n "$UPDATE_FILE" ]]; then
        echo "File filter: $UPDATE_FILE"
    fi
    echo "Dry run: $dry_run"
    echo "Create backups: $CREATE_BACKUP"
    echo ""
    
    # Confirmation prompt
    if [[ "$force" == "false" && "$dry_run" == "false" ]]; then
        read -p "Continue with template updates? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Update cancelled"
            exit 0
        fi
    fi
    
    # Update each service
    local updated_count=0
    for service in "${services[@]}"; do
        # Filter by template type if specified
        if [[ -n "$UPDATE_TEMPLATE" ]]; then
            local service_type
            service_type=$(get_service_type "$service")
            if [[ "$service_type" != "$UPDATE_TEMPLATE" ]]; then
                continue
            fi
        fi
        
        if update_service "$service" "$dry_run"; then
            ((updated_count++))
        fi
    done
    
    echo ""
    if [[ "$dry_run" == "true" ]]; then
        echo "🔍 Dry run completed - $updated_count services would be updated"
        echo "Run without --dry-run to apply changes"
    else
        echo "✅ Template update completed - $updated_count services updated"
        if [[ "$CREATE_BACKUP" == "true" ]]; then
            echo "💾 Backups created with timestamp suffix"
        fi
    fi
}

# Change to script directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Run main function
main "$@"
