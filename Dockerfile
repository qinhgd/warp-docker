ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

ARG GOST_VERSION=3.0.0-rc10
ARG TARGETPLATFORM

# 标签信息
LABEL org.opencontainers.image.authors="your_name"
LABEL org.opencontainers.image.description="WARP with GOST V3 on Debian Slim"

# 复制脚本
COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

# 安装依赖
RUN apt-get update && \
    apt-get install -y curl gnupg lsb-release sudo jq ipcalc procps ca-certificates nftables && \
    # 安装 Cloudflare WARP
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    # 架构适配并下载 GOST V3
    case ${TARGETPLATFORM} in \
      "linux/amd64")   export ARCH="amd64" ;; \
      "linux/arm64")   export ARCH="arm64" ;; \
      *) echo "Unsupported TARGETPLATFORM: ${TARGETPLATFORM}" && exit 1 ;; \
    esac && \
    FILE_NAME="gost_${GOST_VERSION}_linux_${ARCH}.tar.gz" && \
    curl -LO "https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/${FILE_NAME}" && \
    tar -xzf ${FILE_NAME} -C /usr/bin/ gost && \
    rm -f ${FILE_NAME} && \
    # 权限与用户设置
    chmod +x /usr/bin/gost /entrypoint.sh /healthcheck/index.sh && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp && \
    # 清理
    apt-get clean && rm -rf /var/lib/apt/lists/*

USER warp
# 预接受 TOS
RUN mkdir -p /home/warp/.local/share/warp && echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

# 默认 V3 参数：支持 UDP
ENV GOST_ARGS="-L socks5://:1080?udp=true"
ENV WARP_SLEEP=2

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
