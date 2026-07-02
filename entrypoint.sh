#!/bin/bash

# Ambil variabel dari Railway atau gunakan default jika tidak diset
USER_NAME="${SSH_USER:-ddfathu}"
USER_PASS="${SSH_PASSWORD:-123456}"
MAIN_PORT="${PORT:-8080}"

echo "[*] Mengonfigurasi User SSH..."
if ! id "$USER_NAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USER_NAME"
    usermod -aG sudo "$USER_NAME"
fi
echo "$USER_NAME:$USER_PASS" | chpasswd

# Tweak konfigurasi SSH agar support koneksi lokal super cepat & izinkan login password
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config

echo "[*] Memulai OpenSSH Server di Port 22..."
/usr/sbin/sshd

echo "[*] Memulai Python Hybrid Core (SNI + WS) di Port 8888..."
cat << 'EOF' > /usr/local/bin/ws-proxy.py
import socket
import threading

def forward(src, dst):
    try:
        while True:
            buf = src.recv(4096)
            if not buf:
                break
            dst.sendall(buf)
    except:
        pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

def handle(client):
    try:
        # Intip 1024 byte pertama untuk mendeteksi tipe koneksi (SNI atau WS)
        req = client.recv(1024)
        if not req:
            client.close()
            return
            
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.connect(('127.0.0.1', 22))
        
        # Cek apakah ini HTTP Request (WebSocket)
        req_decoded = req.decode('utf-8', errors='ignore')
        if "Upgrade: websocket" in req_decoded or "HTTP/1.1" in req_decoded:
            # Jika WebSocket, balas jabat tangan ke HTTP Custom/aplikasi tunnel
            client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
            # Jalankan jembatan data biasa setelah handshake selesai
            threading.Thread(target=forward, args=(client, server)).start()
            forward(server, client)
        else:
            # Jika SNI / SSH Biasa, kirimkan kembali data intipan tadi ke OpenSSH agar tidak corrupt
            server.sendall(req)
            threading.Thread(target=forward, args=(client, server)).start()
            forward(server, client)
    except:
        try: client.close()
        except: pass

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 8888))
s.listen(500)
while True:
    try:
        c, addr = s.accept()
        threading.Thread(target=handle, args=(c,)).start()
    except:
        pass
EOF

# Jalankan proxy python di background
python3 /usr/local/bin/ws-proxy.py &

echo "[*] Membuat konfigurasi Stunnel di Port $MAIN_PORT..."
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-hybrid]
accept = 0.0.0.0:$MAIN_PORT
connect = 127.0.0.1:8888
cert = /etc/stunnel/stunnel.pem
EOF

echo "[*] Memulai Stunnel Gateway..."
# Jalankan stunnel sebagai proses utama (exec) agar Docker tetap hidup/running di Railway
exec stunnel /etc/stunnel/stunnel.conf
