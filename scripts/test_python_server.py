# test_python_server.py
import socket, threading

HOST, PORT = "127.0.0.1", 8765
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((HOST, PORT))
srv.listen(1)
print(f"[py] listening on {HOST}:{PORT}")

conn, addr = srv.accept()
print(f"[py] BizHawk connected from {addr}")

def recv_loop():
    buf = b""
    while True:
        data = conn.recv(4096)
        if not data:
            print("[py] disconnected")
            break
        buf += data
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            print("[py] from bizhawk:", line.decode(errors="replace"))

threading.Thread(target=recv_loop, daemon=True).start()

# send a couple of demo messages
conn.sendall(b"PING\n")
conn.sendall(b"PRESS A\n")

input("Press Enter to quit...\n")
conn.close()
srv.close()
