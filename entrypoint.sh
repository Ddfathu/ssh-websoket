#!/bin/bash

USER_NAME="${SSH_USER:-ddfathu}"
USER_PASS="${SSH_PASSWORD:-123456}"
MAIN_PORT="${PORT:-8080}" # Ini akan jadi port utama untuk SSL/TLS (SNI)
WS_PORT="80"               # Port HTTP biasa untuk WebSocket (Tanpa SSL)
SSH_PORT="22"

echo "[*] Mengonfigurasi User SSH..."
if ! id "$USER_NAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USER_NAME"
    usermod -aG sudo "$USER_NAME"
fi
echo "$USER_NAME:$USER_PASS" | chpasswd

echo "[*] Memulai OpenSSH Server di Port $SSH_PORT..."
/usr/sbin/sshd

echo "[*] Menginstall & Menjalankan Python WebSocket Proxy..."
# Script Python sederhana untuk handle WebSocket HTTP Upgrade ke SSH
cat << 'EOF' > /usr/local/bin/ws-proxy.py
import socket, sys, threading

def handle(client):
    try:
        req = client.recv(1024).decode('utf-8', errors='ignore')
        if "Upgrade: websocket" in req or "HTTP/1.1" in req:
            client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server.connect(('127.0.0.1', 22))
            
            def forward(src, dst):
                try:
                    while True:
                        buf = src.recv(4096)
                        if not buf: break
                        dst.sendall(buf)
                except: pass
            
            threading.Thread(target=forward, args=(client, server)).start()
            forward(server, client)
    except: pass
    finally: client.close()

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('0.0.0.0', 8888)) # WS Proxy jalan internal di port 8888
s.listen(100)
while True:
    c, addr = s.accept()
    threading.Thread(target=handle, args=(c,)).start()
EOF

python3 /usr/local/bin/ws-proxy.py &

echo "[*] Membuat konfigurasi Stunnel tunggal di Port $MAIN_PORT..."
# Sekarang Stunnel di-connect ke WS Proxy (8888), bukan langsung ke SSH (22)
# Jadi port $MAIN_PORT bisa buat SSH SNI + SSH WS TLS
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-websocket-ssl]
accept = 0.0.0.0:$MAIN_PORT
connect = 127.0.0.1:8888
cert = /etc/stunnel/stunnel.pem
EOF

echo "[*] Memulai Stunnel..."
exec stunnel /etc/stunnel/stunnel.conf
        # Hubungkan langsung ke OpenSSH lokal tanpa menahan buffer data (Anti-Lag / Anti-Freeze)
        ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh_socket.connect(('127.0.0.1', 22))

        # Kirim respons HTTP 101 langsung di awal untuk memancing HTTP Custom membuka jalur
        client_socket.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")

        # Jalankan jembatan data dua arah secara simultan
        threading.Thread(target=forward, args=(client_socket, ssh_socket)).start()
        threading.Thread(target=forward, args=(ssh_socket, client_socket)).start()
    except:
        client_socket.close()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', 3333))
server.listen(500)

while True:
    try:
        client, addr = server.accept()
        threading.Thread(target=handle_client, args=(client,)).start()
    except:
        pass
EOF

python3 /usr/local/bin/ws-server.py &

echo "[*] Memulai Stunnel sebagai Front-Gateway di Port $MAIN_PORT..."
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-ssl]
accept = 0.0.0.0:$MAIN_PORT
connect = 127.0.0.1:3333
cert = /etc/stunnel/stunnel.pem
EOF

exec stunnel /etc/stunnel/stunnel.conf
