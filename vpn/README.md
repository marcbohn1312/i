# VPN mit 2 Endpunkten (WireGuard)

Zwei VPN-Server (Endpunkt A und B) plus eine Client-App, die zwischen beiden
wechselt und bei Ausfall automatisch umschaltet.

```
 Client-App ──► Endpunkt A (10.10.1.0/24)
      └──────► Endpunkt B (10.10.2.0/24)   (immer nur einer aktiv)
```

## 1. Konfigurationen erzeugen
```
python3 gen_configs.py --a vpn-a.example.com:51820 --b vpn-b.example.com:51820
```
Erzeugt in `out/` Schlüssel + `server-a/b.conf` und `client-a/b.conf` (keine Abhängigkeiten, auch ohne `wg`).
**Nicht committen** – `out/` und `*.conf` sind in `.gitignore`.

## 2. Server einrichten (je einer pro Endpunkt, Debian/Ubuntu, root)
```
./server-setup.sh server-a.conf     # auf Server A
./server-setup.sh server-b.conf     # auf Server B
```
UDP-Port in der Firewall freigeben.

## 3. App auf dem Client (Linux/macOS, `wireguard-tools` nötig)
Die `client-*.conf` nach `app/profiles/` kopieren, dann:
```
sudo python3 app/vpn_app.py                 # GUI (tkinter)
sudo python3 app/vpn_app.py connect a|b
sudo python3 app/vpn_app.py disconnect | status | watch
```
Failover: Hat der aktive Tunnel keinen frischen Handshake (>150 s) mehr, wechselt die App zu
dem anderen Endpunkt (`watch` bzw. Häkchen in der GUI).

## Hinweise
- Kein Split-Tunnel: `AllowedIPs = 0.0.0.0/0, ::/0`; in `client-*.conf` anpassbar.
- Windows/Android/iOS: die `client-*.conf` lassen sich direkt in die offiziellen WireGuard-Apps importieren (beide Profile, manuell umschalten).
- Getestet: Schlüsselerzeugung (RFC‑7748-Vektor) und Failover-Logik mit Mock. Ein echter Tunnel wurde hier nicht aufgebaut (keine Server/Root in der Sandbox).
