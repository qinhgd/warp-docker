#!/bin/bash
set -e

# 1. 确保 TUN 设备可用
if [ ! -e /dev/net/tun ]; then
    sudo mkdir -p /dev/net
    sudo mknod /dev/net/tun c 10 200
    sudo chmod 600 /dev/net/tun
fi

# 2. 启动 DBUS 和 WARP 服务
sudo mkdir -p /run/dbus
[ -f /run/dbus/pid ] && sudo rm /run/dbus/pid
sudo dbus-daemon --config-file=/usr/share/dbus-1/system.conf
sudo warp-svc --accept-tos &
sleep "${WARP_SLEEP:-2}"

# 3. 注册与连接逻辑
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
    warp-cli --accept-tos registration new
    [ -n "$WARP_LICENSE_KEY" ] && warp-cli --accept-tos registration license "$WARP_LICENSE_KEY"
    warp-cli --accept-tos mode proxy
    warp-cli --accept-tos connect
else
    echo "Using existing registration..."
    warp-cli --accept-tos connect
fi

# 4. NAT 模式增强 (支持 ICMP/UDP 转发)
if [ -n "$WARP_ENABLE_NAT" ]; then
    echo "[NAT] Enabling NAT Mode..."
    warp-cli --accept-tos mode warp
    sleep "$WARP_SLEEP"
    sudo nft flush ruleset
    sudo nft add table ip nat
    sudo nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
    sudo nft add rule ip nat postrouting oifname "CloudflareWARP" masquerade
    # 修复大包 MTU 问题
    sudo nft add table ip filter
    sudo nft add chain ip filter forward { type filter hook forward priority 0 \; policy accept \; }
    sudo nft add rule ip filter forward tcp flags syn tcp option maxseg size set rt mtu
fi

# 5. 启动 GOST V3
echo "Running GOST V3: $GOST_ARGS"
exec gost $GOST_ARGS
