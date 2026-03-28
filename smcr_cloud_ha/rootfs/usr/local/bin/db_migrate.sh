#!/bin/bash
# Executa migrations de schema no banco existente.
# Rodado pelo supervisord uma única vez após o MariaDB subir.

DB_PASS=$(jq -r '.db_password // "smcr_secret_2024"' /data/options.json)
SOCKET=/run/mysqld/mysqld.sock

# Aguarda o MariaDB ficar disponível (máx 60s)
for i in $(seq 1 60); do
    if mysql -u root -p"${DB_PASS}" --socket="${SOCKET}" -e "SELECT 1" smcr_cloud >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

mysql -u root -p"${DB_PASS}" --socket="${SOCKET}" smcr_cloud <<SQL
ALTER TABLE device_status ADD COLUMN IF NOT EXISTS port SMALLINT UNSIGNED DEFAULT 8080;
ALTER TABLE device_config ADD COLUMN IF NOT EXISTS cloud_heartbeat_enabled TINYINT(1) DEFAULT 0;
ALTER TABLE device_config ADD COLUMN IF NOT EXISTS cloud_heartbeat_interval_min SMALLINT UNSIGNED DEFAULT 5;
SQL

echo "[SMCR] Migrations aplicadas."
