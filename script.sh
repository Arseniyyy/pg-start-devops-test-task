#!/bin/bash

SERVER_IP=$1
SSH_PRIVATE_KEY="~/.ssh/id_rsa"
USER="root"
PGPASSWORD=9879

export PGPASSWORD=$PGPASSWORD

if [ -z "$1" ]; then
    echo "Error: servers are not specified"
    exit 1
fi

check_load() {
    echo "Прверка загруженности сервера $SERVER_IP"
    load_last_5_min=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" "uptime | awk -F 'load average:' '{print \$2}' | cut -d, -f2 | xargs")
    free_mem=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" "free -m | awk '/Mem:/ {print \$4}'")
    free_disk=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" "df -h / | awk 'NR==2 {print \$4}'")

    echo "Текущая нагрузка:"
    echo "Загрузка CPU за последние 5 минут: $load_last_5_min"
    echo "Свободная память: $free_mem"
    echo "Свободное пространство на диске: $free_disk"
}

check_system_name() {
    distribution_name=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" "hostnamectl | awk '/Operating System:/ {print \$3}'")
    echo "$distribution_name"
}

distribution_name=$(check_system_name)
if [[ "$distribution_name" == "AlmaLinux" ]]; then
    echo "Операционная система: $distribution_name"
    scp -i "$SSH_PRIVATE_KEY" install_postgres_almalinux.sh "$USER@$SERVER_IP":/tmp/
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" \
        "chmod +x /tmp/install_postgres_almalinux.sh &&" \
        "/tmp/install_postgres_almalinux.sh"
elif [[ "$distribution_name" == "Debian" ]]; then
    echo "Операционная система: $distribution_name"
    scp -i "$SSH_PRIVATE_KEY" install_postgres_debian.sh "$USER@$SERVER_IP":/tmp/
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" \
        "chmod +x /tmp/install_postgres_debian.sh &&" \
        "/tmp/install_postgres_debian.sh"
else
    echo "Имя дистрибутива не подходит"
    exit 1
fi

echo
echo "Тестирование проверки соединения с другого ip адреса"
psql -h "$SERVER_IP" -p 5432 -d postgres -U postgres -c "\conninfo"
psql -h "$SERVER_IP" -p 5432 -d postgres -U postgres -c "select 1"

# server_load=$(check_load "$SERVER_IP")
# echo "$server_load"

# scp -i "$SSH_PRIVATE_KEY" install_postgres_almalinux.sh "$USER@$SERVER_IP":/tmp/
# ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" \
#     "chmod +x /tmp/install_postgres_almalinux.sh &&" \
#     "/tmp/install_postgres_almalinux.sh"

# IFS="," read -ra servers <<< "$1"

# echo "Servers:"
# for server in "${servers[@]}"; do
#     if ! [[ $server =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$ ]]; then
#         echo "Ошибка: $server — неверный IP-адрес"
#         exit 1
#     fi
#     echo "$server"
# done
