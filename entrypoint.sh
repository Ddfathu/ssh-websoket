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

echo "[*] Menginstall Dropbear & Nginx..."
apt-get update && apt-get install -y dropbear nginx

echo "[*] Memulai Dropbear di Port Lokal 222..."
dropbear -F -E -p 127.0.0.1:222 &

echo "[*] Mengonfigurasi Nginx Reverse Proxy..."
# Nginx dikonfigurasi untuk menerima reverse-proxy dari Cloudflare & Railway tanpa memotong payload
cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8888;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:222;
        proxy_http_version 1.1;
        
        # Teruskan semua header WebSocket utuh tanpa memodifikasi string
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        
        # Buffer besar agar payload GET+PATCH abang tidak terpotong (Anti 400/520)
        proxy_buffers 8 16k;
        proxy_buffer_size 32k;
        
        # Timeout panjang agar tidak gampang disconnect
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF

echo "[*] Memulai Nginx..."
service nginx start

echo "[*] Membuat konfigurasi Stunnel Gateway..."
cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
foreground = yes
debug = 4

[ssh-nginx]
accept = 0.0.0.0:$MAIN_PORT
connect = 127.0.0.1:8888
cert = /etc/stunnel/stunnel.pem
EOF

echo "[*] Memulai Stunnel Gateway..."
exec stunnel /etc/stunnel/stunnel.conf
