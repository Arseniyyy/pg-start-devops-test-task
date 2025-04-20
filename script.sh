#!/bin/bash
SSH_PRIVATE_KEY="~/.ssh/id_rsa"
USER="root"
PGPASSWORD=$(cat ./pgpassword)
ALMA_LINUX_DISTRO_NAME="AlmaLinux"
DEBIAN_DISTRO_NAME="Debian"

echo "Пароль postgres: $PGPASSWORD"
export PGPASSWORD=$PGPASSWORD

if [ -z "$1" ]; then
    echo "Сервера не указаны"
    exit 1
fi

check_distro_name() {
    local server_ip=$1
    local distro_name=$(ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" "hostnamectl | awk '/Operating System:/ {print \$3}'")
    echo "$distro_name"
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

install_to_almalinux() {
    local server_ip=$1
    local distro_name=$2

    echo "Операционная система: $distro_name"
    scp -i "$SSH_PRIVATE_KEY" install_postgres_almalinux.sh pgpassword "$USER@$server_ip":/tmp/
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" \
        "chmod +x /tmp/install_postgres_almalinux.sh &&" \
        "/tmp/install_postgres_almalinux.sh"
}

install_to_debian() {
    local server_ip=$1
    local distro_name=$2

    echo "Операционная система: $distro_name"
    scp -i "$SSH_PRIVATE_KEY" install_postgres_debian.sh pgpassword "$USER@$server_ip":/tmp/
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" \
        "chmod +x /tmp/install_postgres_debian.sh &&" \
        "/tmp/install_postgres_debian.sh"
}

configure_connection_to_user_student() {
    local primary_ip=$1
    local secondary_ip=$2
    local pg_hba_path="/var/lib/postgresql/data/pg_hba.conf"
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$primary_ip" \
        "docker exec postgres_container sed -i '$ d' '$pg_hba_path' &&" \
        "docker exec postgres_container bash -c" \
        "'echo \"host all student "$secondary_ip"/32 scram-sha-256\" >> "$pg_hba_path" &&
          echo \"host all postgres 0.0.0.0/0 scram-sha-256\" >> "$pg_hba_path"' &&" \
        "docker exec -u postgres postgres_container psql -U postgres -c 'SELECT pg_reload_conf()'"
}

install_psql_almalinux() {
    local server_ip=$1
    echo "Установка psql на AlmaLinux: '$server_ip'"
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" \
        "dnf --refresh -y update &&" \
        "dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm &&" \
        "dnf install -y postgresql17"
}

install_psql_debian() {
    local server_ip=$1
    echo "Установка psql на Debian: '$server_ip'"
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" \
        "apt-get -y update &&" \
        "apt-get -y install postgresql"
}

IFS="," read -ra servers <<< "$1"

declare -A server_loads
for server_ip in "${servers[@]}"; do
    if ! [[ $server_ip =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$ ]]; then
        echo "Ошибка: $server — неверный IP-адрес"
        exit 1
    fi
    if [ $(check_distro_name "$server_ip") == "$ALMA_LINUX_DISTRO_NAME" ]; then
        install_psql_almalinux "$server_ip"
    elif [ $(check_distro_name "$server_ip") == "$DEBIAN_DISTRO_NAME" ]; then
        install_psql_debian "$server_ip"
    else
        echo "Дистрибутив не AlmaLinux или Debian"
        exit 1
    fi
    normalized_load="$(check_load "$server_ip")"
    mem_utilized="$(check_memory "$server_ip")"
    disk_utilized="$(check_disk_space "$server_ip")"
    load_score="$(calculate_score "$normalized_load" "$mem_utilized" "$disk_utilized")"
    server_loads+=(["$server_ip"]="$load_score")
done

less_loaded_server_line=$(
    for server_ip in "${!server_loads[@]}"; do
        load_score="${server_loads[$server_ip]}"
        if [[ -n "$load_score" ]] && (( $(echo "$load_score >= 0" | bc -l) )); then
            echo "$load_score $server_ip"
        fi
    done | sort -n | head -n 1
)

for server_ip in "${!server_loads[@]}"; do
    echo "$server_ip: ${server_loads[$server_ip]}"
done

if [ -n "$less_loaded_server_line" ]; then
    read -r min_score primary_ip <<< "$less_loaded_server_line"
    distro_name=$(check_distro_name "$primary_ip")
    secondary_ip=""
    secondary_ip_found=false
    for ip in "${servers[@]}"; do
        if  [[ "$ip" != "$primary_ip" ]]; then
            secondary_ip="$ip"
            secondary_ip_found=true
            break
        fi
    done
    if [ "$secondary_ip_found" = false ]; then
        echo "secondary_ip не найден"
        exit 1
    fi

    echo "Менее загруженный сервер: $primary_ip"
    echo "Более загруженный сервер: $secondary_ip"

    if [[ "$distro_name" == "$ALMA_LINUX_DISTRO_NAME" ]]; then
        install_to_almalinux "$primary_ip" "$distro_name"
        configure_connection_to_user_student "$primary_ip" "$secondary_ip"
        echo "Подключение к базе данных под пользователем student только с сервера $secondary_ip"
        ssh -i "$SSH_PRIVATE_KEY" "$USER@$secondary_ip" \
            "export PGPASSWORD='$PGPASSWORD' &&" \
            "psql -U student -h '$primary_ip' -p 5432 -d postgres -c '\conninfo'"
    elif [[ "$distro_name" == "$DEBIAN_DISTRO_NAME" ]]; then
        install_to_debian "$primary_ip" "$distro_name"
        configure_connection_to_user_student "$primary_ip" "$secondary_ip"
        echo "Подключение к базе данных под пользователем student только с сервера $secondary_ip"
        ssh -i "$SSH_PRIVATE_KEY" "$USER@$secondary_ip" \
            "export PGPASSWORD='$PGPASSWORD' &&" \
            "psql -U student -h '$primary_ip' -p 5432 -d postgres -c '\conninfo'"
    else
        echo "Имя дистрибутива не подходит"
        exit 1
    fi
else
    echo "Не найдено ни одного сервера с валидной оценкой."
    exit 1
fi

echo
echo "Проверка подключения к базе данных с локального хоста"
psql -U postgres -d postgres -h "$primary_ip" -p 5432 -c "\conninfo"

echo
echo "Проверим, подключается ли пользователь student с другого хоста (команда должна вывести ошибку)"
psql -U student -d postgres -h "$primary_ip" -p 5432 -c '\conninfo'
