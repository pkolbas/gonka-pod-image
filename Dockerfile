FROM ghcr.io/product-science/mlnode:3.0.10

# Install nginx, wireguard and related tools
RUN apt update && \
    apt install -y nginx wireguard wireguard-tools iptables resolvconf ufw && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# Configure nginx (single container version)
COPY nginx-single.conf /etc/nginx/nginx.conf

# Set up wireguard directories
RUN chmod 700 /etc/wireguard && \
    mkdir -p /data/wireguard-configs

# Copy start script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose ports
EXPOSE 8081 5001

# Use start script as entrypoint
ENTRYPOINT ["/start.sh"]

