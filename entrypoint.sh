#!/bin/bash

# exit when any command fails
set -e

# create a tun device if not exist
if [ ! -e /dev/net/tun ]; then
    sudo mkdir -p /dev/net
    sudo mknod /dev/net/tun c 10 200
    sudo chmod 600 /dev/net/tun
fi

# start dbus
sudo mkdir -p /run/dbus
if [ -f /run/dbus/pid ]; then
    sudo rm /run/dbus/pid
fi
sudo dbus-daemon --config-file=/usr/share/dbus-1/system.conf

# start the daemon
sudo warp-svc --accept-tos &

# sleep to wait for the daemon to start, default 2 seconds
sleep "${WARP_SLEEP:-2}"

# 如果 reg.json 不存在，则进行初始化
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
    if [ ! -f /var/lib/cloudflare-warp/mdm.xml ] || [ -n "$REGISTER_WHEN_MDM_EXISTS" ]; then
        warp-cli --accept-tos registration new && echo "Warp client registered!"
        if [ -n "$WARP_LICENSE_KEY" ]; then
            echo "License key found, registering license..."
            warp-cli --accept-tos registration license "$WARP_LICENSE_KEY" && echo "Warp license registered!"
        fi
    fi
    # 默认使用代理模式，除非开启了 NAT
    if [ -z "$WARP_ENABLE_NAT" ]; then
        warp-cli --accept-tos mode proxy
    fi
    warp-cli --accept-tos connect
else
    echo "Warp client already registered, skip registration"
    # 确保连接状态
    warp-cli --accept-tos connect
fi

# 性能优化：关闭 qlog
warp-cli --accept-tos debug qlog disable

# --- NAT 模式增强 (支持 ICMP 和全局流量) ---
if [ -n "$WARP_ENABLE_NAT" ]; then
    echo "[NAT] Switching to warp mode..."
    warp-cli --accept-tos mode warp
    sleep "$WARP_SLEEP"

    echo "[NAT] Configuring nftables for UDP/ICMP..."
    # 清理并设置 nftables
    sudo nft flush ruleset
    sudo nft add table ip nat
    sudo nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
    sudo nft add rule ip nat postrouting oifname "CloudflareWARP" counter masquerade
    
    # 关键：MSS 锁定，防止大包丢包（对 UDP/ICMP 稳定很重要）
    sudo nft add table ip filter
    sudo nft add chain ip filter forward { type filter hook forward priority 0 \; policy accept \; }
    sudo nft add rule ip filter forward tcp flags syn tcp option maxseg size set rt mtu
fi

# --- 启动 GOST V3 ---
# 提示：GOST V3 如果 GOST_ARGS 为空，我们要给它一个默认的 V3 格式
if [ -z "$GOST_ARGS" ]; then
    # V3 格式：开启 SOCKS5 并支持 UDP
    export GOST_ARGS="-L socks5://:1080?udp=true"
fi

echo "Starting GOST V3 with: $GOST_ARGS"
# 使用 exec 替换 shell 进程，让 gost 接收系统信号
exec gost $GOST_ARGS
