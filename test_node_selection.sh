#!/bin/bash

# Load the global config
source ~/.pxdcli/env.global

# Copy the exact functions from generate-multi-service.sh
fetch_proxmox_nodes() {
    if [[ -z "${PROXMOX_HOST:-}" ]]; then
        echo "PROXMOX_HOST not set" >&2
        exit 1
    fi

    if [[ -z "${TOKEN_ID:-}" || -z "${TOKEN_SECRET:-}" ]]; then
        echo "TOKEN_ID and TOKEN_SECRET not set" >&2
        exit 1
    fi

    echo "Fetching nodes..." >&2

    local response
    response=$(curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
        "https://${PROXMOX_HOST}:8006/api2/json/nodes" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        echo "Failed to connect to Proxmox API" >&2
        exit 1
    fi

    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.data[] | "\(.node)"' 2>/dev/null || echo ""
    else
        # Fallback parsing without jq
        echo "$response" | grep -o '"node":"[^"]*"' | cut -d'"' -f4 || echo ""
    fi
}

select_proxmox_node() {
    local nodes
    nodes=$(fetch_proxmox_nodes)

    echo "DEBUG: nodes result: '$nodes'" >&2
    echo "DEBUG: nodes length: ${#nodes}" >&2

    if [[ -z "$nodes" ]]; then
        echo "No Proxmox nodes found or unable to connect" >&2
        exit 1
    fi

    # Convert to array
    local node_array=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            node_array+=("$line")
        fi
    done <<< "$nodes"

    echo "DEBUG: node_array length: ${#node_array[@]}" >&2
    echo "DEBUG: node_array contents: ${node_array[*]}" >&2

    if [[ ${#node_array[@]} -eq 1 ]]; then
        echo "Using single available node: ${node_array[0]}" >&2
        echo "${node_array[0]}"
        return 0
    fi

    echo ""
    echo "Available Proxmox nodes:"
    for i in "${!node_array[@]}"; do
        echo "  $((i+1)). ${node_array[$i]}"
    done
    echo ""

    local choice
    while true; do
        read -p "Select node (1-${#node_array[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#node_array[@]} ]]; then
            echo "${node_array[$((choice-1))]}"
            return 0
        else
            echo "Invalid choice. Please select a number between 1 and ${#node_array[@]}."
        fi
    done
}

echo "=== Testing Node Selection ==="
selected_node=$(select_proxmox_node)
echo "Selected node: $selected_node"
