#!/bin/bash
SERVER_IP=$1
SSH_PRIVATE_KEY="~/.ssh/id_rsa"
USER="root"
if [[ -n "$SERVER_IP" ]]; then
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" \
        "docker stop postgres_container &&" \
        "docker rm postgres_container &&" \
        "docker volume rm postgres_data"
else
    echo "Сервер не предоставлен."
    exit 1
fi
