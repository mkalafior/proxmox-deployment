# 🚀 Getting Started with Proxmox Deployment

This guide will walk you through deploying your Hello World Bun application to Proxmox VE in just a few steps.

## ⚡ Quick Deploy (5 minutes)

### Step 1: Environment Setup

```bash
# Copy environment template
cp env.example .env

# Edit the environment file with your Proxmox details
export PROXMOX_HOST="192.168.1.100"       # Your Proxmox server IP
export PROXMOX_PASSWORD="your_password"    # Your Proxmox root password
export PROXMOX_NODE="proxmox"             # Your Proxmox node name
```

### Step 2: Install Prerequisites

```bash
# Install Ansible (if not already installed)
# macOS:
brew install ansible

# Ubuntu/Debian:
sudo apt update && sudo apt install ansible

# Or via pip:
pip3 install ansible
```

### Step 3: Deploy!

```bash
# Navigate to deployment directory
cd deployment

# Deploy your application
./deploy.sh
```

That's it! 🎉

## 📋 What Happens During Deployment

1. **Environment Validation** - Checks Proxmox connection and prerequisites
2. **SSH Key Generation** - Creates SSH key for secure access (if needed)
3. **Container Creation** - Creates Ubuntu 22.04 LXC container in Proxmox
4. **System Setup** - Installs packages, configures firewall
5. **Bun Installation** - Installs latest Bun runtime
6. **App Deployment** - Copies your code and installs dependencies
7. **Service Configuration** - Sets up systemd service for auto-start
8. **Health Check** - Verifies deployment and provides access URLs

## 🎯 After Deployment

Your application will be running at:
- **Main App**: `http://[VM_IP]:3000`
- **Health Check**: `http://[VM_IP]:3000/health`
- **API Info**: `http://[VM_IP]:3000/api/info`

## 🔧 Management Commands

```bash
# Check application status
ansible-playbook manage.yml --tags=status

# View application logs
ansible-playbook manage.yml --tags=logs

# Restart application
ansible-playbook manage.yml --tags=restart

# Update application code
./redeploy.sh

# Remove everything
./cleanup.sh
```

## 🛠️ Prerequisites on Proxmox

Before deploying, ensure your Proxmox server has:

### 1. Container Template
Download Ubuntu 22.04 container template:
1. Login to Proxmox web interface
2. Go to your node → Local → Container Templates
3. Click "Templates" button
4. Download: `ubuntu-22.04-standard`

### 2. Network Bridge
Ensure you have a network bridge configured (usually `vmbr0`).

### 3. Resources Available
- At least 2GB RAM free
- 20GB storage space
- CPU cores available

## 🐛 Troubleshooting

### Common Issues

**"Connection refused" to Proxmox:**
```bash
# Test connection
curl -k https://$PROXMOX_HOST:8006/api2/json/version
```

**"Template not found":**
- Download Ubuntu 22.04 template in Proxmox web interface
- Update `VM_TEMPLATE` in `group_vars/all.yml` if using custom template

**"SSH connection failed":**
- Check if container is running in Proxmox web interface
- Verify network configuration
- Check firewall rules

**"Service failed to start":**
```bash
# SSH into container and check logs
ssh -i ~/.ssh/id_rsa root@[VM_IP]
journalctl -u hello-world-bun-app -f
```

## 📖 Advanced Configuration

### Custom VM Settings
Edit `deployment/group_vars/all.yml` to customize:
- VM resources (CPU, RAM, disk)
- Network configuration
- Application settings
- Security options

### Environment Variables
Add custom environment variables in `deployment/templates/env.j2`.

### Service Configuration
Modify systemd service in `deployment/templates/hello-world-bun-app.service.j2`.

## 🔐 Security Notes

- Container runs as unprivileged LXC container
- Application runs as dedicated user (not root)
- Firewall configured to only allow necessary ports
- SSH key authentication (no password)

## 💡 Tips

1. **Start Simple**: Use default settings for first deployment
2. **Test Locally**: Run `bun src/index.js` locally first
3. **Monitor Resources**: Check Proxmox web interface for resource usage
4. **Backup**: Consider setting up automated backups in Proxmox
5. **Scale**: Increase VM resources as needed via Proxmox web interface

## 📞 Need Help?

- Check the detailed `deployment/README.md`
- Review Ansible playbook logs
- SSH into the container for debugging
- Check Proxmox web interface for container status

---

**Ready to deploy?** 🚀

```bash
cd deployment && ./deploy.sh
```
