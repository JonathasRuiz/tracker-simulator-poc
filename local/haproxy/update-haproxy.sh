#!/bin/sh

SOCKET="/var/run/haproxy/admin.sock"
HTTP_MAP="/tmp/hosts-http.map"
GRPC_MAP="/tmp/hosts-grpc.map"
MAX_SLOTS=10

apply_backend_map() {
    backend="$1"
    map_file="$2"
    i=1

    if [ -f "$map_file" ]; then
        entries=$(cat "$map_file")
    else
        entries=""
    fi

    for full_addr in $entries; do
        IP=${full_addr%:*}
        PORT=${full_addr#*:}

        echo "Setting $backend slot s$i to IP: $IP Port: $PORT"
        echo "set server $backend/s$i addr $IP port $PORT" | socat stdio "$SOCKET"
        echo "enable server $backend/s$i" | socat stdio "$SOCKET"

        i=$((i+1))
        if [ "$i" -gt "$MAX_SLOTS" ]; then
            break
        fi
    done

    while [ "$i" -le "$MAX_SLOTS" ]; do
        echo "disable server $backend/s$i" | socat stdio "$SOCKET"
        i=$((i+1))
    done
}

# 1. Wait for Socket (Keep this, it's working!)
echo "Checking for HAProxy socket..."
while [ ! -S "$SOCKET" ]; do
    echo "Socket not found yet. Waiting 1s..."
    sleep 1
done

# 2. Apply discovered service lists independently
apply_backend_map "http-backend" "$HTTP_MAP"
apply_backend_map "grpc-backend" "$GRPC_MAP"