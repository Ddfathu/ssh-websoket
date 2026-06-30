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

echo "[*] Memulai OpenSSH Server di Port 22..."
/usr/sbin/sshd

echo "[*] Memulai Python Stream WebSocket Lokal di Port 3333..."
cat << 'EOF' > /usr/local/bin/ws-server.py
import socket
import threading

def forward(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data: 
                break
            dst.sendall(data)
    except:
        pass
    finally:
        src.close()
        dst.close()

def handle_client(client_socket):
    try:
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
