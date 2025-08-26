#!/bin/bash

# Load the global config
source ~/.pxdcli/env.global

echo "=== Debug Proxmox API Connection ==="
echo "PROXMOX_HOST: ${PROXMOX_HOST}"
echo "TOKEN_ID: ${TOKEN_ID}"
echo "TOKEN_SECRET: ${TOKEN_SECRET:0:10}..." # Only show first 10 chars for security

echo ""
echo "=== Testing API Connection ==="

# Test basic connectivity
echo "1. Testing basic connectivity to Proxmox host..."
if ping -c 1 "${PROXMOX_HOST}" >/dev/null 2>&1; then
    echo "✅ Host ${PROXMOX_HOST} is reachable"
else
    echo "❌ Host ${PROXMOX_HOST} is NOT reachable"
    exit 1
fi

echo ""
echo "2. Testing HTTPS connection to Proxmox API..."
response=$(curl -ks -w "%{http_code}" -o /dev/null "https://${PROXMOX_HOST}:8006/api2/json/version" 2>/dev/null)
if [[ "$response" == "200" ]]; then
    echo "✅ HTTPS connection successful (HTTP $response)"
else
    echo "❌ HTTPS connection failed (HTTP $response)"
    exit 1
fi

echo ""
echo "3. Testing API authentication..."
response=$(curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
    "https://${PROXMOX_HOST}:8006/api2/json/nodes" 2>/dev/null)

if [[ $? -eq 0 ]]; then
    echo "✅ API call successful"
    echo ""
    echo "4. Parsing nodes..."
    
    if command -v jq >/dev/null 2>&1; then
        echo "Using jq to parse response:"
        nodes=$(echo "$response" | jq -r '.data[] | "\(.node)"' 2>/dev/null)
        if [[ -n "$nodes" ]]; then
            echo "✅ Found nodes:"
            echo "$nodes" | while read -r node; do
                echo "  - $node"
            done
        else
            echo "❌ No nodes found in response"
            echo "Raw response:"
            echo "$response" | jq . 2>/dev/null || echo "$response"
        fi
    else
        echo "jq not available, using grep fallback:"
        nodes=$(echo "$response" | grep -o '"node":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$nodes" ]]; then
            echo "✅ Found nodes:"
            echo "$nodes" | while read -r node; do
                echo "  - $node"
            done
        else
            echo "❌ No nodes found in response"
            echo "Raw response:"
            echo "$response"
        fi
    fi
else
    echo "❌ API call failed"
    exit 1
fi
