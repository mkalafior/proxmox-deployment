#!/bin/bash
SSH_KEY_PATH="/Users/sebastian/.ssh/id_proxmox"
VM_IP="192.168.1.193"

if ! ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=5 -o BatchMode=yes root@${VM_IP} "echo 'OK'" &>
/dev/null; then
    echo "FAILED"
    exit 1
else
    echo "SUCCESS"
fi
