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
ALTER TABLE devices ADD COLUMN IF NOT EXISTS ativo TINYINT(1) NOT NULL DEFAULT 1 COMMENT 'Quando 0, não recebe sync e não é monitorado';
ALTER TABLE device_config ADD COLUMN IF NOT EXISTS cloud_use_https TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE device_config ADD COLUMN IF NOT EXISTS cloud_api_token VARCHAR(128) DEFAULT '';
ALTER TABLE device_config ADD COLUMN IF NOT EXISTS cloud_register_token VARCHAR(128) DEFAULT '';
ALTER TABLE device_actions ADD COLUMN IF NOT EXISTS hora_agendada TINYINT UNSIGNED DEFAULT 255;
ALTER TABLE device_actions ADD COLUMN IF NOT EXISTS minuto_agendado TINYINT UNSIGNED DEFAULT 0;
ALTER TABLE device_actions ADD COLUMN IF NOT EXISTS duracao_agendada_s SMALLINT UNSIGNED DEFAULT 0;
ALTER TABLE device_status ADD COLUMN IF NOT EXISTS sketch_size INT UNSIGNED DEFAULT 0;
ALTER TABLE device_status ADD COLUMN IF NOT EXISTS sketch_free INT UNSIGNED DEFAULT 0;
CREATE TABLE IF NOT EXISTS device_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    device_id INT NOT NULL,
    event ENUM('online', 'offline') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_device_events (device_id, created_at),
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS device_action_events (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    device_id INT UNSIGNED NOT NULL,
    gpio_origem SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    gpio_destino SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    tipo TINYINT UNSIGNED NOT NULL DEFAULT 0,
    ocorrido_em DATETIME NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_event (device_id, gpio_origem, gpio_destino, tipo, ocorrido_em),
    KEY idx_device_time (device_id, ocorrido_em)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL

echo "[SMCR] Migrations aplicadas."
