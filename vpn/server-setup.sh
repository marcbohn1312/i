#!/usr/bin/env bash
# Auf jedem der beiden Server (Debian/Ubuntu) als root ausfuehren:
#   ./server-setup.sh server-a.conf     (bzw. server-b.conf)
set -euo pipefail
CONF="${1:?Usage: $0 server-x.conf}"
apt-get update -qq && apt-get install -y wireguard iptables
install -m 600 "$CONF" /etc/wireguard/wg0.conf
systemctl enable --now wg-quick@wg0
wg show wg0
echo "UDP-Port in Firewall/Security-Group freigeben!"
