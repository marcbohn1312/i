#!/usr/bin/env python3
"""Erzeugt WireGuard-Konfigurationen fuer ein VPN mit zwei Endpunkten.

Aufruf:
    python3 gen_configs.py --a vpn-a.example.com:51820 --b vpn-b.example.com:51820

Ergebnis (Ordner ./out, Rechte 600):
    server-a.conf / server-b.conf  -> je auf einen Server nach /etc/wireguard/wg0.conf
    client-a.conf / client-b.conf  -> Profile fuer die App (Namen: vpna / vpnb)
"""
import argparse
import base64
import os
import secrets
from pathlib import Path

P = 2**255 - 19
A24 = 121665


def _x25519(k: bytes, u: bytes) -> bytes:
    """X25519 nach RFC 7748 (reine Python-Implementierung, keine Abhaengigkeiten)."""
    k = bytearray(k)
    k[0] &= 248
    k[31] &= 127
    k[31] |= 64
    k = int.from_bytes(k, "little")
    x1 = int.from_bytes(u, "little") & ((1 << 255) - 1)
    x2, z2, x3, z3, swap = 1, 0, x1, 1, 0
    for t in reversed(range(255)):
        kt = (k >> t) & 1
        swap ^= kt
        if swap:
            x2, x3, z2, z3 = x3, x2, z3, z2
        swap = kt
        a, b = (x2 + z2) % P, (x2 - z2) % P
        aa, bb = a * a % P, b * b % P
        e = (aa - bb) % P
        c, d = (x3 + z3) % P, (x3 - z3) % P
        da, cb = d * a % P, c * b % P
        x3 = pow(da + cb, 2, P)
        z3 = x1 * pow(da - cb, 2, P) % P
        x2 = aa * bb % P
        z2 = e * (aa + A24 * e) % P
    if swap:
        x2, x3, z2, z3 = x3, x2, z3, z2
    return (x2 * pow(z2, P - 2, P) % P).to_bytes(32, "little")


def keypair():
    priv = secrets.token_bytes(32)
    pub = _x25519(priv, (9).to_bytes(32, "little"))
    return base64.b64encode(priv).decode(), base64.b64encode(pub).decode()


def psk():
    return base64.b64encode(secrets.token_bytes(32)).decode()


def write(path: Path, text: str):
    path.write_text(text)
    os.chmod(path, 0o600)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a", required=True, help="Endpunkt A, host:port")
    ap.add_argument("--b", required=True, help="Endpunkt B, host:port")
    ap.add_argument("--out", default="out")
    ap.add_argument("--dns", default="1.1.1.1")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(exist_ok=True)
    os.chmod(out, 0o700)

    cpriv, cpub = keypair()
    for name, ep, net in (("a", args.a, "10.10.1"), ("b", args.b, "10.10.2")):
        spriv, spub = keypair()
        key = psk()
        port = ep.rsplit(":", 1)[1]
        write(out / f"server-{name}.conf", f"""[Interface]
Address = {net}.1/24
ListenPort = {port}
PrivateKey = {spriv}
PostUp = sysctl -w net.ipv4.ip_forward=1; iptables -t nat -A POSTROUTING -s {net}.0/24 ! -o %i -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s {net}.0/24 ! -o %i -j MASQUERADE

[Peer]
PublicKey = {cpub}
PresharedKey = {key}
AllowedIPs = {net}.2/32
""")
        write(out / f"client-{name}.conf", f"""[Interface]
PrivateKey = {cpriv}
Address = {net}.2/24
DNS = {args.dns}

[Peer]
PublicKey = {spub}
PresharedKey = {key}
Endpoint = {ep}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
""")
    print(f"Fertig. Dateien in {out}/ - server-*.conf auf die Server, client-*.conf in die App.")


if __name__ == "__main__":
    main()
