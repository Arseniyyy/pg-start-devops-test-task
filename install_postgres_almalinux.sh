#!/bin/bash

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

PGPASSWORD=$(cat /tmp/pgpassword)
echo_stamp "PGPASSWORD: $PGPASSWORD"

echo
echo_stamp "Обновление и установка пакетов"
dnf remove -y firewalld
dnf --refresh -y update
dnf install -y yum-utils firewalld
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

echo
echo_stamp "Установка Docker"
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl start docker
systemctl enable docker

echo
echo_stamp "Проверка работы Docker"
systemctl status docker
docker pull postgres:17.4
docker image ls

echo
echo_stamp "Создание volume для хранения данных"
docker volume create postgres_data

echo
echo_stamp "Установка postgres версии 17"
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf install -y postgresql17

echo
echo_stamp "Запуск контейнера"
docker run --name postgres_container \
  -e POSTGRES_PASSWORD=$PGPASSWORD \
  -e POSTGRES_USER=postgres \
  -d -p 0.0.0.0:5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  postgres:17.4 \
  -c listen_addresses='*' \
  -c shared_preload_libraries='pg_stat_statements'

sleep 3

echo
echo_stamp "Настройка пользователя student"
docker exec postgres_container psql -U postgres -c "
    CREATE USER student WITH PASSWORD '$PGPASSWORD';
    ALTER USER student CREATEDB;
    GRANT CONNECT ON DATABASE postgres TO student;
    GRANT CREATE ON SCHEMA public TO student;
    GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO student;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT INSERT, UPDATE, DELETE ON TABLES TO student;"

echo
echo_stamp "Настройка сервера для внешних подключений"
systemctl start firewalld
systemctl status firewalld
firewall-cmd --permanent --add-port=5432/tcp
firewall-cmd --reload

echo
echo_stamp "Проверка работы PostgreSQL"
docker exec postgres_container psql -d postgres -U postgres -c 'select 1'
