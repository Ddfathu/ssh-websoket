FROM ubuntu:22.04

# Mengatur agar instalasi berjalan otomatis tanpa pop-up prompt interaktif
ENV DEBIAN_FRONTEND=noninteractive

# Install semua paket esensial (Termasuk OpenSSH, Dropbear, Stunnel4, Nginx, dan Python3)
RUN apt-get update && apt-get install -y \
    openssh-server \
    dropbear \
    stunnel4 \
    openssl \
    python3 \
    nginx \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Membuat semua direktori runtime yang dibutuhkan oleh sistem
RUN mkdir -p /var/run/sshd /var/run/stunnel /var/run/dropbear

# Membuat SSL Certificate otomatis untuk Stunnel Front-Gateway agar Railway menerima koneksi
RUN openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=RailwaySSH/CN=localhost" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem

# Salin script entrypoint utama ke direktori root kontainer
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose Port 8080 sesuai port alokasi publik utama di Railway
EXPOSE 8080

# Jalankan entrypoint utama sebagai proses awal kontainer dimulai
ENTRYPOINT ["/entrypoint.sh"]
