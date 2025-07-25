#!/bin/bash

set -e

# This script installs WireGuard, configures a basic server, enables IP forwarding,
# and creates a client configuration file. It assumes Ubuntu/Debian and requires root privileges.
# Run with sudo if not root.

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

# Update and install WireGuard
apt update
apt install -y wireguard

# Create WireGuard directory if it doesn't exist
mkdir -p /etc/wireguard
cd /etc/wireguard

# Set umask for secure key generation
umask 077

# Generate server keys
wg genkey | tee server.private | wg pubkey > server.public
SERVER_PRIV=$(cat server.private)
SERVER_PUB=$(cat server.public)

# Prompt for server public IP (endpoint for clients)
read -p "Enter the server's public IP address: " PUBLIC_IP

# Prompt for outgoing network interface (for NAT), default to eth0
read -p "Enter the outgoing network interface (default: eth0): " OUT_IF
OUT_IF=${OUT_IF:-eth0}

# Create server configuration file
cat <<EOF > wg0.conf
[Interface]
Address = 10.0.0.1/24
SaveConfig = true
PrivateKey = $SERVER_PRIV
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $OUT_IF -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $OUT_IF -j MASQUERADE
EOF

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Bring up the WireGuard interface
wg-quick up wg0

# Enable the service to start on boot
systemctl enable wg-quick@wg0

# Generate client keys
wg genkey | tee client.private | wg pubkey > client.public
CLIENT_PRIV=$(cat client.private)
CLIENT_PUB=$(cat client.public)

# Add client as a peer to the server
wg set wg0 peer "$CLIENT_PUB" allowed-ips 10.0.0.2/32

# Create client configuration file
cat <<EOF > client.conf
[Interface]
PrivateKey = $CLIENT_PRIV
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUB
AllowedIPs = 0.0.0.0/0
Endpoint = $PUBLIC_IP:51820
PersistentKeepalive = 25
EOF

echo "WireGuard server configured. Client config created at /etc/wireguard/client.conf"
echo "Remember to open UDP port 51820 on your firewall (e.g., ufw allow 51820/udp)."
