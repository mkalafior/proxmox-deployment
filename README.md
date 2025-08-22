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
# 1) Generate a service
pxdcli generate api-service --type nodejs --runtime bun --vm-id 201 --port 3001
pxdcli generate postgres-db --type database --runtime postgresql --vm-id 204 --port 5432 \
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
# Node.js/Bun.js API
./deployment-templates/generators/generate-multi-service.sh \
  api-service --type nodejs --runtime bun --vm-id 201 --port 3001

# Python FastAPI
./deployment-templates/generators/generate-multi-service.sh \
  python-api --type python --vm-id 202 --port 8000

# Go microservice
./deployment-templates/generators/generate-multi-service.sh \
  go-service --type golang --vm-id 203 --port 8080

# PostgreSQL database
./deployment-templates/generators/generate-multi-service.sh \
  postgres-db --type database --runtime postgresql \
  --vm-id 204 --port 5432 --db-name myapp --db-user myuser --db-pass secret123

# Static website
./deployment-templates/generators/generate-multi-service.sh \
  frontend --type static --vm-id 205 --port 80
```

### 2. Deploy Services

```bash
# Deploy single service
./manage-services.sh deploy python-api

# Deploy all services
./manage-services.sh deploy

# Or deploy from service directory
cd deployments/python-api && ./deploy.sh
```

### 3. Manage Services

```bash
# List all services
./manage-services.sh list

# Check status of all services
./manage-services.sh status

# Check specific service
./manage-services.sh status python-api

# View logs
./manage-services.sh logs python-api

# Restart service
./manage-services.sh restart python-api

# Clean up service
./manage-services.sh cleanup python-api
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
proxmox_node: pve-node-2  # Deploy this service to specific node
```

**Workflow:**
1. **Generate service**: `./deployment-templates/generators/generate-service-deployment.sh --service-name myservice --vm-id 203`
2. **Set target node**: Edit `deployments/myservice/service-config.yml` and set `proxmox_node: your-node`
3. **Update config**: `./deployment-templates/update-deployments.sh myservice`
4. **Deploy**: `cd deployments/myservice && ./deploy.sh`

**Example - Multi-node deployment:**
```bash
# Deploy API to node pve1
echo "proxmox_node: pve1" >> deployments/api-service/service-config.yml

# Deploy database to node pve2  
echo "proxmox_node: pve2" >> deployments/postgres-db/service-config.yml

# Deploy cache to node pve3
echo "proxmox_node: pve3" >> deployments/redis-cache/service-config.yml

# Update and deploy all
./deployment-templates/update-deployments.sh
./manage-services.sh deploy
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
./manage.sh status    # Show service status
./manage.sh logs      # Show service logs  
./manage.sh restart   # Restart service
./manage.sh info      # Show deployment info

# Deployment operations
./deploy.sh           # Deploy/redeploy service
./cleanup.sh          # Remove service and VM
```

### Multi-Service Management
Use the root-level script:

```bash
# Service discovery
./manage-services.sh list

# Bulk operations
./manage-services.sh status          # All services status
./manage-services.sh deploy          # Deploy all services

# Individual operations
./manage-services.sh logs python-api
./manage-services.sh restart go-api
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
./manage-services.sh generate my-new-service
# Interactive prompts for VM ID, port, type, etc.
```

### 2. Develop
```bash
cd services/my-new-service
# Edit your code
# Test locally: bun dev, python main.py, go run main.go
```

### 3. Deploy
```bash
./manage-services.sh deploy my-new-service
```

### 4. Monitor
```bash
./manage-services.sh status my-new-service
./manage-services.sh logs my-new-service
```

## 🎯 Real-World Example: E-commerce Microservices

```bash
# API Gateway (Node.js)
./deployment-templates/generators/generate-multi-service.sh \
  api-gateway --type nodejs --runtime bun --vm-id 201 --port 3000

# User Service (Python)
./deployment-templates/generators/generate-multi-service.sh \
  user-service --type python --vm-id 202 --port 8001

# Order Service (Go)
./deployment-templates/generators/generate-multi-service.sh \
  order-service --type golang --vm-id 203 --port 8002

# Main Database (PostgreSQL)
./deployment-templates/generators/generate-multi-service.sh \
  main-db --type database --runtime postgresql \
  --vm-id 204 --port 5432 --db-name ecommerce

# Cache (Redis)
./deployment-templates/generators/generate-multi-service.sh \
  redis-cache --type database --runtime redis \
  --vm-id 205 --port 6379

# Frontend (Static)
./deployment-templates/generators/generate-multi-service.sh \
  web-frontend --type static --vm-id 206 --port 80

# Deploy all services
./manage-services.sh deploy
```

## 🔍 Troubleshooting

### Check Service Status
```bash
./manage-services.sh status service-name
```

### View Logs
```bash
./manage-services.sh logs service-name
```

### SSH into VM
```bash
# Get VM IP
cat deployments/service-name/vm_ip.txt

# SSH into VM
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
./update-templates.sh --dry-run

# Apply updates to all services
./update-templates.sh
```

### Selective Updates
```bash
# Update only Node.js services
./update-templates.sh --template nodejs

# Update only specific services
./update-templates.sh service01 service02

# Update only deploy.yml files
./update-templates.sh --file deploy.yml.j2
```

### Template Update Workflow
1. **Modify Template**: Edit `deployment-templates/base/deploy.yml.j2`
2. **Update Version**: Edit `deployment-templates/.template-version`
3. **Preview Changes**: `./update-templates.sh --dry-run`
4. **Apply Updates**: `./update-templates.sh`

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