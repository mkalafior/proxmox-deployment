#!/bin/bash

# Service Creator from Templates
# Usage: create-service-from-template.sh <service-name> <service-type> <target-dir> [variables...]

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

# Function to create service from templates
create_service_from_template() {
    local service_name="$1"
    local service_type="$2"
    local target_dir="$3"
    shift 3
    
    # Parse additional variables (key=value pairs)
    declare -A template_vars
    template_vars["service_name"]="$service_name"
    
    while [[ $# -gt 0 ]]; do
        if [[ "$1" =~ ^([^=]+)=(.*)$ ]]; then
            template_vars["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        fi
        shift
    done
    
    # Get script directory and templates base
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local templates_base="$(cd "$script_dir/.." && pwd)"
    local service_starter_dir="$templates_base/service-types/$service_type/service-starter"
    
    # Check if service starter templates exist
    if [[ ! -d "$service_starter_dir" ]]; then
        log_error "No service starter templates found for service type: $service_type"
        log_error "Expected directory: $service_starter_dir"
        return 1
    fi
    
    # Create target directory
    log_step "Creating service directory: $target_dir"
    mkdir -p "$target_dir"
    
    # Process each template file
    log_step "Processing service starter templates..."
    local template_count=0
    
    while IFS= read -r -d '' template_file; do
        local relative_path="${template_file#$service_starter_dir/}"
        local output_file="$target_dir/${relative_path%.j2}"
        
        log_info "  Processing: $relative_path -> $(basename "$output_file")"
        
        # Create output directory if needed
        local output_dir="$(dirname "$output_file")"
        if [[ "$output_dir" != "$target_dir" ]]; then
            mkdir -p "$output_dir"
        fi
        
        # Process template with variable substitution
        local template_content
        template_content="$(cat "$template_file")"
        
        # Replace template variables
        for var_name in "${!template_vars[@]}"; do
            local var_value="${template_vars[$var_name]}"
            # Use sed to replace {{ var_name }} with value
            template_content="$(echo "$template_content" | sed "s|{{ $var_name }}|$var_value|g")"
        done
        
        # Write processed content to output file
        echo "$template_content" > "$output_file"
        
        ((template_count++))
    done < <(find "$service_starter_dir" -name "*.j2" -type f -print0)
    
    if [[ $template_count -eq 0 ]]; then
        log_warn "No template files found in $service_starter_dir"
        return 1
    fi
    
    log_info "✅ Created $template_count files from service starter templates"
    return 0
}

# Main execution
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <service-name> <service-type> <target-dir> [key=value...]"
    echo ""
    echo "Arguments:"
    echo "  service-name    Name of the service"
    echo "  service-type    Type of service (nodejs, python, golang, static, etc.)"
    echo "  target-dir      Directory to create the service in"
    echo "  key=value       Additional template variables (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 my-api nodejs ./services/my-api app_port=3000"
    echo "  $0 web-app static ./services/web-app"
    echo "  $0 backend python ./services/backend app_port=8080 nodejs_runtime=node"
    exit 1
fi

create_service_from_template "$@"
