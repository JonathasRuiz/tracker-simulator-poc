#!/bin/sh

set -eu

# Keep backend slots warm in case HAProxy restarts and loses runtime socket state.
while true; do
  /bin/sh /etc/consul-templates/update-haproxy.sh || true
  sleep 5
done &

exec consul-template \
  -consul-addr=consul:8500 \
  -template="/etc/consul-templates/hosts.ctmpl:/tmp/hosts-http.map:/bin/sh /etc/consul-templates/update-haproxy.sh" \
  -template="/etc/consul-templates/hosts-grpc.ctmpl:/tmp/hosts-grpc.map:/bin/sh /etc/consul-templates/update-haproxy.sh"
