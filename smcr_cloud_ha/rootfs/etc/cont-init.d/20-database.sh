#!/usr/bin/with-contenv bash
set -e

DB_PASS=$(jq -r '.db_password // "smcr_secret_2024"' /data/options.json)
ADMIN_USER=$(jq -r '.admin_user // "admin"' /data/options.json)
ADMIN_PASSWORD=$(jq -r '.admin_password // "admin123"' /data/options.json)
DB_NAME="smcr_cloud"
DB_USER="smcr"
DATADIR="/data/mariadb"

if [ -d "${DATADIR}/mysql" ]; then
    echo "[SMCR] Banco de dados existente encontrado, pulando inicialização."
    exit 0
fi

echo "[SMCR] Primeiro boot: inicializando banco de dados..."
mkdir -p "${DATADIR}"
chown -R mysql:mysql "${DATADIR}"

mysql_install_db --user=mysql --datadir="${DATADIR}" --skip-test-db > /dev/null 2>&1

# Inicia MariaDB temporariamente
mysqld_safe --datadir="${DATADIR}" --skip-networking &
MYSQL_PID=$!

for i in $(seq 1 30); do
    if mysqladmin ping --socket=/run/mysqld/mysqld.sock --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

mysql --socket=/run/mysqld/mysqld.sock <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
SQL

mysql --socket=/run/mysqld/mysqld.sock "${DB_NAME}" < /var/www/html/install/schema.sql

ADMIN_HASH=$(php -r "echo password_hash('${ADMIN_PASSWORD}', PASSWORD_BCRYPT);")
mysql --socket=/run/mysqld/mysqld.sock "${DB_NAME}" <<SQL
INSERT INTO users (username, password_hash) VALUES ('${ADMIN_USER}', '${ADMIN_HASH}')
ON DUPLICATE KEY UPDATE password_hash = '${ADMIN_HASH}', username = '${ADMIN_USER}';
SQL

kill "${MYSQL_PID}"
wait "${MYSQL_PID}" 2>/dev/null || true

echo "[SMCR] Banco de dados inicializado com sucesso."
