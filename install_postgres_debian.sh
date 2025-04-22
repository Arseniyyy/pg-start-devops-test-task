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
apt-get -y remove firewalld
apt-get -y update
apt-get -y install ca-certificates curl firewalld

echo
echo_stamp "Установка Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get -y update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo
echo_stamp "Установка psql"
apt-get -y install postgresql

echo
echo_stamp "Проверка запущен ли Docker"
systemctl status docker

echo
echo_stamp "Подтягиваем образ postgres"
docker pull postgres:17.4
docker image ls

echo
echo_stamp "Создание volume для хранения данных"
docker volume create postgres_data

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
echo_stamp "Запуск и настройка firewalld для приёма внешних соединений"
systemctl start firewalld
systemctl status firewalld
firewall-cmd --permanent --add-port=5432/tcp
firewall-cmd --reload

echo
echo_stamp "Проверка работы PostgreSQL"
docker exec postgres_container psql -d postgres -U postgres -c 'select 1'
