# 使用更轻量的 Debian Bookworm Slim 镜像
ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE}

ARG WARP_VERSION
# 指定 GOST V3 的版本
ARG GOST_VERSION=3.0.0-rc10
ARG COMMIT_SHA
ARG TARGETPLATFORM

LABEL org.opencontainers.image.authors="cmj2002"
LABEL org.opencontainers.image.url="https://github.com/cmj2002/warp-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL GOST_VERSION=${GOST_VERSION}

# 预设工作目录
WORKDIR /home/warp

COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

# 安装依赖并处理 GOST V3
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y curl gnupg lsb-release sudo jq ipcalc procps ca-certificates && \
    # 安装 Cloudflare WARP
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    # 处理不同架构的 GOST V3 下载
    case ${TARGETPLATFORM} in \
      "linux/amd64")   export ARCH="amd64" ;; \
      "linux/arm64")   export ARCH="arm64" ;; \
      *) echo "Unsupported TARGETPLATFORM: ${TARGETPLATFORM}" && exit 1 ;; \
    esac && \
    FILE_NAME="gost_${GOST_VERSION}_linux_${ARCH}.tar.gz" && \
    curl -LO "https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/${FILE_NAME}" && \
    tar -xzf ${FILE_NAME} -C /usr/bin/ gost && \
    rm -f ${FILE_NAME} && \
    # 权限设置
    chmod +x /usr/bin/gost && \
    chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    # 清理缓存
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    # 创建用户
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

USER warp

# 接受 Cloudflare WARP 服务条款
RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

# --- 关键环境变量配置 ---
# 使用 SOCKS5 并开启 UDP 转发 (?udp=true)
ENV GOST_ARGS="-L socks5://:1080?udp=true"
ENV WARP_SLEEP=2
ENV WARP_ENABLE_NAT=0

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
