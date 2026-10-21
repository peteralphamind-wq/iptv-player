#!/usr/bin/env python3
"""Kleiner Heimserver für die IPTV-App.

Liefert die App über http aus, damit Safari die http-Playlists und -Streams
der Anbieter nicht blockiert, und holt Playlists stellvertretend ab
(/proxy?url=…), damit der Browser nicht an CORS scheitert.

Start:   python3 server.py          (Port 8080)
         python3 server.py 9000     (anderer Port)
Aufruf:  http://<rechnername-oder-tailscale-ip>:8080/
"""

import http.server
import os
import socketserver
import sys
import urllib.parse
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
ROOT = os.path.dirname(os.path.abspath(__file__))
UA = 'VLC/3.0.20 LibVLC/3.0.20'  # manche Anbieter sperren Browser-Kennungen


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.endswith('/proxy'):
            return self.proxy(urllib.parse.parse_qs(parsed.query).get('url', [''])[0])
        if parsed.path.endswith('.py'):
            return self.send_error(404)
        return super().do_GET()

    def proxy(self, url):
        if not url.startswith(('http://', 'https://')):
            return self.send_error(400, 'url fehlt')
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=60) as res:
                self.send_response(res.status)
                self.send_header('Content-Type', res.headers.get('Content-Type', 'text/plain'))
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                while chunk := res.read(64 * 1024):
                    self.wfile.write(chunk)
        except Exception as err:  # Anbieter nicht erreichbar, falsche Zugangsdaten usw.
            self.send_error(502, str(err)[:200])


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == '__main__':
    with Server(('0.0.0.0', PORT), Handler) as httpd:
        print(f'IPTV-App läuft: http://localhost:{PORT}/  (Beenden mit Ctrl+C)')
        httpd.serve_forever()
