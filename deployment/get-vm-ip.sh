#!/bin/bash

# Get VM IP address from Proxmox
source ../env.proxmox

echo "🔍 Getting IP address for VM $VM_ID on node $PROXMOX_NODE..."

# Try to get IP via Proxmox API (if working) or provide manual instructions
echo ""
echo "VM Information:"
echo "  VM ID: $VM_ID"
echo "  Node: $PROXMOX_NODE" 
echo "  Name: hello-world-bun-app"
echo ""

echo "🌐 To find the VM's IP address:"
echo "1. Open Proxmox web interface: https://$PROXMOX_HOST:8006"
echo "2. Navigate to: $PROXMOX_NODE → $VM_ID (hello-world-bun-app)"
echo "3. Click on the VM and look at the Summary tab"
echo "4. Find the IP address in the network section"
echo ""

echo "💡 Common IP ranges:"
echo "   - 192.168.1.x (if using bridge to your LAN)"
echo "   - 10.0.0.x or 172.16.x.x (if using NAT)"
echo ""

echo "📝 Once you have the IP address:"
echo "   echo 'FOUND_IP_HERE' > vm_ip.txt"
echo "   Example: echo '192.168.1.150' > vm_ip.txt"
echo ""

echo "🚀 Then continue deployment:"
echo "   ./continue-deployment.sh"
