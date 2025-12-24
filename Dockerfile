# --- 第一阶段：提取器 ---
FROM alpine:latest AS fetcher
ARG GOST_VERSION=3.0.0-rc10
ARG TARGETPLATFORM

RUN apk add --no-cache curl tar binutils

WORKDIR /tmp
RUN case "${TARGETPLATFORM}" in \
      "linux/amd64") ARCH="amd64" ;; \
      "linux/arm64") ARCH="arm64" ;; \
    esac && \
    # 下载并提取 GOST V3
    curl -LO "https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_${ARCH}.tar.gz" && \
    tar -xzf "gost_${GOST_VERSION}_linux_${ARCH}.tar.gz" gost && \
    # 从 Debian 官方提取 WARP 二进制文件 (Alpine 运行 glibc 程序需要提取)
    WARP_ARCH=$(echo ${ARCH} | sed 's/arm64/arm64/' | sed 's/amd64/amd64/') && \
    curl -LO https://pkg.cloudflareclient.com/pool/bookworm/main/c/cloudflare-warp/cloudflare-warp_2024.11.311-1_${WARP_ARCH}.deb && \
    ar x *.deb data.tar.xz && \
    tar -xJf data.tar.xz ./usr/bin/warp-svc ./usr/bin/warp-cli

# --- 第二阶段：最终运行环境 ---
FROM alpine:latest

# 安装 Alpine 下运行 glibc 程序必须的最小兼容层
RUN apk add --no-cache gcompat libstdc++ ca-certificates dbus sudo bash nftables iproute2 tzdata

# 拷贝核心程序
COPY --from=fetcher /tmp/gost /usr/bin/gost
COPY --from=fetcher /tmp/usr/bin/warp-svc /usr/bin/warp-svc
COPY --from=fetcher /tmp/usr/bin/warp-cli /usr/bin/warp-cli

# 拷贝你的启动脚本
COPY entrypoint.sh /entrypoint.sh

# 权限与用户设置
RUN chmod +x /usr/bin/gost /usr/bin/warp-* /entrypoint.sh && \
    adduser -D -u 1000 warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

USER warp
WORKDIR /home/warp

# 预接受 TOS 并设置环境变量
RUN mkdir -p /home/warp/.local/share/warp && echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt
ENV GOST_ARGS="-L socks5://:1080?udp=true"
ENV WARP_SLEEP=2

ENTRYPOINT ["/entrypoint.sh"]
