#!/bin/bash

USER_NAME="${SSH_USER:-ddfathu}"
USER_PASS="${SSH_PASSWORD:-123456}"
MAIN_PORT="${PORT:-8080}"

echo "[*] Mengonfigurasi User SSH..."
if ! id "$USER_NAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USER_NAME"
    usermod -aG sudo "$USER_NAME"
fi
echo "$USER_NAME:$USER_PASS" | chpasswd

echo "[*] Memulai Dropbear di Port Lokal 222..."
# Dropbear dipasang di port internal 222 biar kebal payload double HTTP abang
dropbear -F -E -p 127.0.0.1:222 &

echo "[*] Membangun Python Proxy dengan Teks Kustom Premium..."
cat << 'EOF' > /usr/local/bin/premium-ws.py
import socket, threading

def forward(src, dst):
    try:
        while True:
            data = src.recv(8192)
            if not data: break
            dst.sendall(data)
    except: pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

def handle(client):
    try:
        client.settimeout(5)
        req = client.recv(8192)
        if not req: return
        
        backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        backend.connect(('127.0.0.1', 222))
        
        req_str = req.decode('utf-8', errors='ignore')
        if "HTTP/" in req_str or "Upgrade:" in req_str:
            # DI SINI KUNCINYA, BOS! Teks kustom dipasang langsung setelah status 101
            custom_101 = b"HTTP/1.1 101 PT DDFATHU TUNNEL PREMIUM\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
            client.sendall(custom_101)
            
            threading.Thread(target=forward, args=(client, backend), daemon=True).start()
            forward(backend, client)
        else:
            # Jalur SNI Polosan murni
            backend.sendall(req)
            threading.Thread(target=forward, args=(client, backend), daemon=True).start()
            forward(backend, client)
    except: pass

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 8888))
s.listen(1000)
while True:
    try:
        c, addr = s.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()
    except: pass
EOF

python3 /usr/local/bin/premium-ws.py &

echo "[*] Membuat konfigurasi Stunnel Gateway..."
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-premium]
accept = 0.0.0.0:$MAIN_PORT
connect = 127.0.0.1:8888
cert = /etc/stunnel/stunnel.pem
EOF

exec stunnel /etc/stunnel/stunnel.conf
