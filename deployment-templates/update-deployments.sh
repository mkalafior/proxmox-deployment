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

# TEMPLATES and TARGET PROJECT roots
# If used as a global tool, set PROJECT_ROOT_OVERRIDE to the target repo path
# and TEMPLATES_ROOT to the absolute path of the templates repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TEMPLATES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATES_ROOT="${TEMPLATES_ROOT:-${DEFAULT_TEMPLATES_ROOT}}"
TEMPLATES_BASE="${TEMPLATES_ROOT}/deployment-templates"

# Default target project is the project that contains this templates folder
TARGET_PROJECT_ROOT="${PROJECT_ROOT_OVERRIDE:-${TEMPLATES_ROOT}}"
DEPLOYMENTS_BASE="${TARGET_PROJECT_ROOT}/deployments"

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
    find "${DEPLOYMENTS_BASE}" -maxdepth 1 -type d -not -name "deployments" -exec basename {} \; | sort
}

# Get service type from service config
get_service_type() {
    local service="$1"
    local config_file="${DEPLOYMENTS_BASE}/$service/service-config.yml"
    
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
    local config_file="${DEPLOYMENTS_BASE}/$service/service-config.yml"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Service config not found: $config_file"
        return 1
    fi
    
    # Parse YAML config into environment variables
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Parse key: value pairs
        if [[ "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            # Clean up key and value
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
            
            # Export as environment variable
            if [[ -n "$key" && -n "$value" ]]; then
                export "$key"="$value"
            fi
        fi
    done < "$config_file"
}

# Update deploy.yml using new template merging system
update_deploy_yml() {
    local service="$1"
    local service_type="$2"
    local dry_run="$3"

    local deployment_file="${DEPLOYMENTS_BASE}/$service/deploy.yml"

    # Check if any template files have been modified
    local template_modified=false
    local base_template="${TEMPLATES_BASE}/base/deploy.yml.j2"
    local service_template_dir="${TEMPLATES_BASE}/service-types/${service_type}"

    # Check base template
    if [[ -f "$base_template" ]] && check_template_modified "$base_template" "$deployment_file"; then
        template_modified=true
    fi

    # Check service-specific template parts
    if [[ -d "$service_template_dir" ]]; then
        for template_part in "$service_template_dir"/*.yml.j2; do
            if [[ -f "$template_part" ]] && check_template_modified "$template_part" "$deployment_file"; then
                template_modified=true
                break
            fi
        done
    fi

    if [[ "$template_modified" == "false" ]]; then
        return 0  # No update needed
    fi

    log_service "Regenerating merged template for $service ($service_type)"

    if [[ "$dry_run" == "true" ]]; then
        echo "   Would regenerate merged template for: $service ($service_type)"
        return 0
    fi

    # Create backup
    if [[ "$CREATE_BACKUP" == "true" && -f "$deployment_file" ]]; then
        cp "$deployment_file" "${deployment_file}.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    # Load service configuration
    load_service_config "$service"

    # Source the merging script
    if [[ -f "${TEMPLATES_BASE}/generators/merge-service-template.sh" ]]; then
        source "${TEMPLATES_BASE}/generators/merge-service-template.sh"

        # Regenerate merged template
        if merge_service_template "$service" "$service_type" "${DEPLOYMENTS_BASE}/$service"; then
            log_info "✅ Updated deploy.yml for $service"
        else
            log_error "Failed to update deploy.yml for $service"
            return 1
        fi
    else
        log_error "Template merging script not found: ${TEMPLATES_BASE}/generators/merge-service-template.sh"
        return 1
    fi
}

# Update group_vars/all.yml from template
update_group_vars() {
    local service="$1"
    local service_type="$2"
    local dry_run="$3"
    
    # Prefer service-type specific template if available
    local type_template_file="${TEMPLATES_BASE}/service-types/${service_type}/group_vars/all.yml.j2"
    local template_file="${TEMPLATES_BASE}/base/group_vars/all.yml.j2"
    if [[ -f "$type_template_file" ]]; then
        template_file="$type_template_file"
    fi
    local deployment_file="${DEPLOYMENTS_BASE}/$service/group_vars/all.yml"
    
    # Check if template or service config has been modified
    local service_config="${DEPLOYMENTS_BASE}/$service/service-config.yml"
    local template_needs_update=false
    local config_needs_update=false
    
    if check_template_modified "$template_file" "$deployment_file"; then
        template_needs_update=true
    fi
    
    if [[ -f "$service_config" ]] && [[ "$service_config" -nt "$deployment_file" ]]; then
        config_needs_update=true
    fi
    
    # Decide whether to copy template; always run post-processing
    local skip_copy=false
    if [[ "$template_needs_update" == "false" && "$config_needs_update" == "false" ]]; then
        skip_copy=true
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
    if [[ "$skip_copy" == "false" ]]; then
        cp "$template_file" "$deployment_file"
    fi
    
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
    
    # Replace proxmox_node_override token if provided, but flatten the conditional safely using awk below
    if [[ -n "${proxmox_node:-}" ]]; then
        sed -i '' "s/{{ proxmox_node_override }}/${proxmox_node}/g" "$deployment_file"
    fi
    
    # Remove/flatten Jinja blocks safely without truncating the file
    tmp_file="${deployment_file}.tmp"
    awk -v has_override="${proxmox_node:-}" '
      BEGIN { in_custom=0; in_additional=0; in_pnode=0; drop_pnode=0 }
      /^\{\% if proxmox_node_override \%\}$/ {
        if (has_override!="") { in_pnode=1 } else { drop_pnode=1 }
        next
      }
      /^\{\% if custom_env_vars \%\}$/ { in_custom=1; print "# Custom env vars (none configured)"; next }
      /^\{\% if additional_ports \%\}$/ { in_additional=1; next }
      /^\{\% for key, value in custom_env_vars.items\(\) \%\}$/ { if (in_custom) next }
      /^\{\% for port in additional_ports \%\}$/ { if (in_additional) next }
      /^\{\% endfor \%\}$/ { if (in_custom || in_additional) next }
      /^\{\% endif \%\}$/ {
        if (in_pnode) { in_pnode=0; next }
        if (drop_pnode) { drop_pnode=0; next }
        if (in_custom) { in_custom=0; next }
        if (in_additional) { in_additional=0; next }
      }
      {
        if (drop_pnode) next;
        # When in_pnode (override present), keep and print the line (token already replaced earlier)
        if (in_pnode) { print; next }
        if (!in_custom && !in_additional) print
      }
    ' "$deployment_file" > "$tmp_file" && mv "$tmp_file" "$deployment_file"

    # Ensure service_type is a concrete value and remove any template placeholders
    sed -i '' "/{{ service_type /d" "$deployment_file"
    if grep -q "^service_type:" "$deployment_file"; then
        sed -i '' "s/^service_type:.*/service_type: ${service_type}/" "$deployment_file"
    else
        printf "\n# Service type\nservice_type: %s\n" "${service_type}" >> "$deployment_file"
    fi

    # Database-specific injection (idempotent)
    if [[ "$service_type" == "database" ]]; then
        db_name_val="${db_name:-$service}"
        db_user_val="${db_user:-$service}"
        if [[ -z "${db_password:-}" ]]; then
            if command -v openssl >/dev/null 2>&1; then
                db_password_val="$(openssl rand -base64 18 | tr -d '\n' | sed 's/[\"\'"'"'`$]//g')"
            else
                db_password_val="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
            fi
        else
            db_password_val="${db_password}"
        fi
        ensure_kv() {
            local key="$1"; shift
            local value="$1"; shift
            if grep -q "^${key}:" "$deployment_file"; then
                sed -i '' "s|^${key}:.*|${key}: ${value}|" "$deployment_file"
            else
                printf "${key}: %s\n" "${value}" >> "$deployment_file"
            fi
        }
        ensure_kv "db_name" "${db_name_val}"
        ensure_kv "db_user" "${db_user_val}"
        if grep -q "^db_password:" "$deployment_file"; then
            sed -i '' "s|^db_password:.*|db_password: \"${db_password_val}\"|" "$deployment_file"
        else
            printf "db_password: \"%s\"\n" "${db_password_val}" >> "$deployment_file"
        fi
        if [[ -n "${runtime_variant:-}" ]]; then
            ensure_kv "runtime_variant" "${runtime_variant}"
        else
            ensure_kv "runtime_variant" "postgresql"
        fi
        ensure_kv "db_type" "${db_type:-${runtime_variant:-postgresql}}"
    fi

    log_info "✅ Updated group_vars/all.yml for $service"
}

# Update service templates
update_service_templates() {
    local service="$1"
    local service_type="$2"
    local dry_run="$3"
    
    local template_dir="${TEMPLATES_BASE}/base/templates"
    local deployment_dir="${DEPLOYMENTS_BASE}/$service/templates"
    
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

# Update deploy.sh to support global env fallback (~/.pxdcli/env.global)
update_deploy_script() {
    local service="$1"
    local deploy_script="${DEPLOYMENTS_BASE}/$service/deploy.sh"

    if [[ ! -f "$deploy_script" ]]; then
        return 0
    fi

    log_service "Ensuring deploy.sh env fallback for $service"

    # Backup
    if [[ "$CREATE_BACKUP" == "true" ]]; then
        cp "$deploy_script" "${deploy_script}.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    # Replace the strict load-env block with a fallback-aware block
    # The pattern matches the original generated block
    awk '
      BEGIN {in_block=0}
      /source \\.\.\/\.\.\/global-config\/load-env\.sh/ {in_block=1; print "# Load environment"; print "if [[ -f ../../global-config/load-env.sh ]]; then"; print "  source ../../global-config/load-env.sh"; print "  if ! load_clean_env \"$SERVICE_NAME\" \"$(pwd)\"; then"; print "      log_error \"Failed to load clean environment\""; print "      exit 1"; print "  fi"; print "else"; print "  if [[ -f \"$HOME/.pxdcli/env.global\" ]]; then"; print "    source \"$HOME/.pxdcli/env.global\""; print "  fi"; print "fi"; next}
      in_block==1 && /load_clean_env/ { next }
      in_block==1 && /exit 1/ { next }
      in_block==1 && /fi/ { in_block=0; next }
      { print }
    ' "$deploy_script" > "${deploy_script}.tmp" && mv "${deploy_script}.tmp" "$deploy_script"
    chmod +x "$deploy_script"
}

# Update a single service
update_service() {
    local service="$1"
    local dry_run="$2"
    
    if [[ ! -d "${DEPLOYMENTS_BASE}/$service" ]]; then
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

    # Always ensure deploy.sh has env fallback unless specific file filter excludes scripts
    if [[ -z "$UPDATE_FILE" ]]; then
        update_deploy_script "$service"
    fi

    # Ensure DB-specific Ansible collections for database services
    if [[ "$service_type" == "database" ]]; then
        local req_file="${DEPLOYMENTS_BASE}/$service/requirements.yml"
        if [[ -f "$req_file" ]]; then
            if ! grep -q "community.postgresql" "$req_file"; then
                printf "\n  - name: community.postgresql\n    version: \"\>=3.0.0\"\n" >> "$req_file"
            fi
            if ! grep -q "community.mysql" "$req_file"; then
                printf "  - name: community.mysql\n    version: \"\>=3.0.0\"\n" >> "$req_file"
            fi
        fi
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

# Change to template script directory for relative ops (templates are read via TEMPLATES_BASE)
cd "${SCRIPT_DIR}"

# Run main function
main "$@"
