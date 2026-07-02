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

# Tweak Kernel & OpenSSH Server untuk High Performance & Kebal Payload
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config

echo "[*] Memulai OpenSSH Server di Port 22..."
/usr/sbin/sshd

echo "[*] Membangun Python Enterprise Traffic Multiplexer (Anti-Crash)..."
cat << 'EOF' > /usr/local/bin/core-gateway.py
import socket
import threading
import sys
import time

MAX_BUFFER = 16384  # Buffer besar untuk menampung tumpukan payload tanpa chunking

def pipe_stream(source, destination, initial_data=None):
    """Fungsi menjembatani data dua arah secara simultan dengan penanganan error ketat"""
    if initial_data:
        try:
            destination.sendall(initial_data)
        except Exception as e:
            return
            
    source.settimeout(300)
    destination.settimeout(300)
    
    def forward(src, dst):
        try:
            while True:
                data = src.recv(MAX_BUFFER)
                if not data:
                    break
                dst.sendall(data)
        except:
            pass
        finally:
            try: src.close()
        except: pass
            try: dst.close()
        except: pass

    threading.Thread(target=forward, args=(source, destination), daemon=True).start()
    threading.Thread(target=forward, args=(destination, source), daemon=True).start()

def handle_incoming_connection(client_socket):
    try:
        # Intip header awal tanpa mengosongkan buffer socket
        client_socket.settimeout(10)
        peek_data = client_socket.recv(MAX_BUFFER)
        
        if not peek_data:
            client_socket.close()
            return

        # Buka koneksi internal ke OpenSSH Server
        ssh_backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh_backend.connect(('127.0.0.1', 22))

        # Analisis Karakteristik Data (Deep Packet Inspection Sederhana)
        data_string = peek_data.decode('utf-8', errors='ignore')
        
        # KONDISI 1: Terdeteksi Payload WebSocket HTTP (Termasuk Double HTTP GET/PATCH/POST)
        if any(x in data_string for x in ["Upgrade: websocket", "HTTP/1.1", "HTTP/1.0", "GET ", "PATCH "]):
            # Server wajib merespons jabat tangan 101 murni di awal agar Cloudflare & HTTP Custom sinkron
            handshake_response = (
                b"HTTP/1.1 101 Switching Protocols\r\n"
                b"Upgrade: websocket\r\n"
                b"Connection: Upgrade\r\n\r\n"
            )
            client_socket.sendall(handshake_response)
            
            # Alirkan seluruh sisa payload data ke SSH Backend
            pipe_stream(client_socket, ssh_backend, initial_data=None)
            
        # KONDISI 2: Terdeteksi SSL/TLS Handshake Murni (SNI Polosan)
        # Karakteristik SSL Handshake selalu dimulai dengan Byte 0x16 (22 desimal)
        elif peek_data[0] == 0x16 or peek_data[0] == 22:
            # Kembalikan data intipan murni ke backend karena OpenSSH membutuhkan byte TLS awal tersebut
            pipe_stream(client_socket, ssh_backend, initial_data=peek_data)
            
        # KONDISI 3: Traffic Lainnya (Fallback Aman)
        else:
            pipe_stream(client_socket, ssh_backend, initial_data=peek_data)

    except Exception as e:
        try: client_socket.close()
    except: pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    # Ikatan soket internal lokal
    try:
        server.bind(('127.0.0.1', 8888))
    except Exception as e:
        sys.exit(1)
        
    server.listen(2000)  # Antrean backlog besar untuk mencegah penolakan koneksi massal
    
    while True:
        try:
            client_conn, addr = server.accept()
            # Gunakan daemon thread agar alokasi memori VPS otomatis dibersihkan saat DC
            t = threading.Thread(target=handle_incoming_connection, args=(client_conn,), daemon=True)
            t.start()
        except KeyboardInterrupt:
            break
        except:
            time.sleep(0.1)

if __name__ == "__main__":
    main()
EOF

# Jalankan Core Engine di Background
python3 /usr/local/bin/core-gateway.py &

echo "[*] Mengonfigurasi Stunnel Gateway SSL di Port $MAIN_PORT..."
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-complex-multiplexer]
accept = 0.0.0.0:$MAIN_PORT
connect = 127.0.0.1:8888
cert = /etc/stunnel/stunnel.pem
EOF

echo "[*] Memulai Stunnel Multiplexer..."
exec stunnel /etc/stunnel/stunnel.conf
