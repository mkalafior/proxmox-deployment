# Proxmox Multi-Service Deployment System

A DRY and KISS approach to deploying multiple services to Proxmox VE with automated VM provisioning, service management, and optional Cloudflare tunnel exposure.

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
│   ├── service-types/          # Language-specific configs
│   └── generators/             # Generation scripts
├── global-config/              # Global configuration
│   ├── env.proxmox.global      # Global Proxmox settings
│   └── deployment-defaults.yml # Default values
└── manage-services.sh          # Multi-service management
```

## 🚀 Supported Service Types

### Programming Languages
- **Node.js/Bun.js** - REST APIs, GraphQL, real-time apps
- **Python** - FastAPI, Flask, Django applications  
- **Go** - High-performance compiled services
- **Rust** - Systems programming (template ready)

### Infrastructure Services
- **PostgreSQL** - ACID database with user setup
- **MySQL** - Traditional relational database
- **Redis** - In-memory cache/store
- **MongoDB** - Document database
- **Static Sites** - Nginx-served websites

## 🔧 Installation (Linux/macOS)

Install the global templates and CLI once, then use them from any project without copying files.

### Prerequisites
- git, bash

### Linux
```bash
git clone https://github.com/your-org/proxmox-deploy-playground
cd proxmox-deploy-playground
bash tools/install-global-templates.sh

# Ensure CLI is on your PATH (add once)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
pxdcli help
```

### macOS (zsh)
```bash
git clone https://github.com/your-org/proxmox-deploy-playground
cd proxmox-deploy-playground
bash tools/install-global-templates.sh

# Ensure CLI is on your PATH (add once)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Verify
pxdcli help
```

Notes
- The installer places templates in `~/.proxmox-deploy/templates` and symlinks the CLI to `~/.local/bin/pxdcli`.
- The CLI auto-updates templates (`git pull`) on use.
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

# Direct command with auto VM ID selection
pxdcli generate api-service --type nodejs --runtime bun --port 3001

# Specify node manually (auto VM ID selection)
pxdcli generate python-api --type python --port 8000 --node pve2

# Full manual control
pxdcli generate postgres-db --type database --runtime postgresql \
  --node pve1 --vm-id 204 --port 5432 --db-name myapp --db-user myuser --db-pass secret123
```

### 2. Deploy Services

```bash
# Deploy single service
pxdcli deploy python-api

# Deploy all services
pxdcli deploy

# Or deploy from service directory
cd deployments/python-api && ./deploy.sh
```

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

### 3. Manage Services

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

# Clean up service
pxdcli cleanup python-api
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

### Per-Service Proxmox Node Override
Deploy different services to different Proxmox nodes by configuring `deployments/<service>/service-config.yml`:

```yaml
# Proxmox node override (leave empty to use global default)
proxmox_node: pve  # Deploy this service to specific node
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
```

### 2. Develop
```bash
cd services/my-new-service
# Edit your code
# Test locally: bun dev, python main.py, go run main.go
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

# Or use direct commands with auto-selection
pxdcli generate api-gateway --type nodejs --runtime bun --port 3000 --node pve

pxdcli generate main-db --type database --runtime postgresql \
  --port 5432 --db-name ecommerce --node pve

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
1. Create config in `deployment-templates/service-types/newlang/`
2. Define runtime installation, dependencies, systemd service
3. Test with generator script

### Custom Environment Variables
Add to service config:
```yaml
custom_env_vars:
  DATABASE_URL: "postgresql://..."
  API_KEY: "secret-key"
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

## 🎉 You now have a production-ready, multi-language, scalable deployment system!

From simple single-service deployments to complex polyglot microservices architectures - all with consistent, DRY, and KISS principles.