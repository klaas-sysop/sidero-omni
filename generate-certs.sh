#!/bin/bash

#############################################################################
# Helper Script - Generate SSL Certificates
# Source: Called from docker-entrypoint.sh
#############################################################################

set -e

DOMAIN_NAME="${1:-example.com}"
EMAIL="${2:-admin@example.com}"
CLOUDFLARE_API_TOKEN="${3:-}"
CLOUDFLARE_ZONE_ID="${4:-}"
CERTS_DIR="${5:-/etc/omni/tls}"

log_info() {
    echo "[CERT-GEN] ℹ $1"
}

log_success() {
    echo "[CERT-GEN] ✓ $1"
}

log_error() {
    echo "[CERT-GEN] ✗ $1"
}

# Validate inputs
if [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL" ]; then
    log_error "Usage: $0 <domain> <email> <cf_token> <cf_zone_id> [certs_dir]"
    exit 1
fi

# Check if already exists
if [ -f "$CERTS_DIR/tls.crt" ] && [ -f "$CERTS_DIR/tls.key" ]; then
    log_info "Certificates already exist"
    exit 0
fi

# Create certs directory
mkdir -p "$CERTS_DIR"

# Use Cloudflare if credentials provided
if [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ZONE_ID" ]; then
    log_info "Generating certificate via Cloudflare DNS..."
    
    creds_file="/tmp/cloudflare.ini"
    cat > "$creds_file" << EOF
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOF
    chmod 600 "$creds_file"
    
    if certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$creds_file" \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --domain "$DOMAIN_NAME" \
        --quiet; then
        
        cp "/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem" "$CERTS_DIR/tls.crt"
        cp "/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem" "$CERTS_DIR/tls.key"
        rm "$creds_file"
        log_success "Certificates generated successfully"
        exit 0
    else
        log_error "Certificate generation failed"
        rm "$creds_file"
        exit 1
    fi
else
    # Fallback to self-signed
    log_info "Generating self-signed certificate..."
    
    openssl req -x509 -newkey rsa:2048 -keyout "$CERTS_DIR/tls.key" \
        -out "$CERTS_DIR/tls.crt" -days 365 -nodes \
        -subj "/CN=$DOMAIN_NAME" 2>/dev/null
    
    log_success "Self-signed certificate created"
    exit 0
fi
