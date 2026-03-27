<?php
/**
 * Cron: marca dispositivos como offline se não enviaram heartbeat há mais de 5 minutos.
 * Executado pelo supervisord a cada 60 segundos.
 */
require_once __DIR__ . '/../config/db.php';

try {
    $db = getDB();
    $affected = $db->exec(
        "UPDATE devices SET online = 0
         WHERE online = 1
           AND (last_seen < DATE_SUB(NOW(), INTERVAL 5 MINUTE) OR last_seen IS NULL)"
    );
    if ($affected > 0) {
        echo "[SMCR cron] Marcados offline: {$affected} dispositivo(s)\n";
    }
} catch (Exception $e) {
    echo "[SMCR cron] Erro: " . $e->getMessage() . "\n";
}
