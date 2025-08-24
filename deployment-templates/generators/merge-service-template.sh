#!/bin/bash

# Template Merging System
# Combines base template with service-specific parts using Jinja2

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[MERGE]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Get script directory and templates root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
TEMPLATES_ROOT="${TEMPLATES_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
TEMPLATES_BASE="${TEMPLATES_BASE:-${TEMPLATES_ROOT}/deployment-templates}"

# If TEMPLATES_BASE doesn't exist, try to find it relative to the script location
if [[ ! -d "$TEMPLATES_BASE" ]]; then
    TEMPLATES_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

merge_service_template() {
    local service_name="$1"
    local service_type="$2"
    local deployment_dir="$3"

    log_step "Merging template for $service_name ($service_type)"
    log_info "Templates base: $TEMPLATES_BASE"
    log_info "Base template: $TEMPLATES_BASE/base/deploy.yml.j2"

    # Create temporary working directory
    local temp_dir=$(mktemp -d)
    local service_parts_dir="$temp_dir/service-parts"
    mkdir -p "$service_parts_dir"

    # Copy base template
    cp "$TEMPLATES_BASE/base/deploy.yml.j2" "$temp_dir/deploy.yml.j2"

    # Copy service-specific parts if they exist
    local service_type_dir="$TEMPLATES_BASE/service-types/$service_type"
    local has_runtime_install=false
    local has_dependency_install=false
    local has_build_tasks=false
    local has_systemd_service=false

    if [[ -d "$service_type_dir" ]]; then
        if [[ -f "$service_type_dir/runtime_install.yml.j2" ]]; then
            cp "$service_type_dir/runtime_install.yml.j2" "$service_parts_dir/"
            has_runtime_install=true
            log_info "  ✓ Including runtime installation tasks"
        fi

        if [[ -f "$service_type_dir/dependency_install.yml.j2" ]]; then
            cp "$service_type_dir/dependency_install.yml.j2" "$service_parts_dir/"
            has_dependency_install=true
            log_info "  ✓ Including dependency installation tasks"
        fi

        if [[ -f "$service_type_dir/build_tasks.yml.j2" ]]; then
            cp "$service_type_dir/build_tasks.yml.j2" "$service_parts_dir/"
            has_build_tasks=true
            log_info "  ✓ Including build tasks"
        fi

        if [[ -f "$service_type_dir/systemd_service.yml.j2" ]]; then
            mkdir -p "$deployment_dir/templates"
            cp "$service_type_dir/systemd_service.yml.j2" "$deployment_dir/templates/${service_name}.service.j2"
            has_systemd_service=true
            log_info "  ✓ Including custom systemd service template"
        fi
    fi

    # Create template variables for conditional includes
    cat > "$temp_dir/merge_vars.yml" << EOF
---
service_name: $service_name
service_type: $service_type
service_runtime_install: $has_runtime_install
service_dependency_install: $has_dependency_install
service_build_tasks: $has_build_tasks
service_systemd_service: $has_systemd_service
EOF

    # Use ansible to render the merged template
    log_step "Rendering merged template..."

    # Create a simple ansible playbook to render the template
    cat > "$temp_dir/render.yml" << 'EOF'
---
- name: Render service template
  hosts: localhost
  connection: local
  gather_facts: true
  tasks:
    - name: Render template
      template:
        src: deploy.yml.j2
        dest: "{{ output_file }}"
      vars:
        output_file: "{{ deployment_output }}"
EOF

    # Create extra vars file for ansible
    cat > "$temp_dir/extra_vars.yml" << EOF
---
ansible_python_interpreter: $(which python3)
ssh_public_key_content:
  content: "dGVzdA=="
container_ip: "192.168.1.100"

# Default template variables
vm_id: "100"
vm_name: "test-container"
vm_memory: "2048"
vm_cores: "2"
vm_disk_size: "20"
vm_storage: "local-lvm"
vm_network_bridge: "vmbr0"
vm_swap: "512"
vm_unprivileged: true
app_port: "3000"
app_user: "appuser"
app_dir: "/opt/$service_name"
app_service_name: "$service_name"
service_type: "$service_type"
service_name: "$service_name"
local_app_path: "/tmp"
allowed_ports:
  - "3000"
  - "22"

# Proxmox variables
proxmox_host: "localhost"
proxmox_node: "pve"
proxmox_token_id: ""
proxmox_token_secret: ""
proxmox_user: ""
proxmox_password: ""
vm_os_template: "ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

# DNS variables
dns_server: "192.168.1.11"
dns_domain: "proxmox.local"
service_hostname: "$service_name"

# SSH variables
ssh_public_key_path: "~/.ssh/id_rsa.pub"

# Ansible fact variables (needed for templates)
ansible_date_time:
  date: "2025-01-01"
  hour: "12"
  minute: "00"
  second: "00"

# Additional template variables
proxmox_api_validate_certs: false
http_proxy_port: "8118"
db_type: "postgresql"
nodejs_runtime: "bun"
app_main_file: "index.js"
http_proxy_port: "8118"
EOF

    # Run the template rendering
    extra_vars="-e deployment_output=$deployment_dir/deploy.yml -e @$temp_dir/merge_vars.yml -e @$temp_dir/extra_vars.yml"

    # Add group_vars if it exists
    if [[ -f "$deployment_dir/group_vars/all.yml" ]]; then
        extra_vars="$extra_vars -e @$deployment_dir/group_vars/all.yml"
    fi

    if ansible-playbook "$temp_dir/render.yml" $extra_vars > /dev/null 2>&1; then
        log_info "✅ Template merged successfully"
    else
        log_error "Failed to merge template"
        # Cleanup and exit
        rm -rf "$temp_dir"
        return 1
    fi

    # Cleanup temporary directory
    rm -rf "$temp_dir"

    return 0
}

# Function to preserve custom script
preserve_custom_script() {
    local deployment_dir="$1"
    local service_type="$2"

    local custom_script="$deployment_dir/scripts/custom_script.sh"

    if [[ -f "$custom_script" ]]; then
        log_info "✅ Preserving existing custom_script.sh"
        return 0
    fi

    log_step "Creating default custom_script.sh for $service_type"

    # Ensure scripts directory exists
    mkdir -p "$deployment_dir/scripts"

    # Create service-type specific custom script
    case "$service_type" in
        nodejs)
            create_nodejs_custom_script "$custom_script"
            ;;
        python)
            create_python_custom_script "$custom_script"
            ;;
        golang)
            create_golang_custom_script "$custom_script"
            ;;
        database)
            create_database_custom_script "$custom_script"
            ;;
        *)
            create_generic_custom_script "$custom_script" "$service_type"
            ;;
    esac

    chmod +x "$custom_script"
    log_info "✅ Created default custom_script.sh"
}

create_nodejs_custom_script() {
    local script_file="$1"
    cat > "$script_file" << 'EOF'
#!/bin/bash
set -euo pipefail

# Node.js/Bun Custom Deployment Script
# This script runs after the service-specific installation tasks
# Environment variables available: APP_DIR, SERVICE_TYPE, NODEJS_RUNTIME, APP_PORT, SERVICE_NAME

cd "${APP_DIR:-.}"

echo "🚀 Running custom deployment script for ${SERVICE_NAME:-service}"
echo "   Service Type: ${SERVICE_TYPE:-unknown}"
echo "   Runtime: ${NODEJS_RUNTIME:-unknown}"
echo "   App Directory: ${APP_DIR:-unknown}"

case "${NODEJS_RUNTIME:-bun}" in
    bun)
        if command -v bun >/dev/null 2>&1; then
            echo "📦 Installing dependencies with Bun..."
            bun install

            # Run build if build script exists
            if jq -er '.scripts.build' package.json >/dev/null 2>&1; then
                echo "🔨 Building application with Bun..."
                bun run build || echo "⚠️  Build failed, continuing..."
            fi

            # Run any custom setup scripts
            if jq -er '.scripts.setup' package.json >/dev/null 2>&1; then
                echo "⚙️  Running setup script..."
                bun run setup || echo "⚠️  Setup script failed, continuing..."
            fi
        else
            echo "❌ Bun not found, skipping Bun-specific tasks"
        fi
        ;;
    node)
        if command -v npm >/dev/null 2>&1; then
            echo "📦 Installing dependencies with npm..."
            npm install --omit=dev || npm install --production || true

            # Run build if build script exists
            if jq -er '.scripts.build' package.json >/dev/null 2>&1; then
                echo "🔨 Building application with npm..."
                npm run build || echo "⚠️  Build failed, continuing..."
            fi

            # Run any custom setup scripts
            if jq -er '.scripts.setup' package.json >/dev/null 2>&1; then
                echo "⚙️  Running setup script..."
                npm run setup || echo "⚠️  Setup script failed, continuing..."
            fi
        else
            echo "❌ npm not found, skipping npm-specific tasks"
        fi
        ;;
    *)
        echo "❓ Unknown Node.js runtime: ${NODEJS_RUNTIME:-unknown}"
        ;;
esac

# Add your custom deployment logic here
# Examples:
# - Database migrations
# - Cache warming
# - Configuration file generation
# - Asset compilation
# - Custom file permissions

echo "✅ Custom deployment script completed for ${SERVICE_NAME:-service}"
EOF
}

create_python_custom_script() {
    local script_file="$1"
    cat > "$script_file" << 'EOF'
#!/bin/bash
set -euo pipefail

# Python Custom Deployment Script
# Environment variables available: APP_DIR, SERVICE_TYPE, APP_PORT, SERVICE_NAME

cd "${APP_DIR:-.}"

echo "🚀 Running custom deployment script for ${SERVICE_NAME:-service}"
echo "   Service Type: ${SERVICE_TYPE:-unknown}"
echo "   App Directory: ${APP_DIR:-unknown}"

# Activate virtual environment if it exists
if [[ -f "venv/bin/activate" ]]; then
    echo "🐍 Activating Python virtual environment..."
    source venv/bin/activate
fi

# Run database migrations if manage.py exists (Django)
if [[ -f "manage.py" ]]; then
    echo "🗃️  Running Django migrations..."
    python manage.py migrate || echo "⚠️  Migrations failed, continuing..."

    echo "📊 Collecting static files..."
    python manage.py collectstatic --noinput || echo "⚠️  Static collection failed, continuing..."
fi

# Run Flask database initialization if app.py exists
if [[ -f "app.py" ]] && command -v flask >/dev/null 2>&1; then
    echo "🌶️  Initializing Flask database..."
    flask db upgrade || echo "⚠️  Database upgrade failed, continuing..."
fi

# Add your custom deployment logic here
# Examples:
# - Database seeding
# - Cache initialization
# - Custom configuration
# - Asset processing

echo "✅ Custom deployment script completed for ${SERVICE_NAME:-service}"
EOF
}

create_golang_custom_script() {
    local script_file="$1"
    cat > "$script_file" << 'EOF'
#!/bin/bash
set -euo pipefail

# Go Custom Deployment Script
# Environment variables available: APP_DIR, SERVICE_TYPE, APP_PORT, SERVICE_NAME

cd "${APP_DIR:-.}"

echo "🚀 Running custom deployment script for ${SERVICE_NAME:-service}"
echo "   Service Type: ${SERVICE_TYPE:-unknown}"
echo "   App Directory: ${APP_DIR:-unknown}"

# Set Go environment
export PATH=$PATH:/usr/local/go/bin
export GOOS=linux
export GOARCH=amd64

if command -v go >/dev/null 2>&1; then
    echo "🐹 Go runtime found, running custom Go tasks..."

    # Download dependencies
    echo "📦 Downloading Go modules..."
    go mod download || echo "⚠️  Module download failed, continuing..."

    # Run tests if requested
    if [[ "${RUN_TESTS:-false}" == "true" ]]; then
        echo "🧪 Running Go tests..."
        go test ./... || echo "⚠️  Tests failed, continuing..."
    fi

    # Build the application
    echo "🔨 Building Go application..."
    go build -o "${SERVICE_NAME:-app}" . || echo "⚠️  Build failed, continuing..."

    # Make binary executable
    chmod +x "${SERVICE_NAME:-app}"
else
    echo "❌ Go not found, skipping Go-specific tasks"
fi

# Add your custom deployment logic here
# Examples:
# - Configuration file generation
# - Database migrations
# - Asset compilation

echo "✅ Custom deployment script completed for ${SERVICE_NAME:-service}"
EOF
}

create_database_custom_script() {
    local script_file="$1"
    cat > "$script_file" << 'EOF'
#!/bin/bash
set -euo pipefail

# Database Custom Deployment Script
# Environment variables available: APP_DIR, SERVICE_TYPE, APP_PORT, SERVICE_NAME

echo "🚀 Running custom deployment script for ${SERVICE_NAME:-service}"
echo "   Service Type: ${SERVICE_TYPE:-unknown}"
echo "   Database Type: ${DB_TYPE:-unknown}"

case "${DB_TYPE:-postgresql}" in
    postgresql)
        echo "🐘 PostgreSQL custom setup..."
        # Add PostgreSQL-specific customizations here
        # Examples:
        # - Custom database schemas
        # - Extensions installation
        # - Performance tuning
        ;;
    mysql)
        echo "🐬 MySQL custom setup..."
        # Add MySQL-specific customizations here
        ;;
    redis)
        echo "🔴 Redis custom setup..."
        # Add Redis-specific customizations here
        ;;
    mongodb)
        echo "🍃 MongoDB custom setup..."
        # Add MongoDB-specific customizations here
        ;;
    *)
        echo "❓ Unknown database type: ${DB_TYPE:-unknown}"
        ;;
esac

# Add your custom database setup logic here
# Examples:
# - Data seeding
# - Index creation
# - User management
# - Backup configuration

echo "✅ Custom deployment script completed for ${SERVICE_NAME:-service}"
EOF
}

create_generic_custom_script() {
    local script_file="$1"
    local service_type="$2"
    cat > "$script_file" << EOF
#!/bin/bash
set -euo pipefail

# Generic Custom Deployment Script for $service_type
# Environment variables available: APP_DIR, SERVICE_TYPE, APP_PORT, SERVICE_NAME

cd "\${APP_DIR:-.}"

echo "🚀 Running custom deployment script for \${SERVICE_NAME:-service}"
echo "   Service Type: \${SERVICE_TYPE:-unknown}"
echo "   App Directory: \${APP_DIR:-unknown}"

# Add your custom deployment logic here
# This script runs after the standard service installation
# Examples:
# - Configuration file generation
# - Custom permissions
# - Additional package installation
# - Service-specific setup

echo "✅ Custom deployment script completed for \${SERVICE_NAME:-service}"
EOF
}

# Main function to be called by generators
main() {
    local service_name="$1"
    local service_type="$2"
    local deployment_dir="$3"

    # Merge templates
    if merge_service_template "$service_name" "$service_type" "$deployment_dir"; then
        # Preserve/create custom script
        preserve_custom_script "$deployment_dir" "$service_type"
        return 0
    else
        return 1
    fi
}

# Allow script to be sourced or run directly
if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
    if [[ $# -lt 3 ]]; then
        echo "Usage: $0 <service_name> <service_type> <deployment_dir>"
        exit 1
    fi
    main "$@"
fi
