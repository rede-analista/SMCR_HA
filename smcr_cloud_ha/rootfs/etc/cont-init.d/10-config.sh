#!/usr/bin/with-contenv bash
set -e

PORT=$(jq -r '.port // 8765' /data/options.json)
DB_PASS=$(jq -r '.db_password // "smcr_secret_2024"' /data/options.json)

# Configura porta do Apache
sed -i "s/__PORT__/${PORT}/g" /etc/apache2/sites-available/smcr.conf
sed -i "s/__PORT__/${PORT}/g" /etc/apache2/ports.conf

# Gera db.php com as credenciais
cat > /var/www/html/config/db.php <<EOF
<?php
define('DB_HOST', 'localhost');
define('DB_NAME', 'smcr_cloud');
define('DB_USER', 'smcr');
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

# Garante diretório de sessões PHP
mkdir -p /data/php_sessions
chown www-data:www-data /data/php_sessions

echo "[SMCR] Configuração concluída (porta ${PORT})"
