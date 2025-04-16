#!/bin/bash

SSH_PRIVATE_KEY="~/.ssh/id_rsa"
USER="root"
PGPASSWORD=9879

export PGPASSWORD=$PGPASSWORD

if [ -z "$1" ]; then
    echo "Сервера не указаны"
    exit 1
fi

check_system_name() {
    local server_ip=$1
    local distribution_name=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" "hostnamectl | awk '/Operating System:/ {print \$3}'")
    echo "$distribution_name"
}

check_load() {
    local server_ip=$1
    local cpu_cores=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" "nproc")
    local load_last_5_min=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" "uptime | awk -F 'load average:' '{print \$2}' | cut -d, -f2 | xargs")
    local normalized_load=$(echo "scale=2; $load_last_5_min / $cpu_cores" | bc -l)
    echo "$normalized_load"
}

check_memory() {
    local server_ip=$1
    local total_mem=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" "free -m | awk '/Mem:/ {print \$2}'")
    local used_mem=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" "free -m | awk '/Mem:/ {print \$3}'")
    local mem_utilized=$(echo "scale=1; ($used_mem / $total_mem) * 100" | bc -l)
    echo "$mem_utilized"
}

check_disk_space() {
    local server_ip=$1
    local total_disk=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" "df -m / | awk 'NR==2 {print \$2}'")
    local used_disk=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" "df -m / | awk 'NR==2 {print \$3}'")
    local disk_utilized=$(echo "scale=1; ($used_disk / $total_disk) * 100" | bc -l)
    echo "$disk_utilized"
}

calculate_score() {
    local normalized_load=$1
    local mem_utilized=$2
    local disk_utilized=$3

    # Суммарный score (чем меньше - тем лучше)
    echo "scale=1; ($normalized_load * 50) + ($mem_utilized * 30) + ($disk_utilized * 20)" | bc -l
}

IFS="," read -ra servers <<< "$1"

declare -A server_loads
for server_ip in "${servers[@]}"; do
    if ! [[ $server_ip =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$ ]]; then
        echo "Ошибка: $server — неверный IP-адрес"
        exit 1
    fi
    normalized_load="$(check_load "$server_ip")"
    mem_utilized="$(check_memory "$server_ip")"
    disk_utilized="$(check_disk_space "$server_ip")"
    load_score="$(calculate_score "$normalized_load" "$mem_utilized" "$disk_utilized")"
    server_loads+=(["$server_ip"]="$load_score")
done

less_loaded_server_string=$(
    for server_ip in "${!server_loads[@]}"; do
        load_score="${server_loads[$server_ip]}"
        if [[ -n "$load_score" ]] && (( $(echo "$load_score >= 0" | bc -l) )); then
            echo "$load_score $server_ip"
        fi
    done | sort -n | head -n 1
)

echo "$less_loaded_server_string"

# echo "${server_loads[@]}"

# distribution_name=$(check_system_name)
# if [[ "$distribution_name" == "AlmaLinux" ]]; then
#     echo "Операционная система: $distribution_name"
#     scp -i "$SSH_PRIVATE_KEY" install_postgres_almalinux.sh "$USER@$SERVER_IP":/tmp/
#     ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" \
#         "chmod +x /tmp/install_postgres_almalinux.sh &&" \
#         "/tmp/install_postgres_almalinux.sh"
# elif [[ "$distribution_name" == "Debian" ]]; then
#     echo "Операционная система: $distribution_name"
#     scp -i "$SSH_PRIVATE_KEY" install_postgres_debian.sh "$USER@$SERVER_IP":/tmp/
#     ssh -i "$SSH_PRIVATE_KEY" "$USER@$SERVER_IP" \
#         "chmod +x /tmp/install_postgres_debian.sh &&" \
#         "/tmp/install_postgres_debian.sh"
# else
#     echo "Имя дистрибутива не подходит"
#     exit 1
# fi
