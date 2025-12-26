#!/bin/bash

#############################################################################
# Sidero Omni - Docker Entrypoint
# 
# This script runs inside the Docker container to:
# 1. Generate certificates if needed
# 2. Create GPG keys for etcd encryption
# 3. Start the Omni service
#############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Directories
CERTS_DIR="/etc/omni/tls"
SCRIPTS_DIR="/scripts"
WORKSPACE_DIR="/workspace"

#############################################################################
# Functions
#############################################################################

log_info() {
    echo -e "${BLUE}[OMNI]${NC} ℹ $1"
}

log_success() {
    echo -e "${GREEN}[OMNI]${NC} ✓ $1"
}

log_error() {
    echo -e "${RED}[OMNI]${NC} ✗ $1"
}

log_warn() {
    echo -e "${YELLOW}[OMNI]${NC} ⚠ $1"
}

# Validate required environment variables
validate_env() {
    log_info "Validating environment variables..."
    
    local required_vars=(
        "DOMAIN_NAME"
        "PUBLIC_IP"
        "ACCOUNT_ID"
        "ADVERTISED_API_URL"
        "SIDEROLINK_API_ADVERTISED_URL"
        "WIREGUARD_ADVERTISED_ADDR"
        "K8S_PROXY_URL"
        "INITIAL_USERS"
    )
    
    local missing=0
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "Required environment variable '$var' is not set"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log_error "Please set all required environment variables"
        exit 1
    fi
    
    log_success "All required environment variables are set"
}

# Check if certificates exist and are valid
check_certificates() {
    log_info "Checking SSL certificates..."
    
    local cert_file="$CERTS_DIR/tls.crt"
    local key_file="$CERTS_DIR/tls.key"
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        log_warn "Certificate files not found"
        return 1
    fi
    
    # Check if certificate is still valid
    if ! openssl x509 -in "$cert_file" -noout -checkend 86400 &>/dev/null; then
        log_warn "Certificate expires within 24 hours or is invalid"
        return 1
    fi
    
    log_success "Valid SSL certificates found"
    return 0
}

# Generate certificates using Cloudflare DNS
generate_certificates() {
    log_info "Generating SSL certificates..."
    
    # Validate Cloudflare credentials
    if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; then
        log_error "Cloudflare credentials not set (CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID)"
        return 1
    fi
    
    if [ -z "$LETSENCRYPT_EMAIL" ]; then
        log_error "Let's Encrypt email not set (LETSENCRYPT_EMAIL)"
        return 1
    fi
    
    # Create Cloudflare credentials file
    local creds_file="/tmp/cloudflare.ini"
    cat > "$creds_file" << EOF
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOF
    chmod 600 "$creds_file"
    
    # Determine if we should use staging server
    local staging_flag=""
    if [ "${LETSENCRYPT_STAGING:-false}" = "true" ]; then
        staging_flag="--staging"
        log_info "Using Let's Encrypt STAGING server (for testing)"
    else
        log_info "Using Let's Encrypt PRODUCTION server"
    fi
    
    log_info "Requesting certificate from Let's Encrypt for domain: $DOMAIN_NAME"
    
    # Request certificate
    if certbot certonly \
        $staging_flag \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$creds_file" \
        --dns-cloudflare-propagation-seconds 10 \
        --non-interactive \
        --agree-tos \
        --email "$LETSENCRYPT_EMAIL" \
        --domain "$DOMAIN_NAME" \
        --domain "*.${DOMAIN_NAME}" \
        --quiet 2>&1; then
        
        # Copy certificates to omni directory
        local certbot_cert="/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
        local certbot_key="/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem"
        
        if [ -f "$certbot_cert" ] && [ -f "$certbot_key" ]; then
            cp "$certbot_cert" "$CERTS_DIR/tls.crt"
            cp "$certbot_key" "$CERTS_DIR/tls.key"
            chmod 644 "$CERTS_DIR/tls.crt"
            chmod 600 "$CERTS_DIR/tls.key"
            
            log_success "Certificates generated and installed"
            rm "$creds_file"
            return 0
        else
            log_error "Certificate files not found after generation"
            rm "$creds_file"
            return 1
        fi
    else
        log_error "Failed to generate certificates"
        rm "$creds_file"
        return 1
    fi
}

# Generate self-signed certificate (fallback)
generate_self_signed_cert() {
    log_warn "Generating self-signed certificate (for testing only)"
    
    # Ensure certs directory exists
    mkdir -p "$CERTS_DIR"
    
    # Generate self-signed certificate (non-interactive)
    # Use /dev/urandom explicitly for better compatibility
    local openssl_output
    if openssl_output=$(openssl req -x509 -newkey rsa:2048 \
        -keyout "$CERTS_DIR/tls.key" \
        -out "$CERTS_DIR/tls.crt" \
        -days 365 \
        -nodes \
        -subj "/CN=$DOMAIN_NAME" \
        2>&1); then
        chmod 644 "$CERTS_DIR/tls.crt"
        chmod 600 "$CERTS_DIR/tls.key"
        log_warn "Self-signed certificate created (replace with valid cert for production)"
        return 0
    else
        log_error "Failed to generate self-signed certificate"
        log_error "OpenSSL error: $openssl_output"
        return 1
    fi
}

# Check if GPG key exists
check_gpg_key() {
    log_info "Checking GPG key for etcd encryption..."
    
    if [ -f "$CERTS_DIR/omni.asc" ]; then
        log_success "GPG key found"
        return 0
    fi
    
    log_warn "GPG key not found"
    return 1
}

# Generate GPG key
generate_gpg_key() {
    log_info "Generating GPG key for etcd encryption..."
    
    # Check if gpg-agent is running
    gpgconf --launch gpg-agent 2>/dev/null || true
    
    # Generate key
    gpg --batch --generate-key << EOF 2>/dev/null
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Omni
Name-Email: omni-etcd@local
Expire-Date: 0
EOF
    
    if [ $? -eq 0 ]; then
        # Export the key
        gpg --export-secret-key --armor "omni-etcd@local" > "$CERTS_DIR/omni.asc" 2>/dev/null
        chmod 600 "$CERTS_DIR/omni.asc"
        log_success "GPG key generated"
        return 0
    else
        log_error "Failed to generate GPG key"
        return 1
    fi
}

# Initialize data directories
init_data_dirs() {
    log_info "Initializing data directories..."
    
    local etcd_dir="${OMNI_ETCD_DATA_DIR:-/_out/etcd}"
    local state_dir="${OMNI_STATE_DATA_DIR:-/_out}"
    
    mkdir -p "$etcd_dir" "$state_dir"
    chmod 755 "$etcd_dir" "$state_dir"
    
    log_success "Data directories initialized"
}

#############################################################################
# Main Execution
#############################################################################

main() {
    log_info "=== Sidero Omni - Container Startup ==="
    
    # Validate environment
    validate_env
    
    # Initialize data directories
    init_data_dirs
    
    # Handle certificates
    if ! check_certificates; then
        log_warn "Valid certificates not found, attempting to generate..."
        
        if [ "$ENABLE_CERT_GENERATION" = "true" ] && [ -n "$CLOUDFLARE_API_TOKEN" ]; then
            # Try to generate from Cloudflare
            if ! generate_certificates; then
                log_warn "Cloudflare cert generation failed, using self-signed"
                if ! generate_self_signed_cert; then
                    log_error "Failed to generate any certificate"
                    exit 1
                fi
            fi
        else
            # Use self-signed as fallback
            log_warn "ENABLE_CERT_GENERATION not set, using self-signed certificate"
            if ! generate_self_signed_cert; then
                log_error "Failed to generate self-signed certificate"
                exit 1
            fi
        fi
    fi
    
    # Handle GPG key
    if ! check_gpg_key; then
        log_warn "GPG key not found, generating..."
        if ! generate_gpg_key; then
            log_error "Failed to generate GPG key"
            exit 1
        fi
    fi
    
    log_success "=== Pre-flight checks complete, starting Omni ==="
    
    # Start Omni with provided arguments or defaults
    # If no arguments provided, try to find and execute the omni binary
    if [ $# -eq 0 ]; then
        log_info "No command provided, searching for omni binary..."
        
        # Try common locations for the omni binary
        local omni_path=""
        
        # Check common binary locations
        for path in "/usr/bin/omni" "/usr/local/bin/omni" "/bin/omni" "/sbin/omni"; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                omni_path="$path"
                break
            fi
        done
        
        # If not found, try to find it in PATH
        if [ -z "$omni_path" ]; then
            if command -v omni >/dev/null 2>&1; then
                omni_path="omni"
            fi
        fi
        
        # If still not found, search more broadly
        if [ -z "$omni_path" ]; then
            log_info "Searching for omni binary in filesystem..."
            # Search in common locations including workspace
            omni_path=$(find /usr /bin /sbin /opt /workspace /app -name "omni" -type f -executable 2>/dev/null | head -n 1)
        fi
        
        # Check if there's an omni executable in the current directory
        if [ -z "$omni_path" ] && [ -f "./omni" ] && [ -x "./omni" ]; then
            omni_path="./omni"
        fi
        
        if [ -n "$omni_path" ]; then
            log_info "Found omni binary at: $omni_path"
            log_info "Starting Omni..."
            exec "$omni_path"
        else
            log_error "No command provided and omni binary not found"
            log_error "Searched in: /usr/bin, /usr/local/bin, /bin, /sbin, /opt, /workspace, /app, and PATH"
            log_error ""
            log_error "The base image 'ghcr.io/siderolabs/omni:latest' may use a different startup mechanism."
            log_error "Please check the Omni documentation or specify the command explicitly:"
            log_error "  - Add 'command: [your-omni-command]' to docker-compose.yml"
            log_error "  - Or set CMD in the Dockerfile"
            log_error "  - Or pass a command when running: docker run ... your-image your-command"
            exit 1
        fi
    else
        # Execute provided command
        log_info "Executing provided command: $*"
        exec "$@"
    fi
}

# Run main function with all remaining arguments
main "$@"
