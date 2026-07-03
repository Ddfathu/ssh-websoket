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

echo "[*] Menginstall Dropbear & HAProxy (Low-Level Multiplexer)..."
apt-get update && apt-get install -y dropbear haproxy

echo "[*] Memulai Dropbear pada Port Lokal 222..."
# Dropbear dijalankan tanpa banner agar hemat buffer data
dropbear -F -E -p 127.0.0.1:222 &

echo "[*] Mengonfigurasi HAProxy Pure TCP Pipelining..."
# HAProxy diatur pada mode tcp (Layer 4) agar kebal terhadap payload HTTP yang ditumpuk-tumpuk
cat << 'EOF' > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0

defaults
    log     global
    mode    tcp
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend ssl_and_ws_front
    bind 127.0.0.1:8888
    mode tcp
    # Inspeksi byte awal: jika ada indikasi HTTP request atau payload WebSocket, 
    # langsung oper ke backend ws tanpa membaca isi text-nya secara detail.
    tcp-request inspect-delay 5s
    tcp-request content accept if HTTP
    
    default_backend dropbear_backend

backend dropbear_backend
    mode tcp
    # Salurkan seluruh data mentah (termasuk paket GET + PATCH) secara utuh langsung ke Dropbear
    server ssh_srv 127.0.0.1:222 maxconn 1000
EOF

echo "[*] Memulai HAProxy..."
haproxy -f /etc/haproxy/haproxy.cfg &

echo "[*] Membuat konfigurasi Stunnel Gateway..."
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-haproxy-gateway]
accept = 0.0.0.0:$MAIN_PORT
connect = 127.0.0.1:8888
cert = /etc/stunnel/stunnel.pem
EOF

echo "[*] Memulai Stunnel Multiplexer..."
exec stunnel /etc/stunnel/stunnel.conf
