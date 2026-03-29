<?php
/**
 * Cron: marca dispositivos como offline se não enviaram heartbeat há mais de 5 minutos.
 * Executado pelo supervisord a cada 60 segundos.
 */
require_once __DIR__ . '/../config/db.php';

try {
    $db = getDB();
    $affected = $db->exec(
        "UPDATE devices d
         LEFT JOIN device_config dc ON dc.device_id = d.id
         SET d.online = 0
         WHERE d.online = 1
           AND (d.last_seen IS NULL
             OR d.last_seen < DATE_SUB(NOW(), INTERVAL
                 IF(dc.cloud_heartbeat_enabled = 1 AND dc.cloud_heartbeat_interval_min > 0,
                    dc.cloud_heartbeat_interval_min + 1,
                    5)
             MINUTE))"
    );
    if ($affected > 0) {
        echo "[SMCR cron] Marcados offline: {$affected} dispositivo(s)\n";
    }
} catch (Exception $e) {
    echo "[SMCR cron] Erro: " . $e->getMessage() . "\n";
}
