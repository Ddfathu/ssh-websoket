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

# Install socat untuk jembatan WebSocket murni (kebal segala payload)
apt-get update && apt-get install -y socat

echo "[*] Memulai OpenSSH Server di Port 22..."
/usr/sbin/sshd

echo "[*] Memulai Socat Gateway (Jembatan Pipa Murni untuk WebSocket)..."
# Socat stand-by di port 8888, tugasnya cuma ngorosin payload utuh ke SSH port 22
socat TCP-LISTEN:8888,fork,reuseaddr TCP:127.0.0.1:22 &

echo "[*] Membuat konfigurasi Stunnel Dual-Routing..."
# Di sini kuncinya agar SNI polosan aman dan WebSocket tembus
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-ssl-and-ws]
accept = 0.0.0.0:$MAIN_PORT
connect = 127.0.0.1:8888
cert = /etc/stunnel/stunnel.pem
EOF

echo "[*] Memulai Stunnel Multiplexer..."
exec stunnel /etc/stunnel/stunnel.conf
