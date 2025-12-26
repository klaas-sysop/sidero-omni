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
    echo -e "${BLUE}[OMNI]${NC} ℹ $1" >&2
}

log_success() {
    echo -e "${GREEN}[OMNI]${NC} ✓ $1" >&2
}

log_error() {
    echo -e "${RED}[OMNI]${NC} ✗ $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[OMNI]${NC} ⚠ $1" >&2
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

# Normalize boolean environment variable values
# Converts "true", "True", "TRUE", "1" to "true", everything else to "false"
normalize_boolean() {
    local value="${1:-}"
    case "${value,,}" in
        true|1|yes|on|enabled)
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Check if a value is a placeholder (contains common placeholder patterns)
is_placeholder() {
    local value="${1:-}"
    if [ -z "$value" ]; then
        return 0  # Empty is considered placeholder
    fi
    # Check for common placeholder patterns
    case "${value,,}" in
        *"your-"*|*"example"*|*"placeholder"*|*"change-me"*|*"replace"*|*"xxx"*)
            return 0  # Is placeholder
            ;;
        *)
            return 1  # Not placeholder
            ;;
    esac
}

# Validate authentication configuration
validate_auth_config() {
    log_info "Validating authentication configuration..."
    
    # Debug: Log raw values before normalization
    log_info "Raw authentication values:"
    log_info "  - AUTH0_ENABLED=${AUTH0_ENABLED:-<not set>}"
    log_info "  - OMNI_AUTH_AUTH0_ENABLED=${OMNI_AUTH_AUTH0_ENABLED:-<not set>}"
    log_info "  - AUTH0_DOMAIN=${AUTH0_DOMAIN:-<not set>}"
    log_info "  - OMNI_AUTH_AUTH0_DOMAIN=${OMNI_AUTH_AUTH0_DOMAIN:-<not set>}"
    log_info "  - AUTH0_CLIENT_ID=${AUTH0_CLIENT_ID:-<not set>}"
    log_info "  - OMNI_AUTH_AUTH0_CLIENT_ID=${OMNI_AUTH_AUTH0_CLIENT_ID:-<not set>}"
    
    # Normalize boolean values for authentication methods
    # Check both original variables (from .env) and OMNI_AUTH_* variables (set by docker-compose)
    # This handles cases where docker-compose may not have set the OMNI_AUTH_* vars yet
    local auth0_enabled=$(normalize_boolean "${AUTH0_ENABLED:-${OMNI_AUTH_AUTH0_ENABLED:-false}}")
    local saml_enabled=$(normalize_boolean "${SAML_ENABLED:-${OMNI_AUTH_SAML_ENABLED:-false}}")
    local oidc_enabled=$(normalize_boolean "${OIDC_ENABLED:-${OMNI_AUTH_OIDC_ENABLED:-false}}")
    
    # Export normalized values (this ensures proper boolean format for Omni)
    export OMNI_AUTH_AUTH0_ENABLED="$auth0_enabled"
    export OMNI_AUTH_SAML_ENABLED="$saml_enabled"
    export OMNI_AUTH_OIDC_ENABLED="$oidc_enabled"
    
    # Log authentication status
    log_info "Authentication methods:"
    log_info "  - Auth0: $auth0_enabled"
    log_info "  - SAML: $saml_enabled"
    log_info "  - OIDC: $oidc_enabled"
    
    # Re-check authentication status after placeholder validation
    # (SAML/OIDC might have been disabled if they contained placeholders)
    if [ "$saml_enabled" = "false" ]; then
        export OMNI_AUTH_SAML_ENABLED="false"
    fi
    if [ "$oidc_enabled" = "false" ]; then
        export OMNI_AUTH_OIDC_ENABLED="false"
    fi
    
    # Validate Auth0 configuration if enabled
    if [ "$auth0_enabled" = "true" ]; then
        # Check both original and OMNI_AUTH_* variable names
        local auth0_domain="${AUTH0_DOMAIN:-${OMNI_AUTH_AUTH0_DOMAIN:-}}"
        local auth0_client_id="${AUTH0_CLIENT_ID:-${OMNI_AUTH_AUTH0_CLIENT_ID:-}}"
        local auth0_client_secret="${AUTH0_CLIENT_SECRET:-${OMNI_AUTH_AUTH0_CLIENT_SECRET:-}}"
        
        if [ -z "$auth0_domain" ]; then
            log_error "AUTH0_ENABLED=true but AUTH0_DOMAIN is not set"
            exit 1
        fi
        if [ -z "$auth0_client_id" ]; then
            log_error "AUTH0_ENABLED=true but AUTH0_CLIENT_ID is not set"
            exit 1
        fi
        # Check if domain or client ID are placeholders
        if is_placeholder "$auth0_domain" || is_placeholder "$auth0_client_id"; then
            log_warn "Auth0 configuration appears to contain placeholder values, disabling Auth0"
            export OMNI_AUTH_AUTH0_ENABLED="false"
            auth0_enabled="false"
        else
            log_success "Auth0 configuration is valid (Domain: $auth0_domain, Client ID: $auth0_client_id)"
            # Export the values to ensure Omni receives them
            export OMNI_AUTH_AUTH0_DOMAIN="$auth0_domain"
            export OMNI_AUTH_AUTH0_CLIENT_ID="$auth0_client_id"
            # Export client secret if provided (some Auth0 setups may not require it)
            if [ -n "$auth0_client_secret" ] && ! is_placeholder "$auth0_client_secret"; then
                export OMNI_AUTH_AUTH0_CLIENT_SECRET="$auth0_client_secret"
            fi
        fi
    fi
    
    # Validate SAML configuration if enabled
    if [ "$saml_enabled" = "true" ]; then
        local saml_url="${SAML_URL:-${OMNI_AUTH_SAML_URL:-}}"
        if [ -z "$saml_url" ]; then
            log_error "SAML_ENABLED=true but SAML_URL is not set"
            exit 1
        fi
        # Check if URL is a placeholder
        if is_placeholder "$saml_url"; then
            log_warn "SAML_URL appears to be a placeholder value, disabling SAML"
            export OMNI_AUTH_SAML_ENABLED="false"
            saml_enabled="false"
        else
            log_success "SAML configuration is valid (URL: $saml_url)"
            export OMNI_AUTH_SAML_URL="$saml_url"
        fi
    fi
    
    # Validate OIDC configuration if enabled
    if [ "$oidc_enabled" = "true" ]; then
        local oidc_provider_url="${OIDC_PROVIDER_URL:-${OMNI_AUTH_OIDC_PROVIDER_URL:-}}"
        local oidc_client_id="${OIDC_CLIENT_ID:-${OMNI_AUTH_OIDC_CLIENT_ID:-}}"
        local oidc_client_secret="${OIDC_CLIENT_SECRET:-${OMNI_AUTH_OIDC_CLIENT_SECRET:-}}"
        
        if [ -z "$oidc_provider_url" ]; then
            log_error "OIDC_ENABLED=true but OIDC_PROVIDER_URL is not set"
            exit 1
        fi
        if [ -z "$oidc_client_id" ]; then
            log_error "OIDC_ENABLED=true but OIDC_CLIENT_ID is not set"
            exit 1
        fi
        if [ -z "$oidc_client_secret" ]; then
            log_error "OIDC_ENABLED=true but OIDC_CLIENT_SECRET is not set"
            exit 1
        fi
        # Check if URLs/values are placeholders
        if is_placeholder "$oidc_provider_url" || is_placeholder "$oidc_client_id" || is_placeholder "$oidc_client_secret"; then
            log_warn "OIDC configuration appears to contain placeholder values, disabling OIDC"
            export OMNI_AUTH_OIDC_ENABLED="false"
            oidc_enabled="false"
        else
            log_success "OIDC configuration is valid (Provider: $oidc_provider_url)"
            export OMNI_AUTH_OIDC_PROVIDER_URL="$oidc_provider_url"
            export OMNI_AUTH_OIDC_CLIENT_ID="$oidc_client_id"
            export OMNI_AUTH_OIDC_CLIENT_SECRET="$oidc_client_secret"
            if [ -n "${OIDC_LOGOUT_URL:-${OMNI_AUTH_OIDC_LOGOUT_URL:-}}" ]; then
                export OMNI_AUTH_OIDC_LOGOUT_URL="${OIDC_LOGOUT_URL:-${OMNI_AUTH_OIDC_LOGOUT_URL:-}}"
            fi
        fi
    fi
    
    # Final check: ensure at least one authentication method is enabled
    # This check happens AFTER validation, so if all methods were disabled due to invalid config,
    # we'll catch it here and exit with an error
    local final_auth0=$(normalize_boolean "${OMNI_AUTH_AUTH0_ENABLED:-false}")
    local final_saml=$(normalize_boolean "${OMNI_AUTH_SAML_ENABLED:-false}")
    local final_oidc=$(normalize_boolean "${OMNI_AUTH_OIDC_ENABLED:-false}")
    
    if [ "$final_auth0" != "true" ] && [ "$final_saml" != "true" ] && [ "$final_oidc" != "true" ]; then
        log_error "No authentication method is enabled"
        log_error "All authentication methods were either disabled or had invalid configuration."
        log_error "Please enable at least one authentication method with valid configuration:"
        log_error "  - Set AUTH0_ENABLED=true with AUTH0_DOMAIN and AUTH0_CLIENT_ID (non-placeholder values)"
        log_error "  - Set SAML_ENABLED=true with SAML_URL (non-placeholder value)"
        log_error "  - Set OIDC_ENABLED=true with OIDC_PROVIDER_URL, OIDC_CLIENT_ID, and OIDC_CLIENT_SECRET (non-placeholder values)"
        exit 1
    fi
    
    log_success "Authentication configuration is valid"
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
    # Force output to stderr so it shows in logs even if stdout is redirected
    exec >&2
    
    log_info "=== Sidero Omni - Container Startup ==="
    log_info "Entrypoint script version: $(date +%s)"
    
    # Validate environment
    validate_env
    
    # Validate and normalize authentication configuration
    validate_auth_config
    
    # Debug: Show all OMNI_AUTH_* environment variables after normalization
    log_info "Final OMNI_AUTH_* environment variables:"
    env | grep "^OMNI_AUTH_" | sort | while IFS= read -r line; do
        # Mask sensitive values
        if [[ "$line" == *"SECRET"* ]] || [[ "$line" == *"CLIENT_SECRET"* ]]; then
            log_info "  ${line%%=*}=<masked>"
        else
            log_info "  $line"
        fi
    done || true
    
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
        
        local omni_path=""
        
        # Step 1: Check common binary locations (most likely first)
        log_info "Checking standard binary locations..."
        for path in "/usr/bin/omni" "/usr/local/bin/omni" "/bin/omni" "/sbin/omni" "/usr/sbin/omni"; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                omni_path="$path"
                log_info "Found omni binary at: $path"
                break
            fi
        done
        
        # Step 2: Try to find it in PATH
        if [ -z "$omni_path" ]; then
            log_info "Checking PATH..."
            if command -v omni >/dev/null 2>&1; then
                omni_path="omni"
                log_info "Found omni in PATH"
            fi
        fi
        
        # Step 3: Search in common system directories
        if [ -z "$omni_path" ]; then
            log_info "Searching common system directories..."
            omni_path=$(find /usr /bin /sbin /opt /workspace /app /root -name "omni" -type f -executable 2>/dev/null | head -n 1)
            if [ -n "$omni_path" ]; then
                log_info "Found omni binary at: $omni_path"
            fi
        fi
        
        # Step 4: Check current directory
        if [ -z "$omni_path" ] && [ -f "./omni" ] && [ -x "./omni" ]; then
            omni_path="./omni"
            log_info "Found omni binary in current directory"
        fi
        
        # Step 5: Comprehensive filesystem search (excluding virtual filesystems)
        if [ -z "$omni_path" ]; then
            log_info "Performing comprehensive filesystem search..."
            # Search root filesystem but exclude /proc, /sys, /dev, /tmp, and other virtual filesystems
            omni_path=$(find / -maxdepth 10 -name "omni" -type f -executable \
                ! -path "/proc/*" \
                ! -path "/sys/*" \
                ! -path "/dev/*" \
                ! -path "/tmp/*" \
                ! -path "/run/*" \
                ! -path "/var/run/*" \
                ! -path "/var/tmp/*" \
                2>/dev/null | head -n 1)
            if [ -n "$omni_path" ]; then
                log_info "Found omni binary at: $omni_path"
            fi
        fi
        
        # Step 6: Check if base image has a default command we can use
        if [ -z "$omni_path" ]; then
            log_info "Checking for base image default command..."
            # Check if there's an omni-related executable or script
            # Some base images might have the binary with a different name or in a wrapper
            for alt_name in "omni-controller" "omni-server" "omni-service"; do
                if command -v "$alt_name" >/dev/null 2>&1; then
                    omni_path="$alt_name"
                    log_info "Found alternative omni executable: $alt_name"
                    break
                fi
            done
        fi
        
        # Step 7: Try to use the base image's original entrypoint if available
        if [ -z "$omni_path" ]; then
            log_info "Attempting to use base image's original entrypoint..."
            # Check for common entrypoint patterns in the base image
            # The base image might have set a default command via environment or script
            if [ -n "${OMNI_CMD:-}" ]; then
                log_info "Found OMNI_CMD environment variable: ${OMNI_CMD}"
                omni_path="${OMNI_CMD}"
            elif [ -f "/entrypoint.sh" ] && [ -x "/entrypoint.sh" ]; then
                log_info "Found base image entrypoint script, executing it..."
                exec /entrypoint.sh
            fi
        fi
        
        if [ -n "$omni_path" ]; then
            log_success "Found omni binary at: $omni_path"
            
            # Verify GPG key file exists if private key source is configured
            if [ -n "${OMNI_PRIVATE_KEY_SOURCE:-}" ]; then
                local key_path="${OMNI_PRIVATE_KEY_SOURCE#file://}"
                if [ ! -f "$key_path" ]; then
                    log_error "GPG key file not found at: $key_path"
                    log_error "Expected file from OMNI_PRIVATE_KEY_SOURCE: ${OMNI_PRIVATE_KEY_SOURCE}"
                    exit 1
                fi
                if [ ! -r "$key_path" ]; then
                    log_error "GPG key file is not readable: $key_path"
                    exit 1
                fi
                log_info "Verified GPG key file exists and is readable: $key_path"
            fi
            
            log_info "Starting Omni..."
            
            # Debug: Log environment variables
            log_info "OMNI_SQLITE_STORAGE_PATH=${OMNI_SQLITE_STORAGE_PATH:-<not set>}"
            log_info "OMNI_PRIVATE_KEY_SOURCE=${OMNI_PRIVATE_KEY_SOURCE:-<not set>}"
            
            # Build command arguments
            local omni_args=()
            
            # Set defaults if not provided via environment variables
            # These should be set in docker-compose.yml, but provide fallbacks
            local sqlite_path="${OMNI_SQLITE_STORAGE_PATH:-/_out/omni.db}"
            local private_key_source="${OMNI_PRIVATE_KEY_SOURCE:-file:///etc/omni/tls/omni.asc}"
            
            # Add SQLite storage path (required)
            # Error message explicitly mentions: --sqlite-storage-path flag
            omni_args+=("--sqlite-storage-path" "${sqlite_path}")
            log_info "Using SQLite storage path: ${sqlite_path}"
            
            # Add etcd private key source (required for GPG-encrypted etcd)
            # Error shows: Params.Storage.Default.Etcd.PrivateKeySource
            local key_path="${private_key_source#file://}"
            local key_path_with_prefix="file://${key_path}"
            
            # #region agent log
            mkdir -p /workspace/.cursor 2>/dev/null || true
            echo "{\"id\":\"log_$(date +%s)_h2a\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:428\",\"message\":\"Testing key path formats\",\"data\":{\"original\":\"${private_key_source}\",\"without_prefix\":\"${key_path}\",\"with_prefix\":\"${key_path_with_prefix}\",\"hypothesis\":\"H2a: Need file:// prefix\"},\"sessionId\":\"debug-session\",\"runId\":\"run2\",\"hypothesisId\":\"H2a\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
            # #endregion
            
            # Verify the key file exists
            if [ ! -f "$key_path" ]; then
                log_error "GPG key file not found at: $key_path"
                log_error "Expected from OMNI_PRIVATE_KEY_SOURCE: ${private_key_source}"
                exit 1
            fi
            
            # #region agent log
            mkdir -p /workspace/.cursor 2>/dev/null || true
            echo "{\"id\":\"log_$(date +%s)_h2b\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:438\",\"message\":\"File exists check\",\"data\":{\"key_path\":\"${key_path}\",\"file_exists\":true,\"file_size\":$(stat -c%s "$key_path" 2>/dev/null || echo 0),\"file_perms\":\"$(stat -c%a "$key_path" 2>/dev/null || echo unknown)\",\"hypothesis\":\"H2b: File format/permissions\"},\"sessionId\":\"debug-session\",\"runId\":\"run2\",\"hypothesisId\":\"H2b\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
            # #endregion
            
            # Check file content (first few lines to see if it's a valid GPG key)
            local file_header=$(head -n 1 "$key_path" 2>/dev/null || echo "")
            # #region agent log
            mkdir -p /workspace/.cursor 2>/dev/null || true
            echo "{\"id\":\"log_$(date +%s)_h2c\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:443\",\"message\":\"File content check\",\"data\":{\"first_line\":\"${file_header:0:50}\",\"starts_with_begin\":$(echo "$file_header" | grep -q "^-----BEGIN" && echo true || echo false),\"hypothesis\":\"H2c: File content validation\"},\"sessionId\":\"debug-session\",\"runId\":\"run2\",\"hypothesisId\":\"H2c\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
            # #endregion
            
            # Try different flag name variations based on Go CLI conventions
            # The error structure is: Params.Storage.Default.Etcd.PrivateKeySource
            # Since --storage-default-etcd-private-key-source failed, try variations:
            # Try --storage-etcd-private-key-source (without "default")
            # Also export as environment variable in case Omni reads it that way
            export OMNI_STORAGE_ETCD_PRIVATE_KEY_SOURCE="${key_path}"
            export OMNI_STORAGE_DEFAULT_ETCD_PRIVATE_KEY_SOURCE="${key_path}"
            
            # #region agent log
            mkdir -p /workspace/.cursor 2>/dev/null || true
            echo "{\"id\":\"log_$(date +%s)_h1\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:442\",\"message\":\"Testing flag variations\",\"data\":{\"key_path\":\"${key_path}\",\"hypothesis\":\"H1: Try simpler flag names\",\"attempted_flags\":[\"--storage-etcd-private-key-source\",\"--etcd-private-key-source\",\"--private-key-source\"]},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"H1\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
            # #endregion
            
            # First, try to get help from Omni to see available flags (hypothesis H4: check what flags exist)
            log_info "Checking Omni help for available flags..."
            # #region agent log
            mkdir -p /workspace/.cursor 2>/dev/null || true
            echo "{\"id\":\"log_$(date +%s)_h4\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:448\",\"message\":\"Getting Omni help output\",\"data\":{\"hypothesis\":\"H4: Check available flags via help\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"H4\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
            # #endregion
            if "$omni_path" --help 2>&1 | grep -i "private\|key\|etcd\|storage" > /tmp/omni-help.txt 2>&1; then
                log_info "Found relevant flags in help (saved to /tmp/omni-help.txt)"
                # #region agent log
                echo "{\"id\":\"log_$(date +%s)_h4\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:452\",\"message\":\"Omni help output captured\",\"data\":{\"help_file\":\"/tmp/omni-help.txt\",\"hypothesis\":\"H4: Check available flags\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"H4\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
                # #endregion
            fi
            
            # Try simpler flag variations (hypothesis H1: simpler flag names)
            # Ensure SQLite path is always in args first
            omni_args=("--sqlite-storage-path" "${sqlite_path}")
            
            # Try multiple flag name variations
            local flag_variations=(
                "--storage-etcd-private-key-source"
                "--etcd-private-key-source"
                "--private-key-source"
                "--storage.etcd.private-key-source"
                "--storage-etcd-private-key"
            )
            
            local flag_found=false
            # First, try to see if any flag appears in help output (hypothesis H4)
            local help_output=""
            if help_output=$("$omni_path" --help 2>&1); then
                # #region agent log
                mkdir -p /workspace/.cursor 2>/dev/null || true
                echo "{\"id\":\"log_$(date +%s)_h4\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:465\",\"message\":\"Help output captured\",\"data\":{\"help_length\":${#help_output},\"hypothesis\":\"H4: Check available flags\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"H4\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
                # #endregion
                echo "$help_output" | grep -i "private\|key\|etcd\|storage" > /tmp/omni-help-filtered.txt 2>&1 || true
            fi
            
            # Try each flag variation by attempting to run with it (hypothesis H1, H3)
            for flag in "${flag_variations[@]}"; do
                # #region agent log
                mkdir -p /workspace/.cursor 2>/dev/null || true
                echo "{\"id\":\"log_$(date +%s)_h1\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:475\",\"message\":\"Trying flag variation\",\"data\":{\"flag\":\"${flag}\",\"key_path\":\"${key_path}\",\"hypothesis\":\"H1: Simpler flag names\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"H1\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
                # #endregion
                # Test if flag appears in help or if it's accepted (doesn't error immediately)
                if echo "$help_output" | grep -q "$flag" 2>/dev/null || \
                   "$omni_path" "$flag" "${key_path}" --help >/dev/null 2>&1; then
                    log_info "Flag ${flag} appears to be valid"
                    # Try with file:// prefix first (hypothesis H2a)
                    omni_args+=("$flag" "${key_path_with_prefix}")
                    flag_found=true
                    # #region agent log
                    mkdir -p /workspace/.cursor 2>/dev/null || true
                    echo "{\"id\":\"log_$(date +%s)_h1\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:483\",\"message\":\"Flag accepted\",\"data\":{\"flag\":\"${flag}\",\"hypothesis\":\"H1: Simpler flag names - CONFIRMED\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"H1\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
                    # #endregion
                    break
                else
                    # #region agent log
                    mkdir -p /workspace/.cursor 2>/dev/null || true
                    echo "{\"id\":\"log_$(date +%s)_h1\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:488\",\"message\":\"Flag rejected\",\"data\":{\"flag\":\"${flag}\",\"hypothesis\":\"H1: Simpler flag names - REJECTED\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"H1\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
                    # #endregion
                fi
            done
            
            if [ "$flag_found" = false ]; then
                log_warn "No valid flag found, will try environment variables only (hypothesis H2)"
                # #region agent log
                mkdir -p /workspace/.cursor 2>/dev/null || true
                echo "{\"id\":\"log_$(date +%s)_h2\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:485\",\"message\":\"No flag found, using env vars\",\"data\":{\"hypothesis\":\"H2: Environment variables only\",\"env_vars\":[\"OMNI_STORAGE_ETCD_PRIVATE_KEY_SOURCE\",\"OMNI_STORAGE_DEFAULT_ETCD_PRIVATE_KEY_SOURCE\"]},\"sessionId\":\"debug-session\",\"runId\":\"run2\",\"hypothesisId\":\"H2\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
                # #endregion
                # Don't add flag, rely on environment variables
            else
                log_info "Using etcd private key source (flag: ${omni_args[-2]}): ${omni_args[-1]}"
                # #region agent log
                mkdir -p /workspace/.cursor 2>/dev/null || true
                echo "{\"id\":\"log_$(date +%s)_final\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:503\",\"message\":\"Final key path format\",\"data\":{\"flag\":\"${omni_args[-2]}\",\"key_path_value\":\"${omni_args[-1]}\",\"has_file_prefix\":$(echo "${omni_args[-1]}" | grep -q "^file://" && echo true || echo false),\"hypothesis\":\"H2a: Testing file:// prefix\"},\"sessionId\":\"debug-session\",\"runId\":\"run2\",\"hypothesisId\":\"H2a\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
                # #endregion
            fi
            
            # Log the final command
            log_info "Executing: $omni_path ${omni_args[*]}"
            
            # Final check: Log all OMNI_AUTH_* variables that will be passed to Omni
            log_info "Environment variables being passed to Omni:"
            env | grep "^OMNI_AUTH_" | sort | while IFS= read -r line; do
                # Mask sensitive values
                if [[ "$line" == *"SECRET"* ]] || [[ "$line" == *"CLIENT_SECRET"* ]]; then
                    log_info "  ${line%%=*}=<masked>"
                else
                    log_info "  $line"
                fi
            done
            
            # #region agent log
            mkdir -p /workspace/.cursor 2>/dev/null || true
            echo "{\"id\":\"log_$(date +%s)_final\",\"timestamp\":$(date +%s)000,\"location\":\"docker-entrypoint.sh:495\",\"message\":\"Final command execution\",\"data\":{\"omni_path\":\"${omni_path}\",\"args\":\"${omni_args[*]}\",\"env_vars\":{\"OMNI_STORAGE_ETCD_PRIVATE_KEY_SOURCE\":\"${OMNI_STORAGE_ETCD_PRIVATE_KEY_SOURCE}\"}},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"ALL\"}" >> /workspace/.cursor/debug.log 2>/dev/null || true
            # #endregion
            
            # Final verification: Ensure authentication variables are set and valid
            local final_auth0_check=$(normalize_boolean "${OMNI_AUTH_AUTH0_ENABLED:-false}")
            local final_saml_check=$(normalize_boolean "${OMNI_AUTH_SAML_ENABLED:-false}")
            local final_oidc_check=$(normalize_boolean "${OMNI_AUTH_OIDC_ENABLED:-false}")
            
            if [ "$final_auth0_check" != "true" ] && [ "$final_saml_check" != "true" ] && [ "$final_oidc_check" != "true" ]; then
                log_error "CRITICAL: No valid authentication method is enabled before executing Omni!"
                log_error "OMNI_AUTH_AUTH0_ENABLED=${OMNI_AUTH_AUTH0_ENABLED:-<not set>}"
                log_error "OMNI_AUTH_SAML_ENABLED=${OMNI_AUTH_SAML_ENABLED:-<not set>}"
                log_error "OMNI_AUTH_OIDC_ENABLED=${OMNI_AUTH_OIDC_ENABLED:-<not set>}"
                log_error "This should not happen if validate_auth_config() ran successfully."
                exit 1
            fi
            
            # Ensure all authentication variables are explicitly exported one more time before exec
            # This guarantees they're in the environment when Omni starts
            export OMNI_AUTH_AUTH0_ENABLED="$final_auth0_check"
            export OMNI_AUTH_SAML_ENABLED="$final_saml_check"
            export OMNI_AUTH_OIDC_ENABLED="$final_oidc_check"
            
            # Re-export all auth configuration values to ensure they're available to Omni
            # This is critical because exec replaces the process and we need to guarantee env vars are set
            if [ "$final_auth0_check" = "true" ]; then
                export OMNI_AUTH_AUTH0_DOMAIN="${OMNI_AUTH_AUTH0_DOMAIN:-${AUTH0_DOMAIN:-}}"
                export OMNI_AUTH_AUTH0_CLIENT_ID="${OMNI_AUTH_AUTH0_CLIENT_ID:-${AUTH0_CLIENT_ID:-}}"
                if [ -n "${OMNI_AUTH_AUTH0_CLIENT_SECRET:-${AUTH0_CLIENT_SECRET:-}}" ]; then
                    export OMNI_AUTH_AUTH0_CLIENT_SECRET="${OMNI_AUTH_AUTH0_CLIENT_SECRET:-${AUTH0_CLIENT_SECRET:-}}"
                fi
            fi
            if [ "$final_saml_check" = "true" ]; then
                export OMNI_AUTH_SAML_URL="${OMNI_AUTH_SAML_URL:-${SAML_URL:-}}"
            fi
            if [ "$final_oidc_check" = "true" ]; then
                export OMNI_AUTH_OIDC_PROVIDER_URL="${OMNI_AUTH_OIDC_PROVIDER_URL:-${OIDC_PROVIDER_URL:-}}"
                export OMNI_AUTH_OIDC_CLIENT_ID="${OMNI_AUTH_OIDC_CLIENT_ID:-${OIDC_CLIENT_ID:-}}"
                export OMNI_AUTH_OIDC_CLIENT_SECRET="${OMNI_AUTH_OIDC_CLIENT_SECRET:-${OIDC_CLIENT_SECRET:-}}"
                if [ -n "${OMNI_AUTH_OIDC_LOGOUT_URL:-${OIDC_LOGOUT_URL:-}}" ]; then
                    export OMNI_AUTH_OIDC_LOGOUT_URL="${OMNI_AUTH_OIDC_LOGOUT_URL:-${OIDC_LOGOUT_URL:-}}"
                fi
            fi
            
            # Execute omni with arguments
            # Use exec to replace the shell process, ensuring all exported environment variables are passed
            log_info "About to execute Omni with environment variables exported"
            log_info "Final authentication status - Auth0: $final_auth0_check, SAML: $final_saml_check, OIDC: $final_oidc_check"
            
            # Debug: Log all OMNI_AUTH_* variables one final time before exec
            log_info "Final OMNI_AUTH_* environment variables before exec:"
            env | grep "^OMNI_AUTH_" | sort | while IFS= read -r line; do
                # Mask sensitive values
                if [[ "$line" == *"SECRET"* ]] || [[ "$line" == *"CLIENT_SECRET"* ]]; then
                    log_info "  ${line%%=*}=<masked>"
                else
                    log_info "  $line"
                fi
            done || true
            if [ ${#omni_args[@]} -gt 0 ]; then
                exec "$omni_path" "${omni_args[@]}"
            else
                log_warn "No command-line arguments provided, Omni may fail due to missing configuration"
                exec "$omni_path"
            fi
        else
            log_error "No command provided and omni binary not found"
            log_error ""
            log_error "Searched locations:"
            log_error "  - Standard paths: /usr/bin, /usr/local/bin, /bin, /sbin, /usr/sbin"
            log_error "  - PATH environment variable"
            log_error "  - Common directories: /usr, /bin, /sbin, /opt, /workspace, /app, /root"
            log_error "  - Current directory (./omni)"
            log_error "  - Comprehensive filesystem search (excluding virtual filesystems)"
            log_error "  - Alternative names: omni-controller, omni-server, omni-service"
            log_error "  - Base image entrypoint scripts"
            log_error ""
            log_error "The base image 'ghcr.io/siderolabs/omni:latest' may use a different startup mechanism."
            log_error ""
            log_error "Possible solutions:"
            log_error "  1. Inspect the base image to find the omni binary location:"
            log_error "     docker run --rm --entrypoint /bin/sh ghcr.io/siderolabs/omni:latest -c 'find / -name omni -type f 2>/dev/null'"
            log_error "  2. Check the base image's default CMD/ENTRYPOINT:"
            log_error "     docker inspect ghcr.io/siderolabs/omni:latest | grep -A 5 -E '(Cmd|Entrypoint)'"
            log_error "  3. Specify the command explicitly in docker-compose.yml:"
            log_error "     command: ['/path/to/omni']"
            log_error "  4. Or pass a command when running:"
            log_error "     docker run ... your-image /path/to/omni"
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
