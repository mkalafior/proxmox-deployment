#!/bin/bash

config_file="../deployments/service02/service-config.yml"

echo "=== Debugging YAML parsing ==="
echo "Config file: $config_file"
echo "Content:"
cat "$config_file"
echo ""
echo "=== Parsing with current logic ==="

while IFS= read -r line; do
    echo "Processing line: '$line'"
    
    # Skip comments and empty lines
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
        echo "  -> Skipping comment"
        continue
    fi
    if [[ -z "$line" ]]; then
        echo "  -> Skipping empty line"
        continue
    fi
    
    # Parse key: value pairs
    if [[ "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        
        echo "  -> Raw key: '$key', Raw value: '$value'"
        
        # Clean up key and value
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
        
        echo "  -> Clean key: '$key', Clean value: '$value'"
        
        # Export as environment variable
        if [[ -n "$key" && -n "$value" ]]; then
            export "$key"="$value"
            echo "  -> Exported: $key=$value"
        fi
    else
        echo "  -> No match for key:value pattern"
    fi
done < "$config_file"

echo ""
echo "=== Final environment variables ==="
env | grep -E "(proxmox_node|service_name|vm_id)" | sort
