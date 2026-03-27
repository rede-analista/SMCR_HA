<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/../config/auth.php';
session_init();

if (!is_logged_in()) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'Unauthorized']);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'Method not allowed']);
    exit;
}

/**
 * Executa script Python com zeroconf para descobrir dispositivos SMCR via mDNS.
 * Não requer avahi-daemon — usa multicast UDP direto.
 */
function discover_via_mdns(): array {
    $script = __DIR__ . '/mdns_discover.py';
    $output = shell_exec('python3 ' . escapeshellarg($script) . ' 2>/dev/null');
    if ($output === null || $output === '') {
        return [];
    }

    $data = json_decode($output, true);
    if (!is_array($data)) {
        return [];
    }

    // Se o script retornou um objeto de erro
    if (isset($data['error'])) {
        return [];
    }

    $devices = [];
    foreach ($data as $dev) {
        if (empty($dev['ip']) || !filter_var($dev['ip'], FILTER_VALIDATE_IP)) continue;
        $devices[] = [
            'hostname'  => $dev['hostname'] ?? '',
            'ip'        => $dev['ip'],
            'port'      => (int)($dev['port'] ?? 80),
            'version'   => $dev['version'] ?? '',
            'unique_id' => '',
        ];
    }

    return $devices;
}

/**
 * Busca o unique_id de cada dispositivo via HTTP /api/mqtt/status
 */
function enrich_with_unique_ids(array $devices): array {
    if (empty($devices)) return $devices;

    $mh      = curl_multi_init();
    $handles = [];

    foreach ($devices as $i => $dev) {
        $url = "http://{$dev['ip']}:{$dev['port']}/api/mqtt/status";
        $ch  = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 3,
            CURLOPT_CONNECTTIMEOUT => 2,
            CURLOPT_FOLLOWLOCATION => false,
        ]);
        curl_multi_add_handle($mh, $ch);
        $handles[$i] = $ch;
    }

    $running = null;
    do {
        curl_multi_exec($mh, $running);
        curl_multi_select($mh, 0.1);
    } while ($running > 0);

    foreach ($handles as $i => $ch) {
        $body = curl_multi_getcontent($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_multi_remove_handle($mh, $ch);
        curl_close($ch);

        if ($code === 200 && $body) {
            $json = json_decode($body, true);
            if (is_array($json) && !empty($json['mqtt_unique_id'])) {
                $devices[$i]['unique_id'] = $json['mqtt_unique_id'];
            }
        }

        // Fallback: usa hostname como unique_id se não conseguiu via API
        if ($devices[$i]['unique_id'] === '') {
            $devices[$i]['unique_id'] = $devices[$i]['hostname'];
        }
    }

    curl_multi_close($mh);
    return $devices;
}

// --- Main ---
try {
    $found = discover_via_mdns();
    $found = enrich_with_unique_ids($found);

    // Verifica quais já estão cadastrados
    $db = getDB();
    $registered = [];
    if (!empty($found)) {
        $ids   = array_column($found, 'unique_id');
        $ids   = array_filter($ids);
        if (!empty($ids)) {
            $place = implode(',', array_fill(0, count($ids), '?'));
            $stmt  = $db->prepare("SELECT unique_id FROM devices WHERE unique_id IN ($place)");
            $stmt->execute(array_values($ids));
            $registered = array_column($stmt->fetchAll(), 'unique_id');
        }
    }

    foreach ($found as &$dev) {
        $dev['already_registered'] = in_array($dev['unique_id'], $registered, true);
    }

    echo json_encode([
        'ok'    => true,
        'found' => $found,
        'count' => count($found),
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => $e->getMessage()]);
}
