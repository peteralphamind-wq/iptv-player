<?php
// Holt eine M3U-Playlist stellvertretend ab, damit der Browser nicht an CORS scheitert.
// Für Webhosting mit PHP (z. B. Hostpoint). Gibt nur echte M3U-Playlists weiter,
// damit das Skript nicht als offener Proxy missbraucht werden kann.

$url = $_GET['url'] ?? '';
if (!preg_match('#^https?://#i', $url)) {
    http_response_code(400);
    exit('url fehlt');
}

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_MAXREDIRS => 5,
    CURLOPT_CONNECTTIMEOUT => 15,
    CURLOPT_TIMEOUT => 120,
    CURLOPT_USERAGENT => 'VLC/3.0.20 LibVLC/3.0.20', // manche Anbieter sperren Browser-Kennungen
    CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
]);
$body = curl_exec($ch);
$status = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
$error = curl_error($ch);
curl_close($ch);

if ($body === false) {
    http_response_code(502);
    exit('Anbieter nicht erreichbar: ' . $error);
}
if (strpos(ltrim($body, "\xEF\xBB\xBF \r\n\t"), '#EXTM3U') !== 0) {
    http_response_code(502);
    exit('Keine M3U-Playlist (Status ' . $status . ')');
}

header('Content-Type: audio/x-mpegurl; charset=utf-8');
header('Cache-Control: no-store');
echo $body;
