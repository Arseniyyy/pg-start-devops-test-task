#!/bin/bash
readonly SSH_PRIVATE_KEY="~/.ssh/id_rsa"
readonly USER="root"
readonly ALMA_LINUX_DISTRO_NAME="AlmaLinux"
readonly DEBIAN_DISTRO_NAME="Debian"

echo_stamp() {
  # TEMPLATE: echo_stamp <TEXT> <TYPE>
  # TYPE: SUCCESS, ERROR, INFO

  TEXT="$(date '+[%Y-%m-%d %H:%M:%S]') $1"
  TEXT="\e[1m$TEXT\e[0m" # BOLD

  case "$2" in
    SUCCESS)
    TEXT="\e[32m${TEXT}\e[0m";; # GREEN
    ERROR)
    TEXT="\e[31m${TEXT}\e[0m";; # RED
    *)
    TEXT="\e[34m${TEXT}\e[0m";; # BLUE
  esac
  echo -e ${TEXT}
}

export PGPASSWORD=$(cat ./pgpassword)

if [ -z "$1" ]; then
    echo_stamp "Сервера не указаны" "ERROR"
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

    echo_stamp "Операционная система: $distro_name"
    scp -i "$SSH_PRIVATE_KEY" install_postgres_almalinux.sh pgpassword "$USER@$server_ip":/tmp/
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" \
        "chmod +x /tmp/install_postgres_almalinux.sh &&" \
        "/tmp/install_postgres_almalinux.sh"
}

install_to_debian() {
    local server_ip=$1
    local distro_name=$2

    echo_stamp "Операционная система: $distro_name"
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
    echo_stamp "Установка psql на AlmaLinux: $server_ip"
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" \
        "dnf --refresh -y update &&" \
        "dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm &&" \
        "dnf install -y postgresql17"
}

install_psql_debian() {
    local server_ip=$1
    echo_stamp "Установка psql на Debian: '$server_ip'"
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$server_ip" \
        "apt-get -y update &&" \
        "apt-get -y install postgresql"
}

connect_to_postgres_only_from_secondary_ip() {
    local primary_ip=$1
    local secondary_ip=$2
    ssh -i "$SSH_PRIVATE_KEY" "$USER@$secondary_ip" \
        "export PGPASSWORD='$PGPASSWORD' &&" \
        "psql -U student -h '$primary_ip' -p 5432 -d postgres -c '\conninfo'"
}

IFS="," read -ra servers <<< "$1"

declare -A server_loads
for server_ip in "${servers[@]}"; do
    if ! [[ $server_ip =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$ ]]; then
        echo_stamp "$server — неверный IP-адрес" "ERROR"
        exit 1
    fi
    if [ $(check_distro_name "$server_ip") == "$ALMA_LINUX_DISTRO_NAME" ]; then
        install_psql_almalinux "$server_ip"
    elif [ $(check_distro_name "$server_ip") == "$DEBIAN_DISTRO_NAME" ]; then
        install_psql_debian "$server_ip"
    else
        echo_stamp "Дистрибутив не AlmaLinux или Debian" "ERROR"
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
    echo_stamp "$server_ip: ${server_loads[$server_ip]}"
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
        echo_stamp "secondary_ip не найден" "ERROR"
        exit 1
    fi

    echo_stamp "Менее загруженный сервер: $primary_ip"
    echo_stamp "Более загруженный сервер: $secondary_ip"
    message="Подключение к базе данных под пользователем student только со вторичного сервера $secondary_ip"

    if [[ "$distro_name" == "$ALMA_LINUX_DISTRO_NAME" ]]; then
        install_to_almalinux "$primary_ip" "$distro_name"
        configure_connection_to_user_student "$primary_ip" "$secondary_ip"
        echo_stamp "$message"
        connect_to_postgres_only_from_secondary_ip "$primary_ip" "$secondary_ip"
    elif [[ "$distro_name" == "$DEBIAN_DISTRO_NAME" ]]; then
        install_to_debian "$primary_ip" "$distro_name"
        configure_connection_to_user_student "$primary_ip" "$secondary_ip"
        echo_stamp "$message"
        connect_to_postgres_only_from_secondary_ip "$primary_ip" "$secondary_ip"
    else
        echo_stamp "Имя дистрибутива не подходит" "ERROR"
        exit 1
    fi
else
    echo_stamp "Не найдено ни одного сервера с валидной оценкой" "ERROR"
    exit 1
fi

echo
echo_stamp "Проверка подключения к базе данных ($primary_ip) с локального хоста"
psql -U postgres -d postgres -h "$primary_ip" -p 5432 -c "SELECT 1"
psql -U postgres -d postgres -h "$primary_ip" -p 5432 -c "\du"
psql -U postgres -d postgres -h "$primary_ip" -p 5432 -c "\conninfo"

echo
echo_stamp "Проверим, подключается ли пользователь к базе данных ($primary_ip) student с другого хоста (команда должна вывести ошибку)"
psql -U student -d postgres -h "$primary_ip" -p 5432 -c 'SELECT 1'
