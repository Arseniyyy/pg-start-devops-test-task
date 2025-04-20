#!/bin/bash
PGPASSWORD=$(cat /tmp/pgpassword)
echo "PG password: $PGPASSWORD"

echo
echo "Обновление и установка пакетов"
apt-get -y remove firewalld
apt-get -y update
apt-get -y install ca-certificates curl firewalld

echo
echo "Установка Docker"
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
echo "Установка psql"
apt-get -y install postgresql

echo
echo "Проверка запущен ли Docker"
systemctl status docker

echo
echo "Подтягиваем образ postgres"
docker pull postgres:17.4
docker image ls

echo
echo "Создание volume для хранения данных"
docker volume create postgres_data

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

sleep 3

echo
echo "Настройка пользователя student"
docker exec postgres_container psql -U postgres -c "
    CREATE USER student WITH PASSWORD '$PGPASSWORD';
    ALTER USER student CREATEDB;
    GRANT CONNECT ON DATABASE postgres TO student;
    GRANT CREATE ON SCHEMA public TO student;
    GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO student;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT INSERT, UPDATE, DELETE ON TABLES TO student;"

echo
echo "Запуск и настройка firewalld для приёма внешних соединений"
systemctl start firewalld
systemctl status firewalld
firewall-cmd --permanent --add-port=5432/tcp
firewall-cmd --reload

echo
echo "Проверка работы PostgreSQL"
docker exec postgres_container psql -d postgres -U postgres -c 'select 1'
