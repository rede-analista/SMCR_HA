<?php
/**
 * Endpoint para automação do Home Assistant.
 * Executa descoberta mDNS e auto-registra dispositivos novos.
 *
 * POST /api/auto_discover.php
 * Header: Authorization: Bearer <register_token>
 *   ou Body JSON: {"token": "<register_token>"}
 */
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/../config/db.php';

// Valida token (usa o register_token da tabela settings)
function validate_token(PDO $db): bool {
    $token = '';

    // Aceita via Authorization header
    $auth = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (str_starts_with($auth, 'Bearer ')) {
        $token = trim(substr($auth, 7));
    }

    // Aceita via corpo JSON
    if ($token === '') {
        $body = json_decode(file_get_contents('php://input'), true);
        $token = trim($body['token'] ?? '');
    }

    if ($token === '') return false;

    $stmt = $db->prepare("SELECT value FROM settings WHERE `key` = 'register_token'");
    $stmt->execute();
    $stored = $stmt->fetchColumn();

    return $stored && hash_equals((string)$stored, $token);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'Method not allowed']);
    exit;
}

$db = getDB();

if (!validate_token($db)) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'Unauthorized: invalid token']);
    exit;
}

// Executa descoberta mDNS
$script = __DIR__ . '/mdns_discover.py';
$output = shell_exec('python3 ' . escapeshellarg($script) . ' 2>/dev/null');
$found  = [];

if ($output !== null && $output !== '') {
    $data = json_decode($output, true);
    if (is_array($data) && !isset($data['error'])) {
        $found = $data;
    }
}

// Busca unique_id via HTTP /api/mqtt/status em paralelo (curl_multi)
function enrich_unique_ids(array $devices): array {
    if (empty($devices)) return $devices;
    $mh = curl_multi_init();
    $handles = [];
    foreach ($devices as $i => $dev) {
        $ch = curl_init("http://{$dev['ip']}:{$dev['port']}/api/mqtt/status");
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 3,
            CURLOPT_CONNECTTIMEOUT => 2,
        ]);
        curl_multi_add_handle($mh, $ch);
        $handles[$i] = $ch;
    }
    $running = null;
    do { curl_multi_exec($mh, $running); curl_multi_select($mh, 0.1); } while ($running > 0);
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
        if (empty($devices[$i]['unique_id'])) {
            $devices[$i]['unique_id'] = $devices[$i]['hostname'];
        }
    }
    curl_multi_close($mh);
    return $devices;
}

$found = enrich_unique_ids($found);

// Auto-registra dispositivos novos
$registered = 0;
$skipped    = 0;
$errors     = [];

foreach ($found as $dev) {
    $unique_id = $dev['unique_id'] ?? '';
    if ($unique_id === '') { $skipped++; continue; }

    $stmt = $db->prepare('SELECT id FROM devices WHERE unique_id = ?');
    $stmt->execute([$unique_id]);
    if ($stmt->fetch()) { $skipped++; continue; }

    try {
        $api_token = bin2hex(random_bytes(32));
        $name      = $dev['hostname'] ?: $unique_id;
        $db->beginTransaction();
        $stmt = $db->prepare('INSERT INTO devices (unique_id, name, api_token, last_seen, online) VALUES (?, ?, ?, NOW(), 1)');
        $stmt->execute([$unique_id, $name, $api_token]);
        $device_id = (int)$db->lastInsertId();
        $db->prepare('INSERT INTO device_config (device_id, hostname) VALUES (?, ?)')->execute([$device_id, $dev['hostname'] ?: 'esp32modularx']);
        $db->prepare('INSERT INTO device_status (device_id, ip, hostname) VALUES (?, ?, ?)')->execute([$device_id, $dev['ip'], $dev['hostname']]);
        $db->commit();
        $registered++;
    } catch (Exception $e) {
        if ($db->inTransaction()) $db->rollBack();
        $errors[] = $e->getMessage();
    }
}

echo json_encode([
    'ok'         => true,
    'found'      => count($found),
    'registered' => $registered,
    'skipped'    => $skipped,
    'errors'     => $errors,
]);
