#!/bin/sh
set -e

# Build base command arguments
set -- \
  --account-id="${OMNI_ACCOUNT_UUID}" \
  --name="${OMNI_NAME:-onprem-omni}" \
  --private-key-source=file:///omni.asc \
  --sqlite-storage-path=/_out/sqlite/omni.db \
  --event-sink-port=8091 \
  --bind-addr=0.0.0.0:8080 \
  --machine-api-bind-addr=0.0.0.0:8090 \
  --k8s-proxy-bind-addr=0.0.0.0:8100 \
  --advertised-api-url="https://${OMNI_DOMAIN_NAME}/" \
  --machine-api-advertised-url="https://${OMNI_DOMAIN_NAME}:8090/" \
  --siderolink-wireguard-advertised-addr="${OMNI_WG_IP}:50180" \
  --advertised-kubernetes-proxy-url="https://${OMNI_DOMAIN_NAME}:8100/" \
  --auth-auth0-enabled="${AUTH0_ENABLED:-true}" \
  --auth-auth0-domain="${AUTH0_DOMAIN}" \
  --auth-auth0-client-id="${AUTH0_CLIENT_ID}" \
  --initial-users="${OMNI_ADMIN_EMAIL}"

# Add TLS configuration only if not in reverse proxy mode
if [ "${REVERSE_PROXY_MODE:-false}" != "true" ]; then
  if [ -f /tls.crt ] && [ -f /tls.key ]; then
    set -- "$@" \
      --cert=/tls.crt \
      --key=/tls.key \
      --machine-api-cert=/tls.crt \
      --machine-api-key=/tls.key
  fi
fi

# Execute Omni - the binary should be in PATH from the container's default setup
exec omni "$@"

