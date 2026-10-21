#!/usr/bin/env bash
# Richtet die IPTV-App auf einem Linux-Server als Dienst ein (startet automatisch nach einem Neustart).
# Aufruf:  curl -fsSL https://raw.githubusercontent.com/peteralphamind-wq/iptv-player/main/install.sh | sudo bash
# Anderer Port:  ... | sudo PORT=9000 bash
set -euo pipefail

PORT="${PORT:-8080}"
DIR=/opt/iptv-player
REPO=https://github.com/peteralphamind-wq/iptv-player.git

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte mit sudo ausführen." >&2
  exit 1
fi

if ! command -v python3 >/dev/null || ! command -v git >/dev/null; then
  echo "Installiere python3 und git …"
  if command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y -qq python3 git
  elif command -v dnf >/dev/null; then dnf install -y -q python3 git
  elif command -v apk >/dev/null; then apk add --quiet python3 git
  else echo "Bitte python3 und git von Hand installieren." >&2; exit 1
  fi
fi

if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull -q
else
  git clone -q --depth 1 "$REPO" "$DIR"
fi

cat > /etc/systemd/system/iptv-player.service <<EOF
[Unit]
Description=IPTV Player Web-App
After=network-online.target

[Service]
ExecStart=/usr/bin/env python3 $DIR/server.py $PORT
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now iptv-player >/dev/null
systemctl restart iptv-player

if command -v ufw >/dev/null && ufw status | grep -q active; then
  ufw allow "$PORT/tcp" >/dev/null
fi

echo
echo "Fertig. Die IPTV-App läuft auf Port $PORT."
command -v tailscale >/dev/null && TS_IP=$(tailscale ip -4 2>/dev/null | head -1) || TS_IP=""
[ -n "$TS_IP" ] && echo "Über Tailscale:  http://$TS_IP:$PORT/"
echo "Im Netzwerk:     http://$(hostname -I | awk '{print $1}'):$PORT/"
