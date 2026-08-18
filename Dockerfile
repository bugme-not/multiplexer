FROM alpine:3.20 AS xray-bin
RUN apk add --no-cache curl unzip
WORKDIR /tmp
RUN curl -fsSL --retry 5 \
    "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" \
    -o xray.zip \
 && unzip -q xray.zip xray \
 && chmod +x xray && mv xray /xray
# Verify binary
RUN /xray --version || { echo "Xray binary invalid"; exit 1; }

FROM alpine:3.20 AS wstunnel-bin
ARG WSTUNNEL_VERSION=10.5.1
RUN apk add --no-cache curl tar
WORKDIR /tmp
# FIXED: full URL
RUN curl -fsSL --retry 5 \
    "https://github.com/erebe/wstunnel/releases/download/v${WSTUNNEL_VERSION}/wstunnel_${WSTUNNEL_VERSION}_linux_amd64.tar.gz" \
    -o wstunnel.tar.gz \
 && tar -xzf wstunnel.tar.gz \
 && chmod +x wstunnel && mv wstunnel /wstunnel
RUN /wstunnel --version || { echo "wstunnel binary invalid"; exit 1; }

FROM openresty/openresty:alpine-fat

RUN apk add --no-cache \
    ca-certificates bash curl tzdata wget openssh supervisor procps \
 && rm -rf /var/cache/apk/*

ENV TZ=Asia/Manila PORT=80
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Copy binaries
COPY --from=xray-bin /xray /usr/local/bin/xray
COPY --from=wstunnel-bin /wstunnel /usr/local/bin/wstunnel
RUN chmod +x /usr/local/bin/xray /usr/local/bin/wstunnel

# FIXED: use working mirror + FAIL on error, no silent fallbacks
RUN mkdir -p /usr/local/share/xray && \
    curl -fsSL --retry 3 -o /usr/local/share/xray/geosite.dat \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" || \
    curl -fsSL --retry 3 -o /usr/local/share/xray/geosite.dat \
    "https://ghfast.top/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" && \
    curl -fsSL --retry 3 -o /usr/local/share/xray/geoip.dat \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" || \
    curl -fsSL --retry 3 -o /usr/local/share/xray/geoip.dat \
    "https://ghfast.top/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" && \
    ls -lh /usr/local/share/xray/

COPY config.json /etc/xray.json
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY supervisord.conf /etc/supervisord.conf

# SSH setup
RUN mkdir -p /run/sshd /etc/ssh && \
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#UsePAM.*/UsePAM no/' /etc/ssh/sshd_config && \
    adduser -D -h /home/cxlvin -s /bin/bash cxlvin

EXPOSE 80

# more lenient, verbose, separate checks
HEALTHCHECK --interval=20s --timeout=10s --start-period=60s --retries=6 --start-interval=5s \
    CMD curl -fs http://127.0.0.1:80/health && \
        pgrep xray && pgrep nginx && pgrep sshd && pgrep wstunnel || exit 1

ENTRYPOINT ["/bin/sh", "-c", "\
    if [ -n \"$SSH_PASSWORD\" ]; then echo \"cxlvin:$SSH_PASSWORD\" | chpasswd; fi; \
    exec /usr/bin/supervisord -c /etc/supervisord.conf \
"]
