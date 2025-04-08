#!/bin/bash

PGPASSWORD=9879
export PGPASSWORD=$PGPASSWORD

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
apt-get -y install postgresql

echo
echo "Проверка запущен ли Docker"
systemctl status docker

echo
echo "Подтягиваем образ postgres"
docker pull postgres:17.4
docker image ls
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
echo "Запуск и настройка firewalld для приёма внешних соединений"
systemctl start firewalld
systemctl status firewalld
firewall-cmd --permanent --add-port=5432/tcp
firewall-cmd --reload

echo
echo "Настройка базы данных для внешних подключений"
docker exec postgres_container bash -c 'echo "host all all 0.0.0.0/0 scram-sha-256" >> /var/lib/postgresql/data/pg_hba.conf'
docker restart postgres_container

echo
echo "Проверка работы PostgreSQL"
docker exec postgres_container psql -d postgres -U postgres -c 'select 1'
