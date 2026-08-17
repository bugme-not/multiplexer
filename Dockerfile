FROM alpine:3.20 AS xray-bin

RUN apk add --no-cache \
    curl \
    unzip \
    ca-certificates \
    bash

WORKDIR /app

RUN curl -L --retry 3 "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" -o xray.zip \
    || curl -L --retry 3 "https://ghproxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" -o xray.zip \
    && unzip xray.zip \
    && chmod +x xray \
    && mv xray /usr/local/bin/xray \
    && rm -f xray.zip

FROM openresty/openresty:alpine-fat

RUN apk add --no-cache \
    ca-certificates \
    bash \
    curl \
    tzdata \
    wget

RUN mkdir -p /usr/local/share/xray \
    && wget -qO /usr/local/share/xray/geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
    || wget -qO /usr/local/share/xray/geosite.dat "https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
    && wget -qO /usr/local/share/xray/geoip.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
    || wget -qO /usr/local/share/xray/geoip.dat "https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"

COPY --from=xray-bin /usr/local/bin/xray /usr/local/bin/xray

COPY config.json /etc/xray.json
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

RUN chmod +x /usr/local/bin/xray

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
CMD wget -qO- http://[::1]:8080/health || exit 1

CMD /usr/local/bin/xray run -c /etc/xray.json & \
    sleep 5 && \
    exec /usr/local/openresty/bin/openresty -g 'daemon off;'
