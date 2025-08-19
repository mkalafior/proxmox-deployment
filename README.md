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

Check `./deployment` directory.