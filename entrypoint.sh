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

echo "[*] Membuat Python WebSocket Server di Port 3333..."
cat << 'EOF' > /usr/local/bin/ws-server.py
import socket
import threading

def handle_client(client_socket):
    try:
        request = client_socket.recv(1024).decode('utf-8', errors='ignore')
        if "Upgrade: websocket" in request or "CONNECTION" in request:
            # Kirim balasan HTTP 101 Switching Protocols agar HTTP Custom menganggap Websocket sukses
            client_socket.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        
        # Hubungkan ke OpenSSH lokal port 22
        ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh_socket.connect(('127.0.0.1', 22))

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
    except Exception as e:
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

echo "[*] Memulai Stunnel (TLS) di Port 2222..."
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-ssl]
accept = 127.0.0.1:2222
# Lempar ke Python WS Server agar payload Websocket diproses setelah TLS dibuka
connect = 127.0.0.1:3333
cert = /etc/stunnel/stunnel.pem
EOF
stunnel /etc/stunnel/stunnel.conf &

echo "[*] Mengonfigurasi HAProxy Gateway di Port $MAIN_PORT..."
cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0

defaults
    log     global
    mode    tcp
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend main_gateway
    bind 0.0.0.0:$MAIN_PORT
    mode tcp
    tcp-request inspect-delay 2s
    
    # Jika mendeteksi handshake SSL/TLS (SNI), lempar ke Stunnel
    use_backend backend_stunnel if { req_ssl_hello_type 1 }
    default_backend backend_websocket

backend backend_stunnel
    mode tcp
    server ssl_wrap 127.0.0.1:2222 check

backend backend_websocket
    mode tcp
    server ws_wrap 127.0.0.1:3333 check
EOF

echo "[*] Menjalankan HAProxy Gateway..."
exec haproxy -f /etc/haproxy/haproxy.cfg -db
