FROM ubuntu:22.04

# Mengatur agar proses instalasi berjalan otomatis tanpa interaksi prompt
ENV DEBIAN_FRONTEND=noninteractive

# Install seluruh paket modern yang dibutuhkan (Dropbear, HAProxy, Stunnel4, OpenSSL, Sudo)
RUN apt-get update && apt-get install -y \
    openssh-server \
    dropbear \
    haproxy \
    stunnel4 \
    openssl \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Membuat semua direktori runtime sistem agar tidak terjadi error saat start
RUN mkdir -p /var/run/sshd /var/run/stunnel /var/run/dropbear /var/lib/haproxy

# Membuat SSL Certificate (Self-Signed) untuk pintu depan Stunnel
RUN openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=ModernTunnel/CN=localhost" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem

# Salin script entrypoint utama ke dalam kontainer
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose Port publik 8080 sesuai dengan port internal utama Railway
EXPOSE 8080

# Jalankan skrip konfigurasi saat kontainer pertama kali dinyalakan
ENTRYPOINT ["/entrypoint.sh"]
