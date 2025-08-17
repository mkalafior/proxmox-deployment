#!/bin/bash

# Simplified Proxmox Template Setup Guide
# Provides step-by-step instructions for template setup

set -e

echo "📥 Proxmox Template Setup Assistant"
echo "==================================="

# Load environment variables
if [[ -f "../env.proxmox" ]]; then
    source ../env.proxmox
    echo "✅ Environment loaded"
else
    echo "❌ env.proxmox file not found"
    exit 1
fi

echo ""
echo "🎯 Template Setup Guide"
echo ""
echo "Your Proxmox server needs container templates before deployment."
echo "Here's how to set them up:"
echo ""

echo "📋 Step-by-Step Instructions:"
echo ""
echo "1️⃣  Open Proxmox Web Interface:"
echo "   🌐 https://$PROXMOX_HOST:8006"
echo "   👤 Username: ${PROXMOX_USER%@*}"
echo "   🔑 Password: [your password]"
echo ""

echo "2️⃣  Navigate to Templates:"
echo "   📁 Click: '$PROXMOX_NODE' (your node)"
echo "   💾 Click: 'local' (storage)"
echo "   📦 Click: 'CT Templates' tab"
echo ""

echo "3️⃣  Update Template List:"
echo "   🔄 Click: 'Templates' button (top toolbar)"
echo "   ⏳ Wait for the list to load (may take 30-60 seconds)"
echo ""

echo "4️⃣  Download Ubuntu Template:"
echo "   🔍 Find: 'ubuntu-22.04-standard' in the list"
echo "   📥 Click: 'Download' button next to it"
echo "   ⏳ Wait for download (2-5 minutes depending on connection)"
echo ""

echo "5️⃣  Verify Installation:"
echo "   ✅ Template should appear in the CT Templates list"
echo "   📋 Run: ./check-proxmox.sh (to verify)"
echo ""

echo "🚀 Alternative Quick Templates:"
echo "   If Ubuntu 22.04 isn't available, try:"
echo "   • ubuntu-20.04-standard (older but stable)"
echo "   • debian-12-standard (Debian alternative)"
echo "   • alpine-3.18-default (minimal, faster)"
echo ""

# Check if we can provide direct links
echo "🔗 Direct Links (if you prefer):"
echo "   Web Interface: https://$PROXMOX_HOST:8006"
echo "   Templates: https://$PROXMOX_HOST:8006/#v1:0:=node%2F$PROXMOX_NODE:4:5:=storage%2Flocal:8:9:=content%2Fvztmpl:::::"
echo ""

# Offer to open the browser
if command -v open >/dev/null 2>&1; then
    echo "💡 Quick Actions:"
    echo ""
    read -p "   Open Proxmox web interface in browser? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🌐 Opening browser..."
        open "https://$PROXMOX_HOST:8006"
    fi
fi

echo ""
echo "⏰ Estimated Time: 5-10 minutes total"
echo "   • Template list update: 1-2 minutes"
echo "   • Template download: 3-8 minutes"
echo ""

echo "🔍 After downloading, verify with:"
echo "   ./check-proxmox.sh"
echo ""
echo "🚀 Then deploy your app with:"
echo "   ./deploy.sh"
echo ""

echo "❓ Common Issues:"
echo "   • Template list empty: Click 'Templates' button and wait"
echo "   • Download slow: This is normal, templates are 100-500MB"
echo "   • Network error: Check internet connection"
echo "   • Permission error: Ensure you're logged in as root@pam"
echo ""

echo "💡 Need help? Check the Proxmox documentation:"
echo "   https://pve.proxmox.com/wiki/Linux_Container#_container_templates"
