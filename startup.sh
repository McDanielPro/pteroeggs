#!/bin/bash

# PteroVPN Startup Script
# Version: 1.0.0
# Author: PteroEggs

# Colors for output (optional, remove if causing issues)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Display welcome message
echo ""
echo "========================================="
echo "         PteroVPN Egg v1.0.0            "
echo "         Author: PteroEggs              "
echo "========================================="
echo ""

# Set configuration variables with defaults
CONFIG_NAME="${VPN_CONFIG_NAME:-pterovpn-client}"
VPN_PORT="${VPN_PORT:-1194}"
VPN_PROTOCOL="${VPN_PROTOCOL:-udp}"
VPN_DNS="${VPN_DNS:-8.8.8.8}"
VPN_SUBNET="${VPN_SUBNET:-10.8.0.0/24}"

CONFIG_DIR="/home/container/config"
CONFIG_FILE="${CONFIG_DIR}/${CONFIG_NAME}.ovpn"
LOG_DIR="/home/container/logs"

# Display configuration file info
echo "[INFO] VPN configuration will be saved as: ${CONFIG_NAME}.ovpn"
echo "[INFO] Full path: ${CONFIG_FILE}"
echo ""

# Create necessary directories
mkdir -p "${CONFIG_DIR}"
mkdir -p "${LOG_DIR}"

# Install required packages on first run
if [ ! -f "${CONFIG_DIR}/.installed" ]; then
    echo "[INFO] Installing required packages..."
    apt-get update
    apt-get install -y openvpn easy-rsa curl net-tools
    touch "${CONFIG_DIR}/.installed"
    echo "[INFO] Installation complete"
fi

# Check if config file exists, generate if not
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "[INFO] Generating new VPN configuration file..."
    
    # Determine server IP
    if [ -z "${SERVER_IP}" ] || [ "${SERVER_IP}" = "" ]; then
        SERVER_IP=$(curl -s --max-time 5 https://ipv4.icanhazip.com || echo "YOUR_SERVER_IP")
        echo "[INFO] Auto-detected server IP: ${SERVER_IP}"
        echo "[NOTE] If this shows YOUR_SERVER_IP, set the SERVER_IP environment variable"
    else
        echo "[INFO] Using configured server IP: ${SERVER_IP}"
    fi

    # Generate client configuration
    cat > "${CONFIG_FILE}" << EOF
# PteroVPN Client Configuration
# Generated: $(date)
# Server: ${SERVER_IP}
# Port: ${VPN_PORT}
# Protocol: ${VPN_PROTOCOL}

client
dev tun
proto ${VPN_PROTOCOL}
remote ${SERVER_IP} ${VPN_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
verb 3
keepalive 10 120
dhcp-option DNS ${VPN_DNS}
block-outside-dns

<ca>
# ==========================================
# Replace with your CA certificate
# Generate using: easy-rsa build-ca
# ==========================================
-----BEGIN CERTIFICATE-----
# Your CA certificate will go here
-----END CERTIFICATE-----
</ca>

<cert>
# ==========================================
# Replace with your client certificate
# Generate using: easy-rsa build-client-full client1
# ==========================================
-----BEGIN CERTIFICATE-----
# Your client certificate will go here
-----END CERTIFICATE-----
</cert>

<key>
# ==========================================
# Replace with your client private key
# Keep this secure and private!
# ==========================================
-----BEGIN PRIVATE KEY-----
# Your client private key will go here
-----END PRIVATE KEY-----
</key>
EOF

    echo "[SUCCESS] Configuration file generated: ${CONFIG_FILE}"
    echo "[SUCCESS] Download from: File Manager → config/${CONFIG_NAME}.ovpn"
    echo "[NOTE] This is a template. Replace certificates for production use."
    echo ""
    
    # Create README
    cat > "${CONFIG_DIR}/README.txt" << EOF
PteroVPN Setup Guide
====================

1. CONFIGURATION FILE: ${CONFIG_NAME}.ovpn
   Download this file and use with any OpenVPN client.

2. GENERATING CERTIFICATES:
   For production use, generate real certificates:
   
   cd /usr/share/easy-rsa
   ./easyrsa init-pki
   ./easyrsa build-ca
   ./easyrsa build-server-full server nopass
   ./easyrsa build-client-full client1 nopass
   
   Then copy:
   - pki/ca.crt to <ca> section
   - pki/issued/client1.crt to <cert> section  
   - pki/private/client1.key to <key> section

3. SERVER IP: ${SERVER_IP}
   If this shows "YOUR_SERVER_IP", set the SERVER_IP environment variable
   in your server settings to your actual public IP.

4. CONNECTION INFO:
   - Port: ${VPN_PORT}
   - Protocol: ${VPN_PROTOCOL}
   - DNS: ${VPN_DNS}
   - Subnet: ${VPN_SUBNET}

5. LOGS:
   Server logs: ${LOG_DIR}/openvpn.log
   Connection logs: ${LOG_DIR}/openvpn-status.log

Generated: $(date)
EOF
else
    echo "[INFO] Configuration file already exists."
fi

# Generate server configuration
SERVER_CONF="${CONFIG_DIR}/server.conf"
if [ ! -f "${SERVER_CONF}" ]; then
    echo "[INFO] Generating server configuration..."
    
    # Extract network and netmask from subnet
    NETWORK=$(echo "${VPN_SUBNET}" | cut -d'/' -f1)
    PREFIX=$(echo "${VPN_SUBNET}" | cut -d'/' -f2)
    
    cat > "${SERVER_CONF}" << EOF
# PteroVPN Server Configuration
port ${VPN_PORT}
proto ${VPN_PROTOCOL}
dev tun
ca ${CONFIG_DIR}/ca.crt
cert ${CONFIG_DIR}/server.crt
key ${CONFIG_DIR}/server.key
dh ${CONFIG_DIR}/dh.pem
server ${NETWORK} 255.255.255.0
ifconfig-pool-persist ${CONFIG_DIR}/ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${VPN_DNS}"
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status ${LOG_DIR}/openvpn-status.log
log-append ${LOG_DIR}/openvpn.log
verb 3
explicit-exit-notify 1
EOF
fi

# Generate sample certificates if not present
if [ ! -f "${CONFIG_DIR}/ca.crt" ]; then
    echo "[WARNING] No certificates found. Generating sample certificates for testing..."
    
    # Create sample certificates directory
    mkdir -p "${CONFIG_DIR}/sample-certs"
    
    # Generate sample CA
    openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
        -keyout "${CONFIG_DIR}/sample-certs/ca.key" \
        -out "${CONFIG_DIR}/sample-certs/ca.crt" \
        -subj "/C=US/ST=Sample/L=Test/O=PteroVPN/CN=Sample CA" 2>/dev/null || true
    
    # Copy sample certificates to main location
    cp "${CONFIG_DIR}/sample-certs/ca.crt" "${CONFIG_DIR}/ca.crt"
    
    # Generate sample server certificate
    openssl req -newkey rsa:2048 -sha256 -nodes \
        -keyout "${CONFIG_DIR}/server.key" \
        -out "${CONFIG_DIR}/server.csr" \
        -subj "/C=US/ST=Sample/L=Test/O=PteroVPN/CN=server" 2>/dev/null || true
    
    openssl x509 -req -in "${CONFIG_DIR}/server.csr" \
        -CA "${CONFIG_DIR}/sample-certs/ca.crt" \
        -CAkey "${CONFIG_DIR}/sample-certs/ca.key" \
        -CAcreateserial \
        -out "${CONFIG_DIR}/server.crt" \
        -days 365 2>/dev/null || true
    
    # Generate DH parameters
    openssl dhparam -out "${CONFIG_DIR}/dh.pem" 1024 2>/dev/null || true
    
    # Clean up
    rm -f "${CONFIG_DIR}/server.csr" "${CONFIG_DIR}/sample-certs/ca.srl" 2>/dev/null || true
    
    echo "[NOTE] Sample certificates generated for testing only."
    echo "[IMPORTANT] Replace with real certificates for production use!"
fi

echo ""
echo "========================================="
echo "[STARTUP] Starting VPN service..."
echo "========================================="
echo "[INFO] Server running on port: ${VPN_PORT}"
echo "[INFO] Protocol: ${VPN_PROTOCOL}"
echo "[INFO] DNS: ${VPN_DNS}"
echo "[INFO] Subnet: ${VPN_SUBNET}"
echo "[INFO] Logs: ${LOG_DIR}/openvpn.log"
echo "========================================="

# Start OpenVPN server
openvpn --config "${SERVER_CONF}" --daemon

# Wait a moment for OpenVPN to start
sleep 3

# Show initial logs
echo "[INFO] VPN Service started. Showing logs..."
echo ""

# Tail the log file
tail -f "${LOG_DIR}/openvpn.log"