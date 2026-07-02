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

echo "[*] Menginstall Dropbear SSH Server..."
apt-get update && apt-get install -y dropbear python3

echo "[*] Memulai Dropbear di Port Lokal 222..."
# Jalankan dropbear di port internal 222 (mode no-banner & low-overhead)
dropbear -F -E -p 127.0.0.1:222 &

echo "[*] Membangun Python Premium WS Proxy (Kloning PT RAJA SERVER)..."
cat << 'EOF' > /usr/local/bin/premium-ws.py
import socket
import threading
import sys

def forward_stream(src, dst):
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

def handle_client(client_socket):
    try:
        # Baca payload awal dari Cloudflare
        client_socket.settimeout(5)
        request_data = client_socket.recv(8192)
        if not request_data:
            client_socket.close()
            return

        # Hubungkan ke Dropbear lokal
        dropbear_backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        dropbear_backend.connect(('127.0.0.1', 222))

        request_str = request_data.decode('utf-8', errors='ignore')
        
        # Jika terdeteksi traffic WebSocket/HTTP Payload
        if "HTTP/" in request_str or "Upgrade:" in request_str:
            # Kirim balasan 101 resmi yang disukai HTTP Custom & Cloudflare
            # Kita buat mirip dengan server premium orang lain
            response = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
            client_socket.sendall(response)
            
            # Alirkan data dua arah langsung ke Dropbear
            threading.Thread(target=forward_stream, args=(client_socket, dropbear_backend), daemon=True).start()
            forward_stream(dropbear_backend, client_socket)
        else:
            # Jika SNI Polosan murni, oper data intipan awal langsung ke Dropbear
            dropbear_backend.sendall(request_data)
            threading.Thread(target=forward_stream, args=(client_socket, dropbear_backend), daemon=True).start()
            forward_stream(dropbear_backend, client_socket)
            
    except Exception as e:
        try: client_socket.close()
        except: pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 8888))
    server.listen(1000)
    
    while True:
        try:
            client, addr = server.accept()
            threading.Thread(target=handle_client, args=(client,), daemon=True).start()
        except: pass

if __name__ == "__main__":
    main()
EOF

# Jalankan proxy premium di background
python3 /usr/local/bin/premium-ws.py &

echo "[*] Membuat konfigurasi Stunnel Multiplexer di Port $MAIN_PORT..."
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-premium-gateway]
accept = 0.0.0.0:$MAIN_PORT
connect = 127.0.0.1:8888
cert = /etc/stunnel/stunnel.pem
EOF

echo "[*] Memulai Stunnel Gateway..."
exec stunnel /etc/stunnel/stunnel.conf
