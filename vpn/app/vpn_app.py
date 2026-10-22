#!/usr/bin/env python3
"""VPN-App mit zwei Endpunkten (WireGuard).

GUI:   sudo python3 vpn_app.py
CLI:   sudo python3 vpn_app.py connect a|b | disconnect | status | watch

Profile: client-a.conf / client-b.conf (aus gen_configs.py) liegen in ./profiles
oder in /etc/wireguard als vpna.conf / vpnb.conf. Die App installiert sie bei
Bedarf nach /etc/wireguard und steuert sie mit wg-quick.
"""
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ENDPOINTS = {"a": "vpna", "b": "vpnb"}
HANDSHAKE_MAX_AGE = 150   # Sekunden; WireGuard erneuert alle ~120 s
CHECK_INTERVAL = 10
PROFILE_DIR = Path(__file__).parent / "profiles"


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError:
        raise RuntimeError(f"'{cmd[0]}' nicht gefunden - bitte 'wireguard-tools' installieren") from None


def install_profiles():
    for key, iface in ENDPOINTS.items():
        dst = Path(f"/etc/wireguard/{iface}.conf")
        src = PROFILE_DIR / f"client-{key}.conf"
        if src.exists() and not dst.exists():
            dst.parent.mkdir(mode=0o700, exist_ok=True)
            shutil.copy(src, dst)
            dst.chmod(0o600)


def is_up(iface):
    return run("wg", "show", iface).returncode == 0


def active():
    for key, iface in ENDPOINTS.items():
        if is_up(iface):
            return key
    return None


def healthy(iface):
    """Tunnel gilt als gesund, wenn der letzte Handshake jung genug ist."""
    r = run("wg", "show", iface, "latest-handshakes")
    try:
        ts = int(r.stdout.split()[1])
    except (IndexError, ValueError):
        return False
    return ts > 0 and time.time() - ts < HANDSHAKE_MAX_AGE


def disconnect():
    for iface in ENDPOINTS.values():
        if is_up(iface):
            run("wg-quick", "down", iface)


def connect(key):
    install_profiles()
    disconnect()
    r = run("wg-quick", "up", ENDPOINTS[key])
    if r.returncode:
        raise RuntimeError(r.stderr.strip() or "wg-quick up fehlgeschlagen")


def status():
    key = active()
    if not key:
        return "Getrennt"
    ok = healthy(ENDPOINTS[key])
    return f"Verbunden mit Endpunkt {key.upper()}" + ("" if ok else " (warte auf Handshake ...)")


def failover_if_down(grace=15):
    """Wechselt zum anderen Endpunkt, wenn der aktive auch nach `grace` s keinen Handshake hat."""
    key = active()
    if not key or healthy(ENDPOINTS[key]):
        return None
    time.sleep(grace)
    if healthy(ENDPOINTS[key]):
        return None
    other = "b" if key == "a" else "a"
    connect(other)
    return other


def watch():
    while True:
        other = failover_if_down()
        if other:
            print(f"Failover -> Endpunkt {other.upper()}", flush=True)
        time.sleep(CHECK_INTERVAL)


def gui():
    import tkinter as tk

    root = tk.Tk()
    root.title("VPN - 2 Endpunkte")
    root.geometry("320x230")
    sel = tk.StringVar(value="a")
    auto = tk.BooleanVar(value=True)
    msg = tk.StringVar(value="Bereit")

    tk.Label(root, text="Endpunkt wählen", font=("", 12, "bold")).pack(pady=8)
    tk.Radiobutton(root, text="Endpunkt A", variable=sel, value="a").pack(anchor="w", padx=40)
    tk.Radiobutton(root, text="Endpunkt B", variable=sel, value="b").pack(anchor="w", padx=40)
    tk.Checkbutton(root, text="Automatisch umschalten bei Ausfall", variable=auto).pack(pady=6)

    def do(fn, *a):
        def work():
            try:
                fn(*a)
            except Exception as e:  # noqa: BLE001
                msg.set(f"Fehler: {e}")
        threading.Thread(target=work, daemon=True).start()

    f = tk.Frame(root)
    f.pack(pady=6)
    tk.Button(f, text="Verbinden", command=lambda: do(connect, sel.get())).pack(side="left", padx=6)
    tk.Button(f, text="Trennen", command=lambda: do(disconnect)).pack(side="left", padx=6)
    tk.Label(root, textvariable=msg).pack(pady=8)

    def tick():
        try:
            if not msg.get().startswith("Fehler"):
                msg.set(status())
            if auto.get():
                do(failover_if_down)
        except RuntimeError as e:
            msg.set(f"Fehler: {e}")
        root.after(CHECK_INTERVAL * 1000, tick)

    root.after(1000, tick)
    root.mainloop()


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "gui"
    if cmd == "gui":
        gui()
    elif cmd == "connect" and len(argv) == 3 and argv[2] in ENDPOINTS:
        connect(argv[2])
        print(status())
    elif cmd == "disconnect":
        disconnect()
        print(status())
    elif cmd == "status":
        print(status())
    elif cmd == "watch":
        watch()
    else:
        print(__doc__)
        return 1
    return 0


def cli(argv):
    try:
        return main(argv)
    except RuntimeError as e:
        print(f"Fehler: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(cli(sys.argv))
