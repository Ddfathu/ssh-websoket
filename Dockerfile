FROM ubuntu:22.04

# Mengatur agar instalasi berjalan otomatis tanpa pop-up prompt
ENV DEBIAN_FRONTEND=noninteractive

# Install semua dependensi (Termasuk OpenSSH, Dropbear, Stunnel, dan Python3)
RUN apt-get update && apt-get install -y \
    openssh-server \
    dropbear \
    stunnel4 \
    openssl \
    python3 \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Membuat direktori runtime yang dibutuhkan oleh SSH dan Stunnel
RUN mkdir /var/run/sshd /var/run/stunnel /var/run/dropbear

# Membuat SSL Certificate otomatis untuk Stunnel Front-Gateway
RUN openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=RailwaySSH/CN=localhost" \
    -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem

# Salin script entrypoint utama ke dalam kontainer
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose Port 8080 sesuai port bawaan utama Railway
EXPOSE 8080

# Jalankan entrypoint saat kontainer dimulai
ENTRYPOINT ["/entrypoint.sh"]
