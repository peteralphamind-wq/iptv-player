# IPTV Player (Web-App fürs iPhone)

M3U-Link einmal eintragen – er bleibt gespeichert. Sender nach Gruppen filtern, suchen, Favoriten markieren.

## Installieren aufs iPhone
1. Seite in **Safari** öffnen (GitHub Pages: `https://<benutzer>.github.io/iptv-player/`).
2. Teilen-Symbol → **Zum Home-Bildschirm**.
3. App öffnen → **M3U-Link hinzufügen**.

Playlists, Favoriten und der zuletzt geladene Inhalt werden nur auf dem Gerät gespeichert (localStorage/IndexedDB), nie auf einem Server.

## Wenn etwas nicht geht
- **Link beginnt mit `http://`** oder der Server blockiert den Abruf (CORS): M3U-Datei in Safari herunterladen und unter „Datei oder Text verwenden“ auswählen.
- **Sender spielt nicht** (z. B. `.ts`-Streams oder `http://`-Streams): Im Player auf **VLC** tippen – öffnet den Stream in der kostenlosen App „VLC for Mobile“.

## Veröffentlichen mit GitHub Pages
Settings → Pages → Source: „Deploy from a branch“, Branch `main`, Ordner `/ (root)`.

## Anbieter mit http:// (z. B. Xtream-Links mit get.php)
Safari blockiert http-Playlists und -Streams auf https-Seiten wie GitHub Pages.
Lösung: die App über einen Rechner zu Hause per http ausliefern und mit Tailscale erreichen.

1. Repo auf den Rechner laden (Code → Download ZIP, entpacken). Python 3 muss installiert sein
   (Mac/Linux: vorhanden, Windows: python.org).
2. Im Ordner starten: `python3 server.py` (Windows: `py server.py`). Der Rechner muss eingeschaltet bleiben.
3. iPhone mit Tailscale verbinden und in Safari öffnen: `http://<Tailscale-Name-des-Rechners>:8080/`
4. Teilen → Zum Home-Bildschirm. Den M3U-Link einfach einfügen – der Server holt die Playlist ab.
