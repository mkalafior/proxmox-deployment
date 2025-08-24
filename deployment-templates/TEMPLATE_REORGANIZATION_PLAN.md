# Template Reorganization Implementation Plan

## Overview

This document outlines the complete plan to reorganize the deployment templates to separate generic container management from service-specific deployment logic, using Jinja2 templates and bash scripting.

## Current Problems

1. **Base template contains service-specific logic** - PostgreSQL installation, Node.js setup, etc. mixed with generic container management
2. **No clean separation** - Generic tasks (container creation, IP discovery) mixed with service tasks (runtime installation, dependency management)
3. **Difficult maintenance** - Changes to generic logic affect all services, changes to service logic require base template modifications
4. **Limited extensibility** - Adding new service types requires modifying base template
5. **Custom script handling** - No systematic way to preserve user customizations during template regeneration

## New Architecture Goals

1. **Pure generic base template** - Only container management, IP discovery, DNS, firewall, custom script execution
2. **Service-specific template parts** - Runtime installation, dependency management, build tasks in separate files
3. **Template injection system** - Merge generic + service-specific parts during generation
4. **Custom script preservation** - Always preserve `custom_script.sh` during regeneration
5. **Jinja2 + Bash only** - No Python dependencies, leverage existing Ansible/Jinja2

## Directory Structure (New)

```
deployment-templates/
├── base/
│   ├── deploy.yml.j2                    # Pure generic base template
│   ├── group_vars/
│   │   └── all.yml.j2                   # Generic variables template
│   ├── templates/                       # Generic template files
│   │   ├── bind-key.conf.j2
│   │   ├── cloudflare-tunnel-config.yml.j2
│   │   ├── dns-register.service.j2
│   │   ├── dns-register.sh.j2
│   │   ├── env.j2
│   │   └── ip_discovery_tasks.yml
│   └── service-parts/                   # Injection point templates
│       ├── runtime_install.yml.j2       # Placeholder for runtime installation
│       ├── dependency_install.yml.j2    # Placeholder for dependency installation
│       └── build_tasks.yml.j2           # Placeholder for build tasks
├── service-types/
│   ├── nodejs/
│   │   ├── config.yml                   # Service configuration
│   │   ├── runtime_install.yml.j2       # Node.js/Bun installation tasks
│   │   ├── dependency_install.yml.j2    # npm/bun install tasks
│   │   ├── build_tasks.yml.j2           # TypeScript compilation, etc.
│   │   └── systemd_service.j2           # Service-specific systemd template
│   ├── python/
│   │   ├── config.yml
│   │   ├── runtime_install.yml.j2       # Python + pip + venv setup
│   │   ├── dependency_install.yml.j2    # pip install requirements
│   │   ├── build_tasks.yml.j2           # (usually empty for Python)
│   │   └── systemd_service.j2
│   ├── golang/
│   │   ├── config.yml
│   │   ├── runtime_install.yml.j2       # Go installation
│   │   ├── dependency_install.yml.j2    # go mod download
│   │   ├── build_tasks.yml.j2           # go build
│   │   └── systemd_service.j2
│   ├── database/
│   │   ├── config.yml
│   │   ├── runtime_install.yml.j2       # PostgreSQL/MySQL/Redis installation
│   │   ├── dependency_install.yml.j2    # Database setup, user creation
│   │   └── build_tasks.yml.j2           # (empty for databases)
│   └── static/
│       ├── config.yml
│       ├── runtime_install.yml.j2       # Nginx/Apache installation
│       ├── dependency_install.yml.j2    # Web server configuration
│       └── build_tasks.yml.j2           # (empty for static)
├── generators/
│   ├── generate-service-deployment.sh   # Updated to use new merging system
│   ├── merge-service-template.sh        # NEW: Template merging script
│   └── generate-multi-service.sh        # Updated for new system
└── update-deployments.sh                # Updated for new template system
```

## Implementation Steps

### Step 1: Create New Base Template Structure

#### 1.1 Extract Generic Logic from Current Base Template

**Current base template contains:**
- ✅ **Keep in base**: Container creation, IP discovery, SSH setup, basic packages, firewall, DNS registration, Cloudflare tunnel
- ❌ **Move to service parts**: PostgreSQL installation, Node.js setup, application deployment, systemd service creation

#### 1.2 New Base Template Structure

```yaml
# deployment-templates/base/deploy.yml.j2
---
- name: Deploy {{ service_name }} to Proxmox VE
  hosts: localhost
  connection: local
  gather_facts: true
  vars_files:
    - group_vars/all.yml
  
  tasks:
    # GENERIC CONTAINER MANAGEMENT TASKS ONLY
    - name: Validate environment variables
      # ... existing validation logic ...
    
    - name: Create Proxmox container via curl command
      # ... existing container creation logic ...
    
    - name: Start the container
      # ... existing container start logic ...
    
    - name: IP discovery with progressive backoff
      # ... existing IP discovery logic ...
    
    - name: Add container to dynamic inventory
      # ... existing inventory logic ...

- name: Configure container and deploy {{ service_name }} application
  hosts: proxmox_containers
  become: true
  vars_files:
    - group_vars/all.yml
  
  tasks:
    # GENERIC SYSTEM SETUP
    - name: Wait for system to be ready
      wait_for_connection:
        timeout: 300

    - name: Test internet connectivity
      # ... existing connectivity test ...

    - name: Update apt cache
      # ... existing apt update ...

    - name: Install base system packages
      apt:
        name:
          - curl
          - wget
          - git
          - unzip
          - ufw
          - build-essential
          - qemu-guest-agent
        state: present
      when: not internet_test.failed

    - name: Configure firewall
      # ... existing firewall logic ...

    # SERVICE-SPECIFIC INJECTION POINTS
    {% if service_runtime_install is defined and service_runtime_install %}
    {% include 'service-parts/runtime_install.yml.j2' %}
    {% endif %}

    - name: Create application user
      user:
        name: "{{ app_user }}"
        system: yes
        shell: /bin/bash
        home: "{{ app_dir }}"
        create_home: yes
      when: service_type != 'database'

    - name: Create application directory
      file:
        path: "{{ app_dir }}"
        state: directory
        owner: "{{ app_user }}"
        group: "{{ app_user }}"
        mode: '0755'
      when: service_type != 'database'

    - name: Copy application files using tar
      # ... existing file copy logic ...
      when: service_type != 'database'

    {% if service_dependency_install is defined and service_dependency_install %}
    {% include 'service-parts/dependency_install.yml.j2' %}
    {% endif %}

    {% if service_build_tasks is defined and service_build_tasks %}
    {% include 'service-parts/build_tasks.yml.j2' %}
    {% endif %}

    # CUSTOM SCRIPT EXECUTION (ALWAYS PRESENT)
    - name: Detect local custom deployment script
      stat:
        path: "{{ playbook_dir }}/scripts/custom_script.sh"
      register: local_custom_script
      delegate_to: localhost
      become: false

    - name: Upload custom deployment script to container
      copy:
        src: "{{ playbook_dir }}/scripts/custom_script.sh"
        dest: "/opt/custom_script.sh"
        mode: '0755'
        owner: root
        group: root
      when: local_custom_script.stat.exists

    - name: Run custom deployment script
      shell: "/opt/custom_script.sh"
      args:
        chdir: "{{ app_dir }}"
      become_user: "{{ app_user }}"
      environment:
        APP_DIR: "{{ app_dir }}"
        SERVICE_TYPE: "{{ service_type | default('') }}"
        NODEJS_RUNTIME: "{{ nodejs_runtime | default('') }}"
        APP_PORT: "{{ app_port | string }}"
        SERVICE_NAME: "{{ service_name }}"
      register: custom_script_result
      changed_when: false
      failed_when: false
      when: local_custom_script.stat.exists

    - name: Create environment file
      template:
        src: env.j2
        dest: "{{ app_dir }}/.env"
        owner: "{{ app_user }}"
        group: "{{ app_user }}"
        mode: '0600'
      when: service_type != 'database'

    # SERVICE-SPECIFIC SYSTEMD SERVICE
    {% if service_systemd_service is defined and service_systemd_service %}
    - name: Create systemd service file
      template:
        src: "{{ app_service_name }}.service.j2"
        dest: "/etc/systemd/system/{{ app_service_name }}.service"
        mode: '0644'
      notify: reload systemd
      when: service_type != 'database'

    - name: Enable and start application service
      systemd:
        name: "{{ app_service_name }}"
        enabled: yes
        state: started
        daemon_reload: yes
      when: service_type != 'database'
    {% endif %}

    # GENERIC DNS AND CLOUDFLARE SETUP
    - name: Copy DNS authentication key
      # ... existing DNS logic ...

    - name: Configure Cloudflare tunnel routing
      # ... existing Cloudflare logic ...

    # GENERIC SERVICE STATUS AND HEALTH CHECKS
    - name: Check service status
      # ... existing status checks ...

  handlers:
    - name: reload systemd
      systemd:
        daemon_reload: yes
```

### Step 2: Create Service-Specific Template Parts

#### 2.1 Node.js Service Parts

**File: `deployment-templates/service-types/nodejs/runtime_install.yml.j2`**
```yaml
# Node.js/Bun Runtime Installation
- name: Install Node.js runtime
  apt:
    name:
      - nodejs
      - npm
    state: present
  when: 
    - not internet_test.failed
    - nodejs_runtime == "node"

- name: Install Bun runtime system-wide
  shell: |
    curl -fsSL https://bun.sh/install | bash -s "bun-v1.0.20"
    cp /root/.bun/bin/bun /usr/local/bin/bun
    chmod 755 /usr/local/bin/bun
    chown root:root /usr/local/bin/bun
  args:
    creates: /usr/local/bin/bun
  when: 
    - not internet_test.failed
    - nodejs_runtime == "bun"
```

**File: `deployment-templates/service-types/nodejs/dependency_install.yml.j2`**
```yaml
# Node.js/Bun Dependency Installation
- name: Install dependencies with npm
  shell: npm install
  args:
    chdir: "{{ app_dir }}"
  become_user: "{{ app_user }}"
  when: nodejs_runtime == "node"

- name: Install dependencies with Bun
  shell: /usr/local/bin/bun install
  args:
    chdir: "{{ app_dir }}"
  become_user: "{{ app_user }}"
  when: nodejs_runtime == "bun"
```

**File: `deployment-templates/service-types/nodejs/build_tasks.yml.j2`**
```yaml
# Node.js/Bun Build Tasks
- name: Build TypeScript application with npm
  shell: npm run build
  args:
    chdir: "{{ app_dir }}"
  become_user: "{{ app_user }}"
  when: 
    - nodejs_runtime == "node"
    - build_script_exists.stat.exists
  ignore_errors: true

- name: Build TypeScript application with Bun
  shell: /usr/local/bin/bun run build
  args:
    chdir: "{{ app_dir }}"
  become_user: "{{ app_user }}"
  when: 
    - nodejs_runtime == "bun"
    - build_script_exists.stat.exists
  ignore_errors: true

- name: Check if build script exists
  stat:
    path: "{{ app_dir }}/package.json"
  register: package_json_exists

- name: Check for build script in package.json
  shell: |
    if command -v jq >/dev/null 2>&1; then
      jq -er '.scripts.build' "{{ app_dir }}/package.json" >/dev/null 2>&1
    else
      grep -q '"build"' "{{ app_dir }}/package.json"
    fi
  register: build_script_exists
  failed_when: false
  changed_when: false
  when: package_json_exists.stat.exists
```

#### 2.2 Python Service Parts

**File: `deployment-templates/service-types/python/runtime_install.yml.j2`**
```yaml
# Python Runtime Installation
- name: Install Python runtime
  apt:
    name:
      - python3
      - python3-pip
      - python3-venv
    state: present
  when: not internet_test.failed
```

**File: `deployment-templates/service-types/python/dependency_install.yml.j2`**
```yaml
# Python Dependency Installation
- name: Create Python virtual environment
  shell: python3 -m venv venv
  args:
    chdir: "{{ app_dir }}"
    creates: "{{ app_dir }}/venv"
  become_user: "{{ app_user }}"

- name: Check if requirements.txt exists
  stat:
    path: "{{ app_dir }}/requirements.txt"
  register: requirements_file_exists

- name: Install Python dependencies
  shell: |
    source venv/bin/activate
    pip install -r requirements.txt
  args:
    chdir: "{{ app_dir }}"
  become_user: "{{ app_user }}"
  when: requirements_file_exists.stat.exists
```

**File: `deployment-templates/service-types/python/build_tasks.yml.j2`**
```yaml
# Python Build Tasks (usually empty, but can include compilation of extensions)
# This file can be empty or contain specific build steps if needed
```

#### 2.3 Database Service Parts

**File: `deployment-templates/service-types/database/runtime_install.yml.j2`**
```yaml
# Database Runtime Installation
- name: Install PostgreSQL
  apt:
    name:
      - postgresql
      - postgresql-contrib
      - python3-psycopg2
    state: present
  when:
    - not internet_test.failed
    - db_type == 'postgresql'

- name: Install MySQL
  apt:
    name:
      - mysql-server
      - python3-pymysql
    state: present
  when:
    - not internet_test.failed
    - db_type == 'mysql'

- name: Install Redis
  apt:
    name: redis-server
    state: present
  when:
    - not internet_test.failed
    - db_type == 'redis'
```

**File: `deployment-templates/service-types/database/dependency_install.yml.j2`**
```yaml
# Database Configuration and Setup
- name: Ensure PostgreSQL is running
  systemd:
    name: postgresql
    state: started
    enabled: yes
  when: db_type == 'postgresql'

- name: Discover PostgreSQL config directory
  shell: |
    dirname $(readlink -f $(find /etc/postgresql -type f -name postgresql.conf | head -n1))
  register: pg_conf_dir
  changed_when: false
  when: db_type == 'postgresql'

- name: Configure PostgreSQL
  lineinfile:
    path: "{{ pg_conf_dir.stdout }}/postgresql.conf"
    regexp: "{{ item.regexp }}"
    line: "{{ item.line }}"
    backup: yes
  loop:
    - { regexp: "^#?listen_addresses\\s*=.*", line: "listen_addresses = '*'" }
    - { regexp: "^#?port\\s*=.*", line: "port = {{ app_port }}" }
  when: db_type == 'postgresql'

- name: Configure pg_hba for remote connections
  blockinfile:
    path: "{{ pg_conf_dir.stdout }}/pg_hba.conf"
    marker: "# {mark} ANSIBLE MANAGED BLOCK - remote access"
    block: |
      host    all             all             0.0.0.0/0               md5
      host    all             all             ::/0                    md5
  when: db_type == 'postgresql'

- name: Restart PostgreSQL
  systemd:
    name: postgresql
    state: restarted
  when: db_type == 'postgresql'

- name: Initialize PostgreSQL database
  postgresql_db:
    name: "{{ db_name | default(service_name) }}"
    state: present
    port: "{{ app_port }}"
    login_unix_socket: "/var/run/postgresql"
  become_user: postgres
  when: db_type == 'postgresql'

- name: Create PostgreSQL user
  postgresql_user:
    name: "{{ db_user | default(service_name) }}"
    password: "{{ db_password }}"
    state: present
    port: "{{ app_port }}"
    login_unix_socket: "/var/run/postgresql"
  become_user: postgres
  when: db_type == 'postgresql'

# Similar blocks for MySQL, Redis, MongoDB...
```

### Step 3: Create Template Merging System

#### 3.1 Main Merging Script

**File: `deployment-templates/generators/merge-service-template.sh`**
```bash
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_ROOT="${TEMPLATES_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
TEMPLATES_BASE="${TEMPLATES_ROOT}/deployment-templates"

merge_service_template() {
    local service_name="$1"
    local service_type="$2"
    local deployment_dir="$3"
    
    log_step "Merging template for $service_name ($service_type)"
    
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
        
        if [[ -f "$service_type_dir/systemd_service.j2" ]]; then
            cp "$service_type_dir/systemd_service.j2" "$deployment_dir/templates/${service_name}.service.j2"
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
  gather_facts: false
  tasks:
    - name: Render template
      template:
        src: deploy.yml.j2
        dest: "{{ output_file }}"
      vars:
        output_file: "{{ deployment_output }}"
EOF
    
    # Run the template rendering
    if ansible-playbook "$temp_dir/render.yml" \
        -e "deployment_output=$deployment_dir/deploy.yml" \
        -e "@$temp_dir/merge_vars.yml" \
        -e "@$deployment_dir/group_vars/all.yml" \
        --extra-vars "ansible_python_interpreter=$(which python3)" \
        > /dev/null 2>&1; then
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
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 3 ]]; then
        echo "Usage: $0 <service_name> <service_type> <deployment_dir>"
        exit 1
    fi
    main "$@"
fi
```

### Step 4: Update Generation Scripts

#### 4.1 Update generate-service-deployment.sh

**Key changes needed in `deployment-templates/generators/generate-service-deployment.sh`:**

1. **Replace template copying logic** with template merging:
```bash
# OLD CODE (around line 537):
# Copy and customize deploy.yml
cp "$DEPLOY_TEMPLATE_FILE" "$DEPLOYMENT_DIR/deploy.yml"
sed -i '' "s/{{ service_name }}/$SERVICE_NAME/g" "$DEPLOYMENT_DIR/deploy.yml"

# NEW CODE:
# Source the merging script
source "$SCRIPT_DIR/merge-service-template.sh"

# Merge templates instead of simple copy
log_step "Merging service template..."
if ! merge_service_template "$SERVICE_NAME" "$SERVICE_TYPE_CFG" "$DEPLOYMENT_DIR"; then
    log_error "Failed to merge service template"
    exit 1
fi
```

2. **Update custom script handling** (around line 626):
```bash
# OLD CODE:
# Ensure scripts directory and per-deployment custom_script.sh
mkdir -p "$DEPLOYMENT_DIR/scripts"
if [[ ! -f "$DEPLOYMENT_DIR/scripts/custom_script.sh" ]]; then
  log_step "Creating default custom_script.sh"
  cat > "$DEPLOYMENT_DIR/scripts/custom_script.sh" << 'EOF'
# ... generic script content ...

# NEW CODE:
# Custom script is now handled by merge-service-template.sh
# No changes needed here - the merging script handles it
```

#### 4.2 Update update-deployments.sh

**Key changes needed in `deployment-templates/update-deployments.sh`:**

1. **Replace update_deploy_yml function** (around line 136):
```bash
# OLD CODE:
update_deploy_yml() {
    local service="$1"
    local service_type="$2"
    local dry_run="$3"
    
    # ... existing template copying logic ...
    cp "$template_file" "$deployment_file"
    sed -i '' "s/{{ service_name }}/$service/g" "$deployment_file"

# NEW CODE:
update_deploy_yml() {
    local service="$1"
    local service_type="$2"
    local dry_run="$3"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "   Would regenerate merged template for: $service ($service_type)"
        return 0
    fi
    
    # Source the merging script
    source "$TEMPLATES_BASE/generators/merge-service-template.sh"
    
    # Create backup
    if [[ "$CREATE_BACKUP" == "true" && -f "$deployment_file" ]]; then
        cp "$deployment_file" "${deployment_file}.bak.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Regenerate merged template
    log_service "Regenerating merged template for $service ($service_type)"
    if merge_service_template "$service" "$service_type" "${DEPLOYMENTS_BASE}/$service"; then
        log_info "✅ Updated deploy.yml for $service"
    else
        log_error "Failed to update deploy.yml for $service"
        return 1
    fi
}
```

### Step 5: Service Type Configuration Updates

#### 5.1 Update service-types config.yml files

Each service type's `config.yml` should be updated to indicate which template parts it provides:

**Example: `deployment-templates/service-types/nodejs/config.yml`**
```yaml
# Node.js/Bun.js Service Type Configuration
service_type: nodejs
runtime_name: "Node.js/Bun.js"

# Template parts provided by this service type
provides_runtime_install: true
provides_dependency_install: true
provides_build_tasks: true
provides_systemd_service: true

# Default environment variables
default_env:
  NODE_ENV: production
  HOST: "0.0.0.0"

# Health check endpoint
health_check_path: "/health"

# File exclusions for tar archive
file_exclusions:
  - "node_modules"
  - ".git"
  - "deployment"
  - "deployments"
  - "*.log"
  - ".env"
  - ".npm"
  - "package-lock.json"

# Default systemd service configuration
systemd_service:
  Type: simple
  ExecStart: "{{ '/usr/local/bin/bun' if nodejs_runtime == 'bun' else 'node' }} {{ app_main_file | default('index.js') }}"
  Restart: always
  RestartSec: 10
```

### Step 6: Testing Strategy

#### 6.1 Test Plan

1. **Backup existing deployments**
2. **Test with each service type:**
   - nodejs (both node and bun variants)
   - python
   - golang
   - database (postgresql, mysql, redis)
   - static
3. **Verify template merging works correctly**
4. **Verify custom script preservation**
5. **Test update-deployments.sh with new system**
6. **Verify generated deployments work as expected**

#### 6.2 Test Script

**File: `deployment-templates/test-new-templates.sh`**
```bash
#!/bin/bash

# Test script for new template system
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test service types
SERVICE_TYPES=("nodejs" "python" "golang" "database" "static")

echo "🧪 Testing new template system..."

for service_type in "${SERVICE_TYPES[@]}"; do
    echo ""
    echo "Testing $service_type service type..."
    
    # Generate test service
    test_service="test-${service_type}-$(date +%s)"
    
    if ./generators/generate-service-deployment.sh "$test_service" \
        --port $((3000 + RANDOM % 1000)) \
        --force; then
        echo "✅ $service_type template generation successful"
        
        # Verify files exist
        deployment_dir="$TEMPLATES_ROOT/deployments/$test_service"
        if [[ -f "$deployment_dir/deploy.yml" && 
              -f "$deployment_dir/scripts/custom_script.sh" ]]; then
            echo "✅ Required files generated"
        else
            echo "❌ Missing required files"
        fi
        
        # Test syntax
        if ansible-playbook "$deployment_dir/deploy.yml" --syntax-check >/dev/null 2>&1; then
            echo "✅ Ansible syntax valid"
        else
            echo "❌ Ansible syntax invalid"
        fi
    else
        echo "❌ $service_type template generation failed"
    fi
done

echo ""
echo "🎉 Template testing completed"
```

## Migration Strategy

### Phase 1: Preparation
1. **Backup current templates** - Create full backup of deployment-templates/
2. **Create new directory structure** - Set up service-parts directories
3. **Extract service logic** - Move service-specific tasks to separate files

### Phase 2: Implementation
1. **Implement merging script** - Create merge-service-template.sh
2. **Update base template** - Add Jinja2 injection points
3. **Create service parts** - Extract logic into separate template files
4. **Update generators** - Modify generation scripts to use merging

### Phase 3: Testing
1. **Test with existing services** - Verify backward compatibility
2. **Test new generations** - Create new services with new system
3. **Test updates** - Verify update-deployments.sh works
4. **Performance testing** - Ensure no significant slowdown

### Phase 4: Rollout
1. **Update documentation** - Update README and usage instructions
2. **Migrate existing deployments** - Run update-deployments.sh on all services
3. **Clean up old templates** - Remove redundant template files
4. **Monitor and fix issues** - Address any problems that arise

## Benefits Summary

✅ **Clean separation of concerns** - Generic container management vs service-specific logic  
✅ **Easy maintenance** - Changes to base don't affect services and vice versa  
✅ **Flexible service types** - Easy to add new service types without touching base  
✅ **Custom script preservation** - User customizations never lost during updates  
✅ **No new dependencies** - Uses existing Ansible/Jinja2 and bash  
✅ **Backward compatibility** - Existing deployments continue to work  
✅ **Template reusability** - Service parts can be mixed and matched  
✅ **Clear extension points** - custom_script.sh provides clear customization hook  

## Implementation Checklist

- [ ] Create new directory structure
- [ ] Extract service logic from base template
- [ ] Create service-specific template parts
- [ ] Implement merge-service-template.sh
- [ ] Update base template with injection points
- [ ] Update generate-service-deployment.sh
- [ ] Update update-deployments.sh
- [ ] Create service type configurations
- [ ] Test with all service types
- [ ] Update documentation
- [ ] Migrate existing deployments

This plan provides a complete roadmap for implementing the template reorganization using Jinja2 and bash, maintaining all existing functionality while providing the clean separation you requested.

