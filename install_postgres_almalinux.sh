#!/bin/bash

PGPASSWORD=9879

function check_status() {
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NO_COLOR='\033[0m'
    if [ $? -eq 0 ]; then
        printf "${GREEN}SUCCESS${NO_COLOR}\n"
        return 0
    else
        printf "${RED}ERROR${NO_COLOR}\n"
        exit 1
    fi
}

echo
echo "Обновление и установка пакетов"
dnf --refresh -y update
dnf install -y yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
check_status

echo
echo "Установка Docker"
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl start docker
systemctl enable docker
check_status

echo
echo "Проверка работы Docker"
systemctl status docker
docker pull postgres:17.4
docker image ls
check_status

echo
echo "Создание volume для хранения данных"
docker volume create postgres_data
check_status

echo
echo "Установка postgres версии 17"
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf install -y postgresql17
check_status

echo
echo "Запуск контейнера"
docker run --name postgres_container \
  -e POSTGRES_PASSWORD=$PGPASSWORD \
  -e POSTGRES_USER=postgres \
  -d -p 0.0.0.0:5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  postgres:17.4 \
  -c listen_addresses='*' \
  -c shared_preload_libraries='pg_stat_statements'
check_status

sleep 2

echo
echo "Настройка базы данных для внешних подключений"
docker exec postgres_container bash -c 'echo "host all all 0.0.0.0/0 scram-sha-256" >> /var/lib/postgresql/data/pg_hba.conf'
docker restart postgres_container
check_status

echo
echo "Настройка сервера для внешних подключений"
systemctl start firewalld
systemctl status firewalld
firewall-cmd --permanent --add-port=5432/tcp
firewall-cmd --reload
check_status

echo
echo "Проверка работы PostgreSQL"
docker exec postgres_container psql -d postgres -U postgres -c 'select 1'
check_status
