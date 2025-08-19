# Proxmox Hello World App - Simplified Deployment

🚀 **One-command deployment with optional Cloudflare exposure**

This deployment system automatically:
- Deploys your Bun application to Proxmox LXC container
- Optionally configures Cloudflare tunnel routing for public access
- Supports both internal-only and public deployments
- Uses SSH key authentication (no password prompts)

## 📋 Prerequisites

### 1. Environment Setup
Create `env.proxmox` file in the project root:

```bash
# Proxmox Configuration
export PROXMOX_HOST="192.168.1.99"
export PROXMOX_USER="root@pam"
export PROXMOX_PASSWORD="your_password"
export PROXMOX_NODE="proxmox"

# Optional: API Token (recommended for automation)
export TOKEN_ID="root@pam!your_token_name"
export TOKEN_SECRET="your_token_secret"

# VM Configuration
export VM_ID="200"
export VM_TEMPLATE="local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"

# Cloudflare Configuration (Optional - for public access)
# Leave these unset for internal-only deployment
export CLOUDFLARE_DOMAIN="yourdomain.com"
export APP_SUBDOMAIN="app"
```

### 2. Required Software
- **Ansible**: `brew install ansible` (macOS) or `apt install ansible` (Ubuntu)
- **SSH Key**: Dedicated Proxmox SSH key at `~/.ssh/id_proxmox`

### 3. Cloudflare Tunnel (Optional)
If you want public access, ensure Cloudflare tunnel is already set up on your Proxmox server with tunnel name `proxmox-main`.

## 🚀 Quick Start

### Deployment Options

**Option 1: Internal-Only Deployment**
```bash
# Remove or comment out Cloudflare settings in env.proxmox
# export CLOUDFLARE_DOMAIN="yourdomain.com"
# export APP_SUBDOMAIN="app"

cd deployment
./deploy-and-expose.sh
```
Your app will be accessible only within your network at `http://VM_IP:3000`

**Option 2: Public Deployment with Cloudflare**
```bash
# Set Cloudflare settings in env.proxmox
export CLOUDFLARE_DOMAIN="yourdomain.com"
export APP_SUBDOMAIN="app"

cd deployment
./deploy-and-expose.sh
```
Your app will be accessible both internally and publicly at `https://app.yourdomain.com`

### Initial Deployment
```bash
# Navigate to deployment directory
cd deployment

# One-command deployment with automatic exposure
./deploy-and-expose.sh
```

**That's it!** Your app will be:
- ✅ Deployed to Proxmox container
- ✅ Automatically exposed via Cloudflare tunnel
- ✅ Accessible at `https://app.yourdomain.com`

### Code Updates (After Initial Deployment)

When you need to update your application code without recreating the VM:

```bash
# Option 1: Use the main script (it will detect existing deployment)
./deploy-and-expose.sh
# Choose option 2 when prompted for "Code update only"

# Option 2: Direct code update
./redeploy-code.sh

# Option 3: Via management script
./manage.sh update
```

**Code updates:**
- ✅ Keep existing VM and configuration
- ✅ Update application code only
- ✅ Maintain Cloudflare tunnel routing
- ✅ Minimal downtime (rolling update)

## 🛠️ Management Commands

### Application Management
```bash
# Check application status
./manage.sh status

# View application logs
./manage.sh logs

# Restart application
./manage.sh restart

# Show system information
./manage.sh system

# Show deployment info
./manage.sh info
```

### Deployment Management
```bash
# Clean up deployment (removes VM)
./cleanup.sh

# SSH into VM
ssh -i ~/.ssh/id_proxmox root@$(cat vm_ip.txt)
```

## 📁 File Structure

```
deployment/
├── deploy-and-expose.sh        # 🚀 Master deployment script (with smart detection)
├── redeploy-code.sh            # 🔄 Code-only update script  
├── manage.sh                   # 🛠️ Application management
├── cleanup.sh                  # 🧹 Cleanup deployment
├── deploy.yml                  # 📜 Main Ansible playbook
├── redeploy.yml                # 📜 Code update playbook
├── manage.yml                  # 📜 Management playbook
├── inventory.yml               # 📋 Ansible inventory
├── group_vars/all.yml          # ⚙️ Configuration variables
├── requirements.yml            # 📦 Ansible dependencies
├── templates/                  # 📄 Ansible templates
│   ├── env.j2
│   └── hello-world-bun-app.service.j2
├── vm_ip.txt                   # 📍 Deployed VM IP (auto-generated)
├── vm_credentials.txt          # 🔐 VM credentials (auto-generated)
└── README.md                   # 📖 This file
```

## 🔧 How It Works

### 1. Automated Deployment Flow
```
deploy-and-expose.sh
├── ✅ Check environment & SSH access
├── ✅ Deploy VM using Ansible
├── ✅ Get VM IP address
├── ✅ Test application connectivity
├── ✅ Update Cloudflare tunnel config
├── ✅ Restart cloudflared service
└── ✅ Test final URL accessibility
```

### 2. SSH Key Authentication
- Uses dedicated SSH key: `~/.ssh/id_proxmox`
- Automatic passwordless authentication
- Secure and automated access

### 3. Cloudflare Integration
- Automatically updates tunnel configuration
- Points `app.yourdomain.com` to deployed VM
- Restarts cloudflared service
- Zero manual intervention

## 🎯 What Gets Deployed

### VM Configuration
- **OS**: Ubuntu 24.04 LXC Container
- **Resources**: 2 CPU cores, 2GB RAM, 20GB disk
- **Networking**: DHCP (dynamic IP)
- **Services**: Systemd service for Bun app

### Application Setup
- **Runtime**: Bun (installed automatically)
- **Port**: 3000
- **Service**: `hello-world-bun-app.service`
- **User**: `bunapp` (dedicated app user)
- **Location**: `/opt/hello-world-bun-app`

### Cloudflare Exposure
- **URL**: `https://app.yourdomain.com`
- **SSL**: Automatic via Cloudflare
- **Routing**: Direct to VM IP:3000

## 🧹 Cleanup

To remove everything:
```bash
./cleanup.sh
```

This removes:
- Proxmox container
- Local deployment files
- Preserves SSH keys for future use

## 🔍 Troubleshooting

### Common Issues

1. **SSH Authentication Failed**
   ```bash
   # Copy SSH key to Proxmox
   ssh-copy-id -i ~/.ssh/id_proxmox.pub root@192.168.1.99
   ```

2. **Cloudflare Tunnel Not Found**
   - Ensure tunnel `proxmox-main` exists on Proxmox server
   - Check tunnel status: `ssh root@proxmox "cloudflared tunnel list"`

3. **502 Bad Gateway**
   - Wait 2-5 minutes for DNS propagation
   - Check application status: `./manage.sh status`

4. **VM Deployment Failed**
   - Verify Proxmox credentials in `env.proxmox`
   - Check Proxmox template exists
   - Ensure sufficient resources available

### Debug Commands
```bash
# Check VM connectivity
ssh -i ~/.ssh/id_proxmox root@$(cat vm_ip.txt)

# Check application logs
./manage.sh logs

# Check Cloudflare tunnel status
ssh -i ~/.ssh/id_proxmox root@192.168.1.99 "systemctl status cloudflared"

# Test local application
curl http://$(cat vm_ip.txt):3000
```

## 🔐 Security Notes

- Uses dedicated SSH key for Proxmox access
- LXC container runs unprivileged
- Application runs as non-root user
- Cloudflare provides SSL termination
- Direct Proxmox access remains available locally

## 🚀 Next Steps

After successful deployment:
1. **Customize application** - Edit source code and redeploy
2. **Set up monitoring** - Use `./manage.sh status` for health checks
3. **Configure backups** - Set up automated Proxmox backups
4. **Scale resources** - Adjust VM specs in `group_vars/all.yml`

---

**💡 Pro Tip**: The deployment creates a complete, production-ready setup with automatic SSL, monitoring, and management tools. Perfect for rapid application deployment and testing!