#!/bin/bash
set -e

# ── Lê configurações de /data/options.json ──────────────────────────────────
PORT=$(jq -r '.port // 8765' /data/options.json)
DB_PASS=$(jq -r '.db_password // "smcr_secret_2024"' /data/options.json)
ADMIN_USER=$(jq -r '.admin_user // "admin"' /data/options.json)
ADMIN_PASSWORD=$(jq -r '.admin_password // "admin123"' /data/options.json)

DB_HOST="localhost"
DB_NAME="smcr_cloud"
DB_USER="smcr"
DATADIR="/data/mariadb"

echo "[SMCR] Iniciando add-on SMCR Cloud na porta ${PORT}..."

# ── Configura Apache com a porta escolhida ───────────────────────────────────
sed -i "s/__PORT__/${PORT}/g" /etc/apache2/sites-available/smcr.conf
sed -i "s/__PORT__/${PORT}/g" /etc/apache2/ports.conf

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
            'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
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

    # Inicia MariaDB temporariamente sem autenticação para configuração inicial
    mysqld_safe --datadir="${DATADIR}" --skip-networking --skip-grant-tables &
    MYSQL_PID=$!

    # Aguarda MariaDB ficar disponível
    for i in $(seq 1 30); do
        if mysqladmin -u root ping --socket=/run/mysqld/mysqld.sock --silent 2>/dev/null; then
            break
        fi
        sleep 1
    done

    # Cria banco, usuário e aplica schema
    mysql -u root --socket=/run/mysqld/mysqld.sock <<SQL
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
SQL

    mysql -u root --socket=/run/mysqld/mysqld.sock "${DB_NAME}" < /var/www/html/install/schema.sql

    # Atualiza senha do admin conforme configuração
    ADMIN_HASH=$(php -r "echo password_hash('${ADMIN_PASSWORD}', PASSWORD_BCRYPT);")
    mysql -u root --socket=/run/mysqld/mysqld.sock "${DB_NAME}" <<SQL
INSERT INTO users (username, password_hash) VALUES ('${ADMIN_USER}', '${ADMIN_HASH}')
ON DUPLICATE KEY UPDATE password_hash = '${ADMIN_HASH}', username = '${ADMIN_USER}';
SQL

    # Para o MariaDB temporário
    kill "${MYSQL_PID}"
    wait "${MYSQL_PID}" 2>/dev/null || true
    echo "[SMCR] Banco de dados inicializado com sucesso."
else
    echo "[SMCR] Banco de dados existente encontrado, pulando inicialização."
fi

# ── Ajusta permissões de sessão PHP ─────────────────────────────────────────
mkdir -p /data/php_sessions
chown www-data:www-data /data/php_sessions

# ── Inicia serviços via supervisord ─────────────────────────────────────────
echo "[SMCR] Iniciando serviços (MariaDB + Apache)..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
