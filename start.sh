#!/bin/bash
set -e

# Allow input from vpn network on ports 8081 and 5001
ufw allow from 10.0.0.0/24 to any port 8081 proto tcp || true
ufw allow from 10.0.0.0/24 to any port 5001 proto tcp || true

# Generate wireguard keys and config if environment variables are provided
if [ -n "$WIREGUARD_SERVER_PUBLIC_KEY" ] && [ -n "$WIREGUARD_SERVER_IP" ]; then
    # Create directory if it doesn't exist
    mkdir -p /data/wireguard-configs
    
    # Generate keys only if client_public.key doesn't exist or is empty
    if [ ! -s /data/wireguard-configs/client_public.key ]; then
        wg genkey | tee /data/wireguard-configs/client_private.key | wg pubkey > /data/wireguard-configs/client_public.key
        chmod 600 /data/wireguard-configs/client_private.key
        chmod 644 /data/wireguard-configs/client_public.key
    fi
    
    # Read keys
    CLIENT_PRIVATE_KEY=$(cat /data/wireguard-configs/client_private.key)
    CLIENT_PUBLIC_KEY=$(cat /data/wireguard-configs/client_public.key)
    
    # Generate wireguard config
    cat > /etc/wireguard/wg-client.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.0.0.2/24

[Peer]
PublicKey = $WIREGUARD_SERVER_PUBLIC_KEY
Endpoint = $WIREGUARD_SERVER_IP:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF
    
    chmod 600 /etc/wireguard/wg-client.conf
    
    # Start wireguard
    wg-quick up wg-client || true
fi

# Start nginx in background
nginx &
NGINX_PID=$!

# Wait a moment for nginx to start
sleep 1

# Start the original mlnode service (uvicorn) - this will be the main process
exec uvicorn api.app:app --host=0.0.0.0 --port=8080

