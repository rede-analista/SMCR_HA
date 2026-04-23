#!/bin/bash
set -e

# ── Lê configurações de /data/options.json ──────────────────────────────────
HTTP_PORT=$(jq -r '.http_port // 2082' /data/options.json)
HTTPS_PORT=$(jq -r '.https_port // 2083' /data/options.json)
DB_PASS=$(jq -r '.db_password // "smcr_secret_2024"' /data/options.json)
ADMIN_USER=$(jq -r '.admin_user // "admin"' /data/options.json)
ADMIN_PASSWORD=$(jq -r '.admin_password // "admin123"' /data/options.json)

DB_HOST="localhost"
DB_NAME="smcr_cloud"
DB_USER="smcr"
DATADIR="/data/mariadb"
RESET=$(jq -r '.reset_on_start // false' /data/options.json)

echo "[SMCR] Iniciando add-on SMCR Cloud (HTTP:${HTTP_PORT} HTTPS:${HTTPS_PORT})..."

# ── Reset solicitado via configuração do add-on ──────────────────────────────
if [ "${RESET}" = "true" ]; then
    echo "[SMCR] reset_on_start=true: removendo banco de dados para reinicialização..."
    rm -rf "${DATADIR}"
    echo "[SMCR] Banco removido. Defina reset_on_start=false na configuração do add-on."
fi

# ── Gera certificado autoassinado para HTTPS ─────────────────────────────────
mkdir -p /etc/apache2/ssl
if [ ! -f /etc/apache2/ssl/smcr.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/apache2/ssl/smcr.key \
        -out /etc/apache2/ssl/smcr.crt \
        -subj "/CN=smcr_cloud_ha" 2>/dev/null
fi

# ── Configura Apache com as portas HTTP e HTTPS ──────────────────────────────
sed -i "s/__HTTP_PORT__/${HTTP_PORT}/g" /etc/apache2/sites-available/smcr.conf
sed -i "s/__HTTPS_PORT__/${HTTPS_PORT}/g" /etc/apache2/sites-available/smcr.conf
sed -i "s/__HTTP_PORT__/${HTTP_PORT}/g" /etc/apache2/ports.conf
sed -i "s/__HTTPS_PORT__/${HTTPS_PORT}/g" /etc/apache2/ports.conf

# ── Gera db.php com as credenciais do container ──────────────────────────────
cat > /var/www/html/config/db.php <<EOF
<?php
define('DB_HOST', '${DB_HOST}');
define('DB_NAME', '${DB_NAME}');
define('DB_USER', '${DB_USER}');
define('DB_PASS', '${DB_PASS}');

function getDB(): PDO {
    static \$pdo = null;
    if (\$pdo === null) {
        \$pdo = new PDO(
            'mysql:unix_socket=/run/mysqld/mysqld.sock;dbname=' . DB_NAME . ';charset=utf8mb4',
            DB_USER,
            DB_PASS,
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]
        );
    }
    return \$pdo;
}
EOF

# ── Inicializa MariaDB (somente na primeira execução) ────────────────────────
if [ ! -d "${DATADIR}/mysql" ]; then
    echo "[SMCR] Primeiro boot: inicializando banco de dados..."
    mkdir -p "${DATADIR}"
    chown -R mysql:mysql "${DATADIR}"

    mysql_install_db --user=mysql --datadir="${DATADIR}" --skip-test-db > /dev/null 2>&1

    ADMIN_HASH=$(php -r "echo password_hash('${ADMIN_PASSWORD}', PASSWORD_BCRYPT);")

    # Cria arquivo de inicialização executado pelo mysqld antes de aceitar conexões
    cat > /tmp/smcr_init.sql <<INITEOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
INITEOF

    # Inicia MariaDB com --init-file (executa SQL com privilégios internos, sem auth)
    mysqld --init-file=/tmp/smcr_init.sql --user=mysql --datadir="${DATADIR}" \
        --socket=/run/mysqld/mysqld.sock --pid-file=/run/mysqld/mysqld.pid \
        --skip-networking 2>/dev/null &
    MYSQL_PID=$!

    # Aguarda MariaDB ficar disponível (usando a senha definida no init-file)
    for i in $(seq 1 30); do
        if mysql -u root -p"${DB_PASS}" --socket=/run/mysqld/mysqld.sock \
                -e "SELECT 1" 2>/dev/null; then
            break
        fi
        sleep 1
    done

    # Aplica schema e insere admin
    mysql -u root -p"${DB_PASS}" --socket=/run/mysqld/mysqld.sock "${DB_NAME}" \
        < /var/www/html/install/schema.sql

    mysql -u root -p"${DB_PASS}" --socket=/run/mysqld/mysqld.sock "${DB_NAME}" <<SQL
INSERT INTO users (username, password_hash) VALUES ('${ADMIN_USER}', '${ADMIN_HASH}')
ON DUPLICATE KEY UPDATE password_hash = '${ADMIN_HASH}', username = '${ADMIN_USER}';
SQL

    rm -f /tmp/smcr_init.sql

    # Para o MariaDB temporário
    kill "${MYSQL_PID}"
    wait "${MYSQL_PID}" 2>/dev/null || true
    echo "[SMCR] Banco de dados inicializado com sucesso."
else
    echo "[SMCR] Banco de dados existente encontrado, pulando inicialização."

    # ── Aplica migrations pendentes no banco existente ───────────────────────
    echo "[SMCR] Aplicando migrations pendentes..."
    mysqld --user=mysql --datadir="${DATADIR}" \
        --socket=/run/mysqld/mysqld.sock --pid-file=/run/mysqld/mysqld.pid \
        --skip-networking 2>/dev/null &
    MYSQL_PID=$!

    for i in $(seq 1 30); do
        if mysql -u root -p"${DB_PASS}" --socket=/run/mysqld/mysqld.sock \
                -e "SELECT 1" 2>/dev/null; then
            break
        fi
        sleep 1
    done

    for MIGRATION in /var/www/html/install/migrate_*.sql; do
        echo "[SMCR] Aplicando migration: $(basename ${MIGRATION})..."
        mysql -u root -p"${DB_PASS}" --socket=/run/mysqld/mysqld.sock "${DB_NAME}" \
            < "${MIGRATION}" && echo "[SMCR] Migration OK: $(basename ${MIGRATION})" \
            || echo "[SMCR] AVISO: falha ao aplicar $(basename ${MIGRATION})"
    done

    kill "${MYSQL_PID}"
    wait "${MYSQL_PID}" 2>/dev/null || true
    echo "[SMCR] Migrations concluídas."
fi

# ── Ajusta permissões de sessão PHP ─────────────────────────────────────────
mkdir -p /data/php_sessions
chown www-data:www-data /data/php_sessions

# ── Inicia serviços via supervisord ─────────────────────────────────────────
echo "[SMCR] Iniciando serviços (MariaDB + Apache)..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
