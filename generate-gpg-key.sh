#!/bin/bash

#############################################################################
# Helper Script - Generate GPG Key for Etcd Encryption
# Source: Called from docker-entrypoint.sh
#############################################################################

set -e

OUTPUT_FILE="${1:-/etc/omni/tls/omni.asc}"

log_info() {
    echo "[GPG-GEN] ℹ $1"
}

log_success() {
    echo "[GPG-GEN] ✓ $1"
}

log_error() {
    echo "[GPG-GEN] ✗ $1"
}

# Create output directory
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Check if already exists
if [ -f "$OUTPUT_FILE" ]; then
    log_info "GPG key already exists"
    exit 0
fi

log_info "Generating GPG key for etcd encryption..."

# Ensure gpg-agent is running
gpgconf --launch gpg-agent 2>/dev/null || true

# Generate key
if gpg --batch --generate-key << EOF 2>/dev/null
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Omni
Name-Email: omni-etcd@local
Expire-Date: 0
EOF
then
    # Export the key
    if gpg --export-secret-key --armor "omni-etcd@local" > "$OUTPUT_FILE" 2>/dev/null; then
        chmod 600 "$OUTPUT_FILE"
        log_success "GPG key generated and exported"
        exit 0
    else
        log_error "Failed to export GPG key"
        exit 1
    fi
else
    log_error "Failed to generate GPG key"
    exit 1
fi
