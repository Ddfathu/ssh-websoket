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

echo "[*] Memulai Python WebSocket Lokal di Port 3333..."
cat << 'EOF' > /usr/local/bin/ws-server.py
import socket
import threading

def handle_client(client_socket):
    try:
        # Baca data awal (payload)
        request = client_socket.recv(1024).decode('utf-8', errors='ignore')
        
        # Jika HTTP Custom mengirimkan payload WebSocket, berikan respon HTTP 101 standar sekali saja
        if "GET " in request or "Upgrade: websocket" in request:
            client_socket.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        
        # Langsung sambungkan ke OpenSSH lokal port 22
        ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh_socket.connect(('127.0.0.1', 22))

        # Jika ada sisa data di awal request yang bukan bagian dari HTTP handshake, kirim ke SSH
        # Tapi dalam kasus HTTP Custom, setelah 101 biasanya langsung masuk paket data murni

        def forward(src, dst):
            try:
                while True:
                    data = src.recv(4096)
                    if not data: break
                    dst.sendall(data)
            except:
                pass
            finally:
                src.close()
                dst.close()

        threading.Thread(target=forward, args=(client_socket, ssh_socket)).start()
        threading.Thread(target=forward, args=(ssh_socket, client_socket)).start()
    except:
        client_socket.close()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', 3333))
server.listen(100)

while True:
    client, addr = server.accept()
    threading.Thread(target=handle_client, args=(client,)).start()
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
