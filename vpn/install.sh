#!/usr/bin/env bash
# Automatische Installation des 2-Endpunkte-VPN.
#
#   ./install.sh all    --a user@server-a --b user@server-b [--port 51820] [--dns 1.1.1.1]
#       erzeugt Schluessel, richtet beide Server per SSH ein und installiert die Client-App
#   ./install.sh servers --a ... --b ...   nur Schluessel erzeugen + Server einrichten
#   ./install.sh client                    nur diesen Rechner (Profile aus ./out bzw. app/profiles)
#   Zusatz: --dry-run zeigt nur, was passieren wuerde
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"; shift || true
A=""; B=""; PORT=51820; DNS=1.1.1.1; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --a) A="$2"; shift 2;; --b) B="$2"; shift 2;;
    --port) PORT="$2"; shift 2;; --dns) DNS="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    *) echo "Unbekannte Option: $1" >&2; exit 1;;
  esac
done

run() { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes)

gen() {
  [ -n "$A" ] && [ -n "$B" ] || { echo "--a und --b (user@host) angeben" >&2; exit 1; }
  run python3 gen_configs.py --a "${A#*@}:$PORT" --b "${B#*@}:$PORT" --dns "$DNS"
}

servers() {
  for n in a b; do
    target="$A"; [ "$n" = b ] && target="$B"
    echo "==> Server $n ($target)"
    run scp "${SSH_OPTS[@]}" "out/server-$n.conf" server-setup.sh "$target:/tmp/"
    run ssh "${SSH_OPTS[@]}" "$target" \
      "S=''; [ \$(id -u) -ne 0 ] && S=sudo; chmod +x /tmp/server-setup.sh && \$S /tmp/server-setup.sh /tmp/server-$n.conf; rm -f /tmp/server-$n.conf"
  done
}

client() {
  echo "==> Abhaengigkeiten"
  if command -v apt-get >/dev/null; then
    run $SUDO apt-get update -qq
    run $SUDO apt-get install -y wireguard-tools resolvconf python3 python3-tk iproute2
  elif command -v dnf >/dev/null; then run $SUDO dnf install -y wireguard-tools python3 python3-tkinter
  elif command -v pacman >/dev/null; then run $SUDO pacman -S --needed --noconfirm wireguard-tools python tk openresolv
  elif command -v brew >/dev/null; then run brew install wireguard-tools python-tk
  else echo "Paketmanager unbekannt - wireguard-tools und python3-tk bitte manuell installieren" >&2; fi

  echo "==> App + Profile"
  run $SUDO install -d -m 700 /etc/wireguard
  for n in a b; do
    src="out/client-$n.conf"; [ -f "$src" ] || src="app/profiles/client-$n.conf"
    if [ -f "$src" ] || [ "$DRY" = 1 ]; then run $SUDO install -m 600 "$src" "/etc/wireguard/vpn$n.conf"
    else echo "client-$n.conf fehlt - erst './install.sh all' bzw. gen_configs.py ausfuehren" >&2; exit 1; fi
  done
  run $SUDO install -d /opt/vpn2
  run $SUDO install -m 755 app/vpn_app.py /opt/vpn2/vpn_app.py
  if [ "$DRY" = 1 ]; then echo "[dry-run] Launcher /usr/local/bin/vpn2, Menue-Eintrag, systemd-Dienst vpn2-watch"; return; fi

  $SUDO tee /usr/local/bin/vpn2 >/dev/null <<'L'
#!/bin/sh
# vpn2 -> GUI;  vpn2 connect a|b | disconnect | status | watch
if [ "$(id -u)" -ne 0 ]; then
  if [ -z "${1:-}" ] && command -v pkexec >/dev/null && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    exec pkexec env DISPLAY="$DISPLAY" XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" python3 /opt/vpn2/vpn_app.py
  fi
  exec sudo python3 /opt/vpn2/vpn_app.py "$@"
fi
exec python3 /opt/vpn2/vpn_app.py "$@"
L
  $SUDO chmod 755 /usr/local/bin/vpn2
  if [ -d /usr/share/applications ]; then
    $SUDO tee /usr/share/applications/vpn2.desktop >/dev/null <<'D'
[Desktop Entry]
Type=Application
Name=VPN (2 Endpunkte)
Exec=/usr/local/bin/vpn2
Icon=network-vpn
Categories=Network;
D
  fi
  if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then
    $SUDO tee /etc/systemd/system/vpn2-watch.service >/dev/null <<'S'
[Unit]
Description=VPN Failover-Ueberwachung (A/B)
After=network-online.target
[Service]
ExecStart=/usr/bin/python3 /opt/vpn2/vpn_app.py watch
Restart=on-failure
[Install]
WantedBy=multi-user.target
S
    $SUDO systemctl daemon-reload
    echo "Optional: Failover im Hintergrund: sudo systemctl enable --now vpn2-watch"
  fi
  echo "Fertig. Start: 'vpn2' (GUI) oder 'vpn2 connect a'"
}

case "$MODE" in
  all)     gen; servers; client;;
  servers) gen; servers;;
  client)  client;;
  *) sed -n '2,8p' "$0"; exit 1;;
esac
