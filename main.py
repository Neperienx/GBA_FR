# main.py
import os
import sys
import time
import shutil
import socket
import threading
import subprocess
from contextlib import suppress

# --- Config -----------------------------------------------------------

HOST, PORT = "127.0.0.1", 8765

# BizHawk paths
BIZHAWK_EXE = r"C:\BizHawk\EmuHawk.exe"
ROM_PATH    = r"C:\Bizhawk\GBA\SaveRAM\Pokemon - Version Rouge Feu (France).gba"  # <-- keep your path

# Lua paths: edit in your repo; we mirror it into BizHawk\Lua\ before launch
SRC_LUA     = r"C:\Users\nicol\Documents\Programming\Pokemon_codex\lua\bizhawk_client_bridge.lua"
DEST_LUA    = r"C:\BizHawk\Lua\bizhawk_client_bridge.lua"  # overwritten each run

# Throttle how often we print state lines (seconds)
STATE_PRINT_PERIOD = 0.5

# --- Globals ----------------------------------------------------------

ready_evt = threading.Event()
stop_evt  = threading.Event()

# --- Helpers ----------------------------------------------------------

def ensure_paths():
    ok = True
    if not os.path.isfile(BIZHAWK_EXE):
        print(f"[py][ERR] EmuHawk not found: {BIZHAWK_EXE}", file=sys.stderr); ok = False
    if not os.path.isfile(ROM_PATH):
        print(f"[py][ERR] ROM not found: {ROM_PATH}", file=sys.stderr); ok = False
    if not os.path.isfile(SRC_LUA):
        print(f"[py][ERR] Repo Lua not found: {SRC_LUA}", file=sys.stderr); ok = False
    # ensure BizHawk\Lua exists
    dest_dir = os.path.dirname(DEST_LUA)
    if not os.path.isdir(dest_dir):
        try:
            os.makedirs(dest_dir, exist_ok=True)
        except Exception as e:
            print(f"[py][ERR] cannot create {dest_dir}: {e}", file=sys.stderr); ok = False
    if not ok:
        sys.exit(1)

def copy_lua():
    """Mirror repo Lua into BizHawk\Lua\ (overwrite every run)."""
    try:
        shutil.copy2(SRC_LUA, DEST_LUA)
        print(f"[py] copied Lua: {SRC_LUA} -> {DEST_LUA}")
    except Exception as e:
        print(f"[py][ERR] failed to copy Lua: {e}", file=sys.stderr)
        sys.exit(1)

def server_thread():
    """Blocking TCP server; prints incoming lines from BizHawk."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT))
        srv.listen(1)
        print(f"[py] listening on {HOST}:{PORT}", flush=True)
        ready_evt.set()

        srv.settimeout(0.5)
        conn = addr = None
        while not stop_evt.is_set() and conn is None:
            try:
                conn, addr = srv.accept()
            except socket.timeout:
                continue

        if conn is None:
            return

        print(f"[py] BizHawk connected from {addr}", flush=True)

        with conn:
            conn.settimeout(0.2)
            buf = b""
            last_state_print = 0.0

            while not stop_evt.is_set():
                try:
                    data = conn.recv(4096)
                    if not data:
                        print("[py] disconnected", flush=True)
                        break
                    buf += data

                    # Handle all complete lines currently buffered
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        txt = line.decode(errors="replace")

                        if '"type":"state"' in txt:
                            now = time.time()
                            if now - last_state_print >= STATE_PRINT_PERIOD:
                                print("[py] state:", txt, flush=True)
                                last_state_print = now
                        else:
                            print("[py] msg:", txt, flush=True)

                except socket.timeout:
                    pass
                except ConnectionResetError:
                    print("[py] connection reset by BizHawk", flush=True)
                    break

def launch_bizhawk():
    # Always quote the --lua path (spaces!)
    cmd = [
        BIZHAWK_EXE,
        "--gdi",
        f"--socket_ip={HOST}",
        f"--socket_port={PORT}",
        f'--lua="{DEST_LUA}"',
        ROM_PATH
    ]
    print("[py] launching BizHawk...", flush=True)
    return subprocess.Popen(cmd)

# --- Main -------------------------------------------------------------

def main():
    ensure_paths()
    copy_lua()  # keep BizHawk using your repo script

    t = threading.Thread(target=server_thread, daemon=False)
    t.start()

    # Only launch BizHawk once the server is listening
    ready_evt.wait(timeout=10)
    if not ready_evt.is_set():
        print("[py][ERR] server failed to start", file=sys.stderr)
        sys.exit(1)

    proc = launch_bizhawk()
    print("[py] waiting for connections… (Ctrl+C to quit)", flush=True)

    try:
        t.join()
    except KeyboardInterrupt:
        print("\n[py] shutting down…", flush=True)
    finally:
        stop_evt.set()
        with suppress(Exception):
            proc.terminate()

if __name__ == "__main__":
    main()
