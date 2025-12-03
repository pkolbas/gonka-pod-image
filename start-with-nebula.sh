#!/bin/bash
set -e

# CLIENT_ID: "01".."99"
if [[ ! "$CLIENT_ID" =~ ^[0-9]{2}$ ]]; then
    echo "CLIENT_ID must be a two-digit number between 01 and 99." >&2
    exit 1
fi

CLIENT_ID_NUM=$((10#$CLIENT_ID))
if [ "$CLIENT_ID_NUM" -lt 1 ] || [ "$CLIENT_ID_NUM" -gt 99 ]; then
    echo "CLIENT_ID must be between 01 and 99." >&2
    exit 1
fi

if [ -z "$NEBULA_LH_HOST" ] || [ -z "$NEBULA_LH_PORT" ]; then
    echo "Missing Nebula configuration: NEBULA_LH_HOST and NEBULA_LH_PORT are required." >&2
    exit 1
fi

# Проверим наличие сертификатов (монтируются как bind)
for f in /etc/nebula/ca.crt /etc/nebula/host.crt /etc/nebula/host.key; do
  if [ ! -f "$f" ]; then
    echo "Nebula PKI file missing: $f" >&2
    exit 1
  fi
done

NEBULA_IP="10.0.0.${CLIENT_ID_NUM}"
NEBULA_NAME="${NEBULA_NAME:-ml-node-${CLIENT_ID}}"

echo "Writing /etc/nebula/config.yml for Nebula client..."
cat > /etc/nebula/config.yml <<EOF
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/host.crt
  key: /etc/nebula/host.key

static_host_map:
  "10.0.0.100":
    - "${NEBULA_LH_HOST}:${NEBULA_LH_PORT}"

lighthouse:
  am_lighthouse: false
  hosts:
    - "10.0.0.100"

listen:
  host: 0.0.0.0
  port: 0

tun:
  disabled: false
  dev: nebula1
  drop_local_broadcast: true
  drop_multicast: true

firewall:
  conntrack:
    tcp_timeout: 12m
    udp_timeout: 3m
    default_timeout: 10m
  outbound:
    - port: any
      proto: any
      host: any
  inbound:
    - port: any
      proto: any
      host: any

handshakes:
  try_interval: 1s
  retries: 20

# Просто для читаемости логов
stats:
  metrics: false
EOF

echo "Starting Nebula client..."
nebula -config /etc/nebula/config.yml &
NEBULA_PID=$!

# Start nginx in background
nginx &
NGINX_PID=$!

# Wait a moment for nginx to start
sleep 1

echo "Creating user and group 'appuser' and 'appgroup'..."
HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1001}

if ! getent group appgroup >/dev/null; then
  echo "Creating group 'appgroup'"
  groupadd -g "$HOST_GID" appgroup
else
  echo "Group 'appgroup' already exists"
fi

if ! id -u appuser >/dev/null 2>&1; then
  echo "Creating user 'appuser'"
  useradd -m -u "$HOST_UID" -g appgroup appuser
else
  echo "User 'appuser' already exists"
fi

echo "Starting uvicorn application..."
source /app/packages/api/.venv/bin/activate
exec uvicorn api.app:app --host=0.0.0.0 --port=8080
