#!/bin/bash

# Proxmox Container Template Download Script
# Automatically downloads Ubuntu 22.04 LXC template

set -e

echo "📥 Proxmox Template Downloader"
echo "=============================="

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
echo "🔍 Checking Proxmox connection..."

# Test connectivity
if ! ping -c 1 $PROXMOX_HOST >/dev/null 2>&1; then
    echo "❌ Cannot reach Proxmox host $PROXMOX_HOST"
    exit 1
fi

# Get API ticket
echo "🔐 Authenticating with Proxmox API..."
TICKET_RESPONSE=$(curl -k -s -X POST https://$PROXMOX_HOST:8006/api2/json/access/ticket \
    -d "username=$PROXMOX_USER" \
    -d "password=$PROXMOX_PASSWORD" 2>/dev/null)

if ! echo "$TICKET_RESPONSE" | grep -q '"ticket"'; then
    echo "❌ API authentication failed"
    echo "   Response: $TICKET_RESPONSE"
    exit 1
fi

TICKET=$(echo "$TICKET_RESPONSE" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data['data']['ticket'])" 2>/dev/null)
CSRF_TOKEN=$(echo "$TICKET_RESPONSE" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data['data']['CSRFPreventionToken'])" 2>/dev/null)

echo "✅ Authentication successful"

# Check if template already exists
echo ""
echo "🔍 Checking existing templates..."
EXISTING_TEMPLATES=$(curl -k -s -H "Authorization: PVEAuthCookie=PVE:$PROXMOX_USER:$TICKET" \
    "https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_NODE/storage/local/content?content=vztmpl" 2>/dev/null)

if echo "$EXISTING_TEMPLATES" | grep -q "ubuntu-22.04-standard"; then
    echo "✅ Ubuntu 22.04 template already exists!"
    echo ""
    echo "📦 Available templates:"
    echo "$EXISTING_TEMPLATES" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for template in data['data']:
        if 'ubuntu-22.04' in template['volid']:
            print(f'   - {template[\"volid\"]}')
except:
    pass
"
    echo ""
    echo "🚀 You can now run: ./deploy.sh"
    exit 0
fi

# Get list of available templates to download
echo "📋 Getting list of available templates..."
APPLIANCE_INFO=$(curl -k -s -H "Authorization: PVEAuthCookie=PVE:$PROXMOX_USER:$TICKET" \
    "https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_NODE/aplinfo" 2>/dev/null)

if ! echo "$APPLIANCE_INFO" | grep -q '"data"'; then
    echo "❌ Could not get template list from Proxmox"
    echo "   You may need to update the appliance info first"
    echo ""
    echo "💡 Manual steps:"
    echo "   1. Go to: https://$PROXMOX_HOST:8006"
    echo "   2. Navigate: $PROXMOX_NODE → local → CT Templates"
    echo "   3. Click 'Templates' to update the list"
    echo "   4. Download ubuntu-22.04-standard"
    exit 1
fi

# Find Ubuntu 22.04 template
echo "🔍 Looking for Ubuntu 22.04 template..."
UBUNTU_TEMPLATE=$(echo "$APPLIANCE_INFO" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for template in data['data']:
        if ('ubuntu-22.04-standard' in template.get('template', '').lower() or 
            'ubuntu' in template.get('package', '').lower() and '22.04' in template.get('version', '')):
            print(f'{template[\"template\"]}')
            break
except Exception as e:
    pass
")

if [[ -z "$UBUNTU_TEMPLATE" ]]; then
    echo "❌ Ubuntu 22.04 template not found in available templates"
    echo ""
    echo "📋 Available templates:"
    echo "$APPLIANCE_INFO" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for template in data['data']:
        desc = template.get('headline', template.get('package', 'Unknown'))
        print(f'   - {template[\"template\"]} - {desc}')
except:
    print('   Could not parse template list')
"
    echo ""
    echo "💡 You can download any template manually via web interface:"
    echo "   https://$PROXMOX_HOST:8006 → $PROXMOX_NODE → local → CT Templates"
    exit 1
fi

echo "✅ Found template: $UBUNTU_TEMPLATE"

# Download the template
echo ""
echo "📥 Downloading template (this may take several minutes)..."
echo "   Template: $UBUNTU_TEMPLATE"
echo "   Storage: local"

DOWNLOAD_RESPONSE=$(curl -k -s -X POST \
    -H "Authorization: PVEAuthCookie=PVE:$PROXMOX_USER:$TICKET" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -d "storage=local" \
    -d "template=$UBUNTU_TEMPLATE" \
    "https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_NODE/aplinfo" 2>/dev/null)

if echo "$DOWNLOAD_RESPONSE" | grep -q '"data"'; then
    TASK_ID=$(echo "$DOWNLOAD_RESPONSE" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data['data'])" 2>/dev/null)
    echo "✅ Download started (Task ID: $TASK_ID)"
    
    # Monitor download progress
    echo "⏳ Monitoring download progress..."
    for i in {1..60}; do  # Wait up to 10 minutes
        sleep 10
        TASK_STATUS=$(curl -k -s -H "Authorization: PVEAuthCookie=PVE:$PROXMOX_USER:$TICKET" \
            "https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_NODE/tasks/$TASK_ID/status" 2>/dev/null)
        
        if echo "$TASK_STATUS" | grep -q '"exitstatus":"OK"'; then
            echo "✅ Template download completed successfully!"
            break
        elif echo "$TASK_STATUS" | grep -q '"status":"stopped"'; then
            echo "❌ Template download failed"
            echo "   Check Proxmox web interface for details"
            exit 1
        else
            printf "."
        fi
        
        if [[ $i -eq 60 ]]; then
            echo ""
            echo "⏰ Download is taking longer than expected"
            echo "   Check the Proxmox web interface for progress: https://$PROXMOX_HOST:8006"
            echo "   The download may still be running in the background"
        fi
    done
else
    echo "❌ Failed to start template download"
    echo "   Response: $DOWNLOAD_RESPONSE"
    echo ""
    echo "💡 Try downloading manually via web interface:"
    echo "   https://$PROXMOX_HOST:8006 → $PROXMOX_NODE → local → CT Templates"
    exit 1
fi

# Verify template is now available
echo ""
echo "🔍 Verifying template installation..."
FINAL_CHECK=$(curl -k -s -H "Authorization: PVEAuthCookie=PVE:$PROXMOX_USER:$TICKET" \
    "https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_NODE/storage/local/content?content=vztmpl" 2>/dev/null)

if echo "$FINAL_CHECK" | grep -q "ubuntu"; then
    echo "✅ Template successfully installed!"
    echo ""
    echo "📦 Available templates:"
    echo "$FINAL_CHECK" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for template in data['data']:
        print(f'   - {template[\"volid\"]}')
        if 'ubuntu-22.04' in template['volid']:
            print(f'     ✅ This one will be used for deployment')
except:
    print('   Could not parse template list')
"
    
    echo ""
    echo "🎉 Setup complete! You can now deploy your application:"
    echo "   ./deploy.sh"
    echo ""
    echo "💡 Or run a quick check first:"
    echo "   ./check-proxmox.sh"
    
else
    echo "⚠️  Template installation could not be verified"
    echo "   Please check the Proxmox web interface to confirm"
    echo "   https://$PROXMOX_HOST:8006 → $PROXMOX_NODE → local → CT Templates"
fi
