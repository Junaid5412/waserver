<?php
/** PHP 8+ and curl extension. No automatic retries. */
final class Zelon {
    private string $base;
    public function __construct(string $url, string $instanceId, private string $apiKey) {
        $this->base = rtrim($url, '/') . '/api/instances/' . rawurlencode($instanceId);
    }
    public function request(string $path, string $method = 'GET', mixed $body = null, ?string $key = null, bool $raw = false): array {
        $ch = curl_init($this->base . $path);
        $headers = ['Authorization: Bearer ' . $this->apiKey];
        if ($body !== null) $headers[] = 'Content-Type: ' . ($raw ? 'application/octet-stream' : 'application/json');
        if ($key !== null) $headers[] = 'Idempotency-Key: ' . $key;
        curl_setopt_array($ch, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_HTTPHEADER => $headers, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 30, CURLOPT_FOLLOWLOCATION => false]);
        if ($body !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, $raw ? $body : json_encode($body, JSON_THROW_ON_ERROR));
        $response = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $error = curl_error($ch);
        curl_close($ch);
        if ($response === false) throw new RuntimeException($error);
        $data = json_decode($response, true, 512, JSON_THROW_ON_ERROR);
        if ($status >= 400) throw new RuntimeException($data['error'] ?? 'HTTP ' . $status, $status);
        return $data;
    }
    public function send(array $message, ?string $key = null): array {
        return $this->request('/messages', 'POST', $message, $key ?? bin2hex(random_bytes(16)));
    }
    public function upload(string $path, string $mimetype = 'application/octet-stream'): array {
        $size = filesize($path);
        if ($size === false) throw new RuntimeException('Cannot read file');
        $m = $this->request('/media', 'POST', ['filename' => basename($path), 'size' => $size, 'mimetype' => $mimetype]);
        $stream = fopen($path, 'rb');
        if ($stream === false) throw new RuntimeException('Cannot open file');
        try { for ($i = 0; $i < $m['totalChunks']; $i++) $this->request('/media/' . $m['id'] . '/chunks/' . $i, 'PUT', fread($stream, $m['chunkSize']), null, true); }
        finally { fclose($stream); }
        return $this->request('/media/' . $m['id'] . '/complete', 'POST', new stdClass());
    }
}
