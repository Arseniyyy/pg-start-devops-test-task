#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: servers are not specified"
    exit 1
fi

SERVER_IP=$1
SSH_PRIVATE_KEY="~/.ssh/id_rsa"
USER="root"
PGPASSWORD=9879

scp -i "$SSH_PRIVATE_KEY" install_postgres_almalinux.sh "$USER@$SERVER_IP":/tmp/
ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" \
    "chmod +x /tmp/install_postgres_almalinux.sh &&" \
    "/tmp/install_postgres_almalinux.sh"

echo
echo "Тестирование проверки соединения с другого ip адреса"
export PGPASSWORD=$PGPASSWORD
psql -h "$SERVER_IP" -p 5432 -d postgres -U postgres -c "\conninfo"
psql -h "$SERVER_IP" -p 5432 -d postgres -U postgres -c "select 1"

echo
echo "Response code from the last command: $?"

# IFS="," read -ra servers <<< "$1"

# echo "Servers:"
# for server in "${servers[@]}"; do
#     if ! [[ $server =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$ ]]; then
#         echo "Ошибка: $server — неверный IP-адрес"
#         exit 1
#     fi
#     echo "$server"
# done
