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
