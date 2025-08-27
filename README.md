# Proxmox Multi-Service Deployment System

A DRY and KISS approach to deploying multiple services to Proxmox VE with automated VM provisioning, template-based service generation, and comprehensive service management.

## 🏗️ Architecture

```
proxmox-deploy-playground/
├── services/                    # Your application code
│   ├── python-api/             # FastAPI service
│   ├── go-api/                 # Go HTTP service  
│   ├── postgres-db/            # PostgreSQL database
│   ├── service01/              # Bun.js service
│   └── service02/              # Bun.js worker
├── deployments/                # Service-specific deployment configs
│   ├── python-api/             # Python deployment
│   ├── go-api/                 # Go deployment
│   ├── postgres-db/            # Database deployment
│   ├── service01/              # Bun deployment
│   └── service02/              # Bun deployment
├── deployment-templates/       # Shared templates (DRY principle)
│   ├── base/                   # Base Ansible templates
│   ├── service-types/          # Language-specific configs & starter templates
│   │   ├── nodejs/service-starter/  # Node.js starter templates
│   │   ├── python/service-starter/  # Python starter templates
│   │   └── golang/service-starter/  # Go starter templates
│   └── generators/             # Template-based generation scripts
├── global-config/              # Global configuration
│   ├── env.proxmox.global      # Global Proxmox settings
│   └── deployment-defaults.yml # Default values
└── tools/
    └── proxmox-deploy          # CLI tool (installed as pxdcli)
```

## 🚀 Supported Service Types

### Programming Languages
- **Node.js/Bun.js** - REST APIs, GraphQL, real-time apps with runtime-specific templates
- **Python** - FastAPI applications with dependency management
- **Go** - High-performance compiled services with module support
- **Static Sites** - Nginx-served websites and SPAs

### Infrastructure Services
- **PostgreSQL** - ACID database with user setup
- **MySQL** - Traditional relational database
- **Redis** - In-memory cache/store
- **MongoDB** - Document database
- **Tor Proxy** - Privacy-focused proxy services

### Template-Based Service Generation
All service types use Jinja2 templates for consistent, maintainable code generation:
- **Runtime-specific configurations** (Node.js vs Bun, Python versions)
- **Proper error handling** and HTTP status codes
- **Health check endpoints** and service metadata
- **Environment-based configuration** (PORT, HOST variables)
- **CORS headers** and security best practices

## 🔧 Installation (Linux/macOS)

Install the global templates and CLI once, then use them from any project without copying files.

### Prerequisites
- git, bash, curl
- j2cli (Jinja2 command-line tool) - automatically installed during setup
- Ansible (for deployment) - automatically installed during setup

### One-Command Installation (Recommended)

```bash
git clone https://github.com/your-org/proxmox-deploy-playground
cd proxmox-deploy-playground
./tools/install.sh
```

This installs:
- ✅ Global templates and CLI tool
- ✅ Bash completion for enhanced productivity
- ✅ Automatic PATH configuration

### Custom Installation Options

```bash
# Install only templates and CLI (skip completion)
./tools/install.sh --no-completion

# Install only completion (skip templates)
./tools/install.sh --no-templates

# Force reinstall everything
./tools/install.sh --force

# Custom directories
./tools/install.sh /opt/pxdcli /usr/local/bin

# See all options
./tools/install.sh --help
```

### Manual Verification

```bash
# Restart shell or source profile
source ~/.bashrc  # Linux
source ~/.zshrc   # macOS

# Verify installation
pxdcli help

# Test completion (after shell restart)
pxdcli de<TAB>    # Should complete to "deploy"
```

### Bash Completion Features

The installer automatically sets up tab completion with these features:
- **Command completion**: `pxdcli de<TAB>` → `deploy`
- **Service name completion**: `pxdcli deploy <TAB>` → shows available services
- **Option completion**: `pxdcli generate myapp --type <TAB>` → shows service types
- **Context-aware completion**: `pxdcli generate myapp --type nodejs --runtime <TAB>` → shows `node bun`

**Usage Examples:**
```bash
pxdcli de<TAB>                    # Completes to "deploy"
pxdcli deploy <TAB>               # Shows available services
pxdcli redeploy <TAB>             # Shows available services and --no-build --force flags
pxdcli generate myapp --type <TAB> # Shows: nodejs python golang rust database static tor-proxy
pxdcli update <TAB>               # Shows services and --force flag
```

Notes
- The installer places templates in `~/.proxmox-deploy/templates` and symlinks the CLI to `~/.local/bin/pxdcli`.
- The CLI auto-updates templates (`git pull`) on use.
- Service generation uses template-based creation with Jinja2 processing for consistent, high-quality code.
- To target a different project directory: run commands from that project root. Advanced: set `PROJECT_ROOT_OVERRIDE=/abs/path`.
- Advanced: point to a custom templates checkout by exporting `TEMPLATES_ROOT=/abs/path/to/templates-root`.

### CLI Troubleshooting (PATH)

If you see `pxdcli: command not found`, ensure `~/.local/bin` is on your PATH.

```bash
# Check PATH contains ~/.local/bin
echo $PATH | tr ':' '\n' | grep -x "$HOME/.local/bin" || echo "not-in-PATH"

# Add to PATH (zsh)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

# Add to PATH (bash)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

# Verify the CLI is installed
ls -l ~/.local/bin/pxdcli
pxdcli help
```

### CLI Usage (Global Templates)

From the root of your real project (no templates copied):

```bash
# 1) Generate a service (interactive with auto VM ID selection)
pxdcli generate api-service --type nodejs --runtime bun --port 3001

# Or specify node and VM ID manually
pxdcli generate postgres-db --type database --runtime postgresql --node pve --vm-id 204 --port 5432 \
  --db-name myapp --db-user myuser --db-pass secret123

# 2) Update generated deployments after template changes
pxdcli update --force

# 3) Deploy a service
pxdcli deploy postgres-db
```

Advanced:
- Use a different target repo: `PROJECT_ROOT_OVERRIDE=/abs/path pxdcli update --force`
- Use a custom templates path: `TEMPLATES_ROOT=/abs/path/to/templates pxdcli generate ...`

## 🎯 Quick Start

### 1. Generate a New Service

```bash
# Interactive generation (recommended - auto-selects node and VM ID)
pxdcli generate api-service

# Direct command with auto VM ID selection and template-based service creation
pxdcli generate api-service --type nodejs --runtime node --port 3001

# Bun.js runtime with template-based generation
pxdcli generate bun-service --type nodejs --runtime bun --port 3002

# Python service with FastAPI template
pxdcli generate python-api --type python --port 8000 --node pve2

# Full manual control with database setup
pxdcli generate postgres-db --type database --runtime postgresql \
  --node pve1 --vm-id 204 --port 5432 --db-name myapp --db-user myuser --db-pass secret123
```

### 2. Deploy Services

```bash
# Deploy single service
pxdcli deploy python-api

# Deploy all services
pxdcli deploy-all

# Or deploy from service directory
cd deployments/python-api && ./deploy.sh
```

### 3. Redeploy Code Changes (Fast Updates)

For code-based services (nodejs, python, golang, static), you can quickly redeploy just your code changes without reprovisioning the entire VM:

```bash
# Redeploy single service
pxdcli redeploy python-api

# Redeploy all code-based services
pxdcli redeploy-all

# Skip build step (faster for interpreted languages)
pxdcli redeploy python-api --no-build

# Force dependency update even if package files haven't changed
pxdcli redeploy python-api --force

# Or redeploy from service directory
cd deployments/python-api && ./redeploy.sh
```

**Redeploy Features:**
- ⚡ **Fast**: Completes in <60 seconds (vs 3-5 minutes for full deploy)
- 🔍 **Smart**: Only updates dependencies when package files change
- 🏗️ **Build-aware**: Automatically runs build steps for compiled languages
- 🩺 **Health checks**: Verifies service is running after redeployment
- 🔄 **Rollback**: Automatically restores previous version on failure
- 📦 **Backup**: Keeps previous versions for quick rollback

## ✨ New Features

### 🔍 Intelligent Node & VM ID Selection

The CLI now provides intelligent automation for node and VM ID selection:

**Interactive 3-Step Process:**
```bash
pxdcli generate my-service

# Step 1: Shows available Proxmox nodes, asks for selection
# Step 2: Auto-finds first available VM ID on selected node
# Step 3: Prompts for service configuration (port, type, etc.)
```

**Command Line Options:**
- `--node NODE` - Specify target Proxmox node (optional)
- `--vm-id ID` - Specify VM ID (optional, auto-selected if omitted)
- `--port PORT` - Application port (required)

**Examples:**
```bash
# Interactive with auto-selection (recommended)
pxdcli generate api-service

# Auto VM ID on specific node
pxdcli generate api-service --type nodejs --port 3001 --node pve2

# Full manual control
pxdcli generate api-service --type nodejs --port 3001 --node pve2 --vm-id 150
```

### 4. Manage Services

```bash
# List all services
pxdcli list

# Check status of all services
pxdcli status

# Check specific service
pxdcli status python-api

# View logs
pxdcli logs python-api

# Restart service
pxdcli restart python-api

# Redeploy code changes (fast)
pxdcli redeploy python-api

# Clean up service
pxdcli cleanup python-api
```

## 📁 File Exclusion with .deployignore

The deployment system supports a `.deployignore` file that works similarly to `.gitignore` to control which files are excluded from deployment.

### How it works
- Place a `.deployignore` file in your service root directory (same level as your application code)
- List patterns of files/directories to exclude, one per line
- Supports comments (lines starting with `#`) and empty lines
- If no `.deployignore` file exists, default exclusions are used

### Default Exclusions (when no .deployignore file exists)
```
node_modules
.git
deployment
deployments
*.log
.env
```

### Example .deployignore file
```bash
# Version control
.git
.gitignore

# Dependencies
node_modules
__pycache__
*.pyc
venv

# Build artifacts
dist
build
target

# Logs and temporary files
*.log
*.tmp
logs

# Environment files
.env*

# IDE files
.vscode
.idea
*.swp

# OS files
.DS_Store
Thumbs.db

# Test files
test
tests
*.test.js
*.spec.py

# Documentation (optional)
docs
README.md
```

### Usage
1. Create a `.deployignore` file in your service directory:
   ```bash
   cd services/my-service
   cp ../../.deployignore.example .deployignore
   ```

2. Customize the patterns for your specific needs

3. Deploy as usual - the exclusions will be automatically applied:
   ```bash
   pxdcli deploy my-service
   ```

## 🔧 Configuration

### Global Configuration
Edit `global-config/env.proxmox.global`:
```bash
export PROXMOX_HOST="192.168.1.99"
export PROXMOX_USER="root@pam"
export TOKEN_ID="root@pam!deploy-root"
export TOKEN_SECRET="your-token-secret"
export CLOUDFLARE_DOMAIN="yourdomain.com"  # Optional
```

### Service-Specific Configuration
Each service has its own config in `deployments/<service>/env.service`:
```bash
export SERVICE_NAME="python-api"
export VM_ID="202"
export APP_PORT="8000"
export APP_SUBDOMAIN="api"
export SERVICE_HOSTNAME="python-api"
```

### Per-Service Configuration Override
Configure service-specific settings by editing `deployments/<service>/service-config.yml`:

```yaml
# Proxmox node override (leave empty to use global default)
proxmox_node: pve  # Deploy this service to specific node

# Health check path override (overrides service type default)
health_check_path: "/api/health"  # Custom health endpoint
```

**Workflow:**
1. **Generate service**: `pxdcli generate myservice --vm-id 203`
2. **Set target node**: Edit `deployments/myservice/service-config.yml` and set `proxmox_node: your-node`
3. **Update config**: `pxdcli update myservice`
4. **Deploy**: `pxdcli deploy myservice`

**Example - Multi-node deployment:**
```bash
# Deploy API to node pve1
echo "proxmox_node: pve1" >> deployments/api-service/service-config.yml

# Deploy database to node pve2  
echo "proxmox_node: pve2" >> deployments/postgres-db/service-config.yml

# Deploy cache to node pve3
echo "proxmox_node: pve3" >> deployments/redis-cache/service-config.yml

# Update and deploy all
pxdcli update
pxdcli deploy
```

## 🌐 Service Communication

Services communicate via DNS names:

```python
# Python service calling Go service
import httpx
response = await httpx.get("http://go-api.proxmox.local:8080/data")
```

```go
// Go service calling database
import "database/sql"
db, err := sql.Open("postgres", "postgres://user:pass@postgres-db.proxmox.local:5432/mydb")
```

```javascript
// Node.js service calling Python API
const response = await fetch('http://python-api.proxmox.local:8000/users');
```

## 📊 Service Management

### Per-Service Management
Each service has its own management script:

```bash
cd deployments/python-api

# Service operations
pxdcli status python-api    # Show service status
pxdcli logs python-api      # Show service logs  
pxdcli restart python-api   # Restart service

# Deployment operations
pxdcli deploy python-api    # Deploy/redeploy service
pxdcli cleanup python-api   # Remove service and VM
```

### Multi-Service Management
Use the CLI:

```bash
# Service discovery
pxdcli list

# Bulk operations
echo "All services status:" && pxdcli status
pxdcli deploy          # Deploy all services

# Individual operations
pxdcli logs python-api
pxdcli restart go-api
```

## 🔐 Security & Networking

### VM Isolation
- Each service gets its own VM/container
- Unique VM IDs and ports
- Independent resource allocation
- Isolated failures

### DNS Resolution
- Internal: `service-name.proxmox.local`
- External: `subdomain.yourdomain.com` (if Cloudflare configured)

### Firewall
- SSH (22) always open
- Service-specific ports
- Additional ports configurable per service

## 🛠️ Development Workflow

### 1. Create Service
```bash
pxdcli generate my-new-service

# Interactive 3-step process:
# Step 1: Node Selection - Shows available Proxmox nodes, asks for selection
# Step 2: VM ID Assignment - Auto-finds first available VM ID on selected node
# Step 3: Service Configuration - Prompts for port, subdomain, service type, etc.
# Step 4: Template Generation - Creates service code from Jinja2 templates
```

### 2. Develop
```bash
cd services/my-new-service
# Service code is already generated from templates with:
# - Proper error handling and HTTP status codes
# - Health check endpoints (/health)
# - Environment-based configuration
# - Runtime-specific optimizations

# Test locally: 
npm start          # Node.js services
bun run start      # Bun.js services  
python main.py     # Python services
go run main.go     # Go services
```

### 3. Deploy
```bash
pxdcli deploy my-new-service
```

### 4. Monitor
```bash
pxdcli status my-new-service
pxdcli logs my-new-service
```

## 🎯 Real-World Example: E-commerce Microservices

```bash
# Interactive generation (recommended - auto-selects nodes and VM IDs)
pxdcli generate api-gateway
pxdcli generate user-service
pxdcli generate order-service
pxdcli generate main-db
pxdcli generate redis-cache
pxdcli generate web-frontend

# Or use direct commands with template-based service creation
pxdcli generate api-gateway --type nodejs --runtime bun --port 3000 --node pve
# Generates: Bun.js server with health checks, CORS, proper error handling

pxdcli generate user-service --type nodejs --runtime node --port 3001 --node pve
# Generates: Node.js HTTP server with URL parsing, JSON responses

pxdcli generate main-db --type database --runtime postgresql \
  --port 5432 --db-name ecommerce --node pve
# Generates: PostgreSQL with user setup and database initialization

pxdcli generate web-frontend --type static --port 80 --node pve
# Generates: Nginx-served static site with proper configuration

# Deploy all services
pxdcli deploy
```

## 🔍 Troubleshooting

### Interactive Generation Issues

If you encounter issues with the interactive generation flow:

```bash
# Check if Proxmox API credentials are configured
echo $PROXMOX_HOST $TOKEN_ID $TOKEN_SECRET

# Test API connectivity
curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
  "https://${PROXMOX_HOST}:8006/api2/json/nodes"

# If API fails, the CLI will use fallback defaults
# You can still specify --node and --vm-id manually
```

### Check Service Status
```bash
pxdcli status service-name
```

### View Logs
```bash
pxdcli logs service-name
```

### SSH into VM
```bash
# Check service info and SSH via pxdcli (hostname-based)
pxdcli info service-name
pxdcli ssh service-name
ssh -i ~/.ssh/id_proxmox root@<VM_IP>
```

### Validate Configuration
```bash
cd deployments/service-name
ansible-playbook deploy.yml --syntax-check
```

## 🔄 Template Updates

When you modify templates, you don't need to regenerate all services:

### Update All Services
```bash
# Preview changes
pxdcli update --dry-run

# Apply updates to all services
pxdcli update
```

### Selective Updates
```bash
# Update only Node.js services
pxdcli update --template nodejs

# Update only specific services
pxdcli update service01 service02

# Update only deploy.yml files
pxdcli update --file deploy.yml.j2
```

### Template Update Workflow
1. **Modify Template**: Edit `deployment-templates/base/deploy.yml.j2`
2. **Update Version**: Edit `deployment-templates/.template-version`
3. **Preview Changes**: `pxdcli update --dry-run`
4. **Apply Updates**: `pxdcli update`

### Benefits
- ✅ **Preserves** service-specific configurations
- ✅ **Smart Updates** - only changes what's needed
- ✅ **Automatic Backups** - timestamped backups created
- ✅ **Selective** - target specific services or types
- ✅ **Safe** - dry-run mode to preview changes

## 🚀 Benefits

### DRY (Don't Repeat Yourself)
- Single source of truth for deployment logic
- Shared templates and configurations
- Centralized updates affect all services

### KISS (Keep It Simple, Stupid)
- Simple shell scripts for common operations
- Clear directory structure
- Minimal dependencies (Ansible + Bash)

### Multi-Language Support
- Use the right tool for each job
- Team specialization
- Technology freedom

### Service Isolation
- Independent scaling and configuration
- Isolated failures
- Resource optimization per service

## 📚 Advanced Topics

### Adding New Service Types
1. Create service type directory: `deployment-templates/service-types/newlang/`
2. Add deployment configuration files (config.yml, runtime_install.yml.j2, etc.)
3. Create starter templates: `deployment-templates/service-types/newlang/service-starter/`
4. Add Jinja2 templates for service files (main.ext.j2, package.json.j2, etc.)
5. Test with generator script using template-based creation

### Custom Environment Variables
Add to service config:
```yaml
custom_env_vars:
  DATABASE_URL: "postgresql://..."
  API_KEY: "secret-key"
```

### Health Check Configuration
Each service type has a default health check path that can be overridden:

**Default health check paths by service type:**
- **Node.js/Python/Go**: `/health`
- **Static sites**: `/` (root path)
- **Database/Tor-proxy**: `/` (port-based checks)

**Override per service:**
```yaml
# In deployments/<service>/service-config.yml
health_check_path: "/api/v1/health"  # Custom health endpoint
```

**Service-specific examples:**
```yaml
# API service with versioned health endpoint
health_check_path: "/api/v1/health"

# Admin service with custom path
health_check_path: "/admin/status"

# Microservice with detailed health checks
health_check_path: "/health/detailed"
```

### Resource Customization
```yaml
vm_cores: 4
vm_memory: 4096
vm_disk_size: 50
```

### Service Dependencies
```yaml
service_dependencies:
  - database
  - redis
```

---

## 🎉 You now have a production-ready, template-based, multi-language deployment system!

From simple single-service deployments to complex polyglot microservices architectures - all with:
- **Template-based service generation** using Jinja2 for consistent, high-quality code
- **Runtime-specific optimizations** (Node.js vs Bun, Python versions, etc.)
- **Built-in best practices** (health checks, error handling, CORS, environment configuration)
- **DRY and KISS principles** with centralized templates and simple management
- **Production-ready code** generated from the start with proper HTTP handling and logging