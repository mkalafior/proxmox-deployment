#!/bin/bash

# Proxmox Setup Checker
# This script helps verify Proxmox configuration before deployment

set -e

echo "🔍 Proxmox Setup Checker"
echo "========================"

# Load environment variables
if [[ -f "../env.proxmox" ]]; then
    source ../env.proxmox
    echo "✅ Loaded environment from env.proxmox"
else
    echo "❌ env.proxmox file not found"
    echo "   Please create it with your Proxmox credentials"
    exit 1
fi

echo ""
echo "📡 Testing Proxmox Connection..."
echo "   Host: $PROXMOX_HOST"
echo "   User: $PROXMOX_USER"
echo "   Node: $PROXMOX_NODE"

# Test basic connectivity
if ! ping -c 1 $PROXMOX_HOST >/dev/null 2>&1; then
    echo "❌ Cannot reach Proxmox host $PROXMOX_HOST"
    exit 1
fi
echo "✅ Host is reachable"

# Test API authentication
echo ""
echo "🔐 Testing API Authentication..."

# Handle special characters in password properly
TICKET_RESPONSE=$(curl -k -s -X POST https://$PROXMOX_HOST:8006/api2/json/access/ticket \
    -d "username=$PROXMOX_USER" \
    -d "password=$PROXMOX_PASSWORD" 2>/dev/null)

echo "🐛 DEBUG - Auth response:"
echo "$TICKET_RESPONSE" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null || echo "Could not parse auth response: $TICKET_RESPONSE"

if echo "$TICKET_RESPONSE" | grep -q '"ticket"'; then
    echo "✅ API authentication successful"
    TICKET=$(echo "$TICKET_RESPONSE" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data['data']['ticket'])" 2>/dev/null)
    CSRF_TOKEN=$(echo "$TICKET_RESPONSE" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data['data']['CSRFPreventionToken'])" 2>/dev/null)
    
    # Create proper cookie like browser does - URL encode the entire ticket
    ENCODED_TICKET=$(echo "$TICKET" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read().strip()))")
    COOKIE="PVEAuthCookie=PVE%3Aroot%40pam%3A${ENCODED_TICKET}"
    echo "🐛 DEBUG - Cookie: ${COOKIE:0:80}..."
else
    echo "❌ API authentication failed"
    echo "   This might be due to:"
    echo "   - Incorrect credentials"
    echo "   - Special characters in password"
    echo "   - Two-factor authentication enabled"
    echo "   - User lacks API permissions"
    echo ""
    echo "💡 Try logging into the web interface first:"
    echo "   https://$PROXMOX_HOST:8006"
    exit 1
fi

# Check cluster nodes first
echo ""
echo "🌐 Checking Cluster Nodes..."
NODES_RESPONSE=$(curl -k -s -H "Cookie: $COOKIE" \
    "https://$PROXMOX_HOST:8006/api2/json/nodes" 2>/dev/null)

echo "🐛 DEBUG - Nodes API response:"
echo "$NODES_RESPONSE" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null || echo "Could not parse nodes response"

if echo "$NODES_RESPONSE" | grep -q '"data"'; then
    echo "✅ Found cluster nodes:"
    AVAILABLE_NODES=$(echo "$NODES_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    nodes = []
    for node in data['data']:
        status = 'online' if node['status'] == 'online' else 'offline'
        print(f'   - {node[\"node\"]} ({status})')
        if node['status'] == 'online':
            nodes.append(node['node'])
    print('|'.join(nodes))
except Exception as e:
    print('Error parsing nodes')
    print('')
" | tail -1)
else
    echo "⚠️  Could not retrieve cluster information"
    AVAILABLE_NODES="$PROXMOX_NODE"
fi

# Check available storage on current node
echo ""
echo "💾 Checking Available Storage on node '$PROXMOX_NODE'..."
STORAGE_RESPONSE=$(curl -k -s -H "Cookie: $COOKIE" \
    "https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_NODE/storage" 2>/dev/null)

echo "🐛 DEBUG - Storage API response for $PROXMOX_NODE:"
echo "$STORAGE_RESPONSE" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null || echo "Could not parse storage response"

if echo "$STORAGE_RESPONSE" | grep -q '"data"'; then
    echo "✅ Storage API accessible on $PROXMOX_NODE"
    echo "$STORAGE_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print('📁 Available Storage:')
    for storage in data['data']:
        print(f'   - {storage[\"storage\"]} ({storage[\"type\"]}) - Content: {storage.get(\"content\", \"N/A\")}')
except:
    print('   Could not parse storage information')
"
else
    echo "⚠️  Could not retrieve storage information for $PROXMOX_NODE"
fi

# Check available templates on all nodes
echo ""
echo "📦 Checking Available Container Templates..."

# Get all nodes to check
ALL_NODES="pve proxmox $PROXMOX_NODE"
if [[ -n "$AVAILABLE_NODES" ]]; then
    ALL_NODES="$AVAILABLE_NODES"
fi

# Remove duplicates
ALL_NODES=$(echo "$ALL_NODES" | tr ' ' '\n' | sort -u | tr '\n' ' ')

for node in $ALL_NODES; do
    echo ""
    echo "🔍 Checking node: $node"
    
    # Try different storage locations
    for storage in "local" "local-lvm" "pve-storage"; do
        echo "   Checking storage: $storage on $node"
        TEMPLATE_RESPONSE=$(curl -k -s -H "Cookie: $COOKIE" \
            "https://$PROXMOX_HOST:8006/api2/json/nodes/$node/storage/$storage/content?content=vztmpl" 2>/dev/null)
        
        echo "   🐛 DEBUG - Template API response for $node/$storage:"
        echo "   $TEMPLATE_RESPONSE" | python3 -c "import json, sys; print('   ' + json.dumps(json.load(sys.stdin), indent=2).replace('\n', '\n   '))" 2>/dev/null || echo "   Could not parse template response"
        
        if echo "$TEMPLATE_RESPONSE" | grep -q '"volid"'; then
            echo "   ✅ Found templates in $storage on $node:"
            echo "$TEMPLATE_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if data['data']:
        for template in data['data']:
            print(f'      - {template[\"volid\"]}')
    else:
        print('      (No templates found)')
except:
    print('      (Could not parse template list)')
"
            FOUND_TEMPLATES=true
        elif echo "$TEMPLATE_RESPONSE" | grep -q '"data"'; then
            echo "   ℹ️  Storage $storage accessible on $node but no templates"
        else
            echo "   ⚠️  Could not access storage $storage on $node"
        fi
    done
done

if [[ -z "$FOUND_TEMPLATES" ]]; then
    echo ""
    echo "❌ No container templates found!"
    echo ""
    echo "📥 To fix this, download templates via Proxmox Web UI:"
    echo "   1. Go to: https://$PROXMOX_HOST:8006"
    echo "   2. Navigate: $PROXMOX_NODE → local → CT Templates"
    echo "   3. Click: 'Templates' button"
    echo "   4. Download: Ubuntu 22.04 (recommended)"
    echo ""
    echo "💡 Popular templates:"
    echo "   - ubuntu-22.04-standard (recommended)"
    echo "   - debian-12-standard"
    echo "   - alpine-3.18-default (minimal)"
    echo ""
    exit 1
else
    echo ""
    echo "✅ Container templates are available!"
fi

# Check network configuration
echo ""
echo "🌐 Checking Network Configuration..."
NETWORK_RESPONSE=$(curl -k -s -H "Cookie: $COOKIE" \
    "https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_NODE/network" 2>/dev/null)

if echo "$NETWORK_RESPONSE" | grep -q 'vmbr'; then
    echo "✅ Network bridges found:"
    echo "$NETWORK_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for iface in data['data']:
        if 'vmbr' in iface.get('iface', ''):
            print(f'   - {iface[\"iface\"]} - {iface.get(\"comments\", \"No description\")}')
except:
    print('   Could not parse network information')
"
else
    echo "⚠️  Could not retrieve network information"
fi

echo ""
echo "🎉 Proxmox Setup Check Complete!"
echo ""
echo "🚀 If everything looks good, you can now run:"
echo "   ./deploy.sh"
echo ""
echo "🔧 If you need to download templates:"
echo "   1. Open web browser: https://$PROXMOX_HOST:8006"
echo "   2. Navigate to: $PROXMOX_NODE → local → CT Templates"
echo "   3. Download Ubuntu 22.04 template"
echo "   4. Run this script again to verify"
