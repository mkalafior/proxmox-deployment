# Hello World Bun App - Proxmox Deployment

A simple Hello World application built with Bun, designed to be deployed to Proxmox Virtual Environment using Ansible.

## 🚀 Quick Start

### Local Development

```bash
# Install Bun (if not already installed)
curl -fsSL https://bun.sh/install | bash

# Install dependencies
bun install

# Run in development mode
bun run dev

# Or run normally
bun run start
```

The application will be available at `http://localhost:3000`

### Available Endpoints

- `/` - Main homepage with server information
- `/health` - Health check endpoint (JSON)
- `/api/info` - Application information (JSON)

## 🏗️ Deployment to Proxmox

This project includes a complete Ansible-based deployment system for Proxmox Virtual Environment.

### Prerequisites

1. **Proxmox VE Server** running locally
2. **Ansible** installed on your local machine
3. **SSH access** to your Proxmox server
4. **API access** to Proxmox (username/password or API tokens)

### Deployment Commands

```bash
# Navigate to deployment directory
cd deployment

# Initial deployment (creates VM and deploys app)
./deploy.sh

# Redeploy code changes (keeps VM, updates app)
./redeploy.sh

# Clean up (removes VM and resources)
./cleanup.sh
```

### Configuration

1. **Set environment variables** (copy from `env.example`):
```bash
export PROXMOX_HOST="192.168.1.100"
export PROXMOX_USER="root@pam"
export PROXMOX_PASSWORD="your_password"
export PROXMOX_NODE="proxmox"
```

2. **Optional**: Customize VM settings in `deployment/group_vars/all.yml`:
- VM specifications (CPU, RAM, storage)
- Network configuration (bridge, IP assignment)
- Application settings (port, environment variables)
- Security settings (firewall ports)

## 📦 Project Structure

```
proxmox-deploy-playground/
├── src/
│   └── index.js          # Main Bun application
├── deployment/           # Complete Ansible automation
│   ├── deploy.sh        # 🚀 Main deployment script
│   ├── redeploy.sh      # 🔄 Code update script  
│   ├── cleanup.sh       # 🧹 Cleanup script
│   ├── deploy.yml       # Main Ansible playbook
│   ├── redeploy.yml     # Code redeployment playbook
│   ├── manage.yml       # Management tasks playbook
│   ├── ansible.cfg      # Ansible configuration
│   ├── requirements.yml # Ansible Galaxy requirements
│   ├── inventory.yml    # Dynamic inventory
│   ├── group_vars/
│   │   └── all.yml      # Configuration variables
│   ├── templates/
│   │   ├── hello-world-bun-app.service.j2  # Systemd service
│   │   └── env.j2       # Environment template
│   └── README.md        # Deployment documentation
├── package.json         # Bun project configuration
├── env.example         # Environment variables template
└── README.md           # This file
```

## 🔧 Features

- **Fast Runtime**: Built with Bun for excellent performance
- **Health Monitoring**: Built-in health check endpoints
- **Automated Deployment**: Complete Ansible automation for Proxmox
- **Production Ready**: Systemd service, proper logging, error handling
- **Resource Efficient**: Minimal resource usage perfect for VMs

## 🛡️ Security

The deployment includes:
- Firewall configuration (UFW)
- Service user (non-root execution)
- Secure file permissions
- SSH key-based authentication

## 📊 Monitoring

Monitor your deployed application:

```bash
# Check service status
ansible-playbook manage.yml --tags=status

# View logs
ansible-playbook manage.yml --tags=logs

# Restart service
ansible-playbook manage.yml --tags=restart
```
