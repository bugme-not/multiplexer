# Builder stage: Xray
FROM alpine:3.20 AS xray-bin
RUN apk add --no-cache curl unzip
WORKDIR /tmp
RUN curl -L --retry 3 "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" -o xray.zip \
 && unzip -q xray.zip xray \
 && chmod +x xray && mv xray /xray && rm xray.zip

# Final image: OpenResty + Xray + SSH + Supervisor
FROM openresty/openresty:alpine-fat

# Install ALL deps in one layer
RUN apk add --no-cache \
    ca-certificates bash curl tzdata wget \
    openssh supervisor \
    && rm -rf /var/cache/apk/*

# Timezone
ENV TZ=Asia/Manila
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Xray binary from builder
COPY --from=xray-bin /xray /usr/local/bin/xray
RUN chmod +x /usr/local/bin/xray

# Geodata — cached layer
RUN mkdir -p /usr/local/share/xray \
 && wget -qO /usr/local/share/xray/geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
 || wget -qO /usr/local/share/xray/geosite.dat "https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
 && wget -qO /usr/local/share/xray/geoip.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
 || wget -qO /usr/local/share/xray/geoip.dat "https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"

# Configs
COPY config.json /etc/xray.json
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY supervisord.conf /etc/supervisord.conf

# --- SSH SETUP — CREDENTIALS FROM ENV, NOT BAKED IN ---
RUN mkdir -p /run/sshd /etc/ssh
RUN sed -i 's/#PermitRootLogin/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Create user — password set at RUNTIME via entrypoint
RUN adduser -D -h /home/cxlvin -s /bin/bash cxlvin

EXPOSE 22 8080

# Health check — NOW checks BOTH services
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
CMD wget -qO- http://[::1]:8080/health && pgrep xray && pgrep sshd || exit 1

# Entrypoint: SETS PASSWORD FROM ENV → NEVER IN IMAGE
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
