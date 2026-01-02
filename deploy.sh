#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
MODE=""
SELF_SIGNED=false
PRODUCTION=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --self-signed)
            SELF_SIGNED=true
            MODE="self-signed"
            shift
            ;;
        --production)
            PRODUCTION=true
            MODE="production"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--self-signed|--production]"
            echo ""
            echo "Options:"
            echo "  --self-signed    Generate self-signed certificates for testing"
            echo "  --production     Use existing production certificates"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "If no option is provided, the script will prompt for mode selection."
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing=0
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        missing=1
    fi
    
    if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        missing=1
    fi
    
    if ! command -v openssl &> /dev/null; then
        print_error "OpenSSL is not installed. Please install OpenSSL first."
        missing=1
    fi
    
    if ! command -v gpg &> /dev/null; then
        print_error "GPG is not installed. Please install GPG first."
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
    
    print_info "All prerequisites met!"
}

# Generate self-signed certificates
generate_self_signed_certs() {
    print_info "Generating self-signed certificates..."
    
    local certs_dir="./certs"
    local cert_file="$certs_dir/tls.crt"
    local key_file="$certs_dir/tls.key"
    
    # Create certs directory if it doesn't exist
    mkdir -p "$certs_dir"
    
    # Check if certificates already exist
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        print_warn "Certificates already exist. Skipping generation."
        return
    fi
    
    # Get domain from .env or use default
    local domain="${OMNI_DOMAIN_NAME:-localhost}"
    
    # Generate self-signed certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key_file" \
        -out "$cert_file" \
        -subj "/C=US/ST=State/L=City/O=Omni/CN=$domain" \
        -addext "subjectAltName=DNS:$domain,DNS:*.$domain,IP:127.0.0.1"
    
    # Set proper permissions
    chmod 600 "$key_file"
    chmod 644 "$cert_file"
    
    print_info "Self-signed certificates generated successfully!"
    print_warn "These certificates are for testing only and will show browser warnings."
}

# Validate production certificates
validate_production_certs() {
    print_info "Validating production certificates..."
    
    local cert_file="${TLS_CERT_PATH:-./certs/tls.crt}"
    local key_file="${TLS_KEY_PATH:-./certs/tls.key}"
    
    if [ ! -f "$cert_file" ]; then
        print_error "Certificate file not found: $cert_file"
        print_error "Please provide valid certificates or use --self-signed for testing."
        exit 1
    fi
    
    if [ ! -f "$key_file" ]; then
        print_error "Private key file not found: $key_file"
        print_error "Please provide valid certificates or use --self-signed for testing."
        exit 1
    fi
    
    # Validate certificate
    if ! openssl x509 -in "$cert_file" -text -noout &> /dev/null; then
        print_error "Invalid certificate file: $cert_file"
        exit 1
    fi
    
    # Validate key
    if ! openssl rsa -in "$key_file" -check &> /dev/null && ! openssl ec -in "$key_file" -check &> /dev/null; then
        print_error "Invalid private key file: $key_file"
        exit 1
    fi
    
    print_info "Production certificates validated successfully!"
}

# Generate GPG key for etcd encryption
generate_gpg_key() {
    print_info "Checking GPG encryption key..."
    
    local gpg_key_file="${GPG_KEY_PATH:-./omni.asc}"
    
    if [ -f "$gpg_key_file" ]; then
        print_info "GPG key already exists. Skipping generation."
        return
    fi
    
    print_info "Generating GPG encryption key for etcd..."
    
    # Get email from .env or use default
    local email="${OMNI_ADMIN_EMAIL:-omni@example.com}"
    local key_name="Omni (Used for etcd data encryption) $email"
    
    # Use a temporary GPG home directory to avoid TTY issues
    local temp_gnupg=$(mktemp -d)
    local old_gnupg="${GNUPGHOME:-}"
    export GNUPGHOME="$temp_gnupg"
    
    # Create GPG batch config for non-interactive key generation
    local batch_config=$(mktemp)
    cat > "$batch_config" <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: cert
Name-Real: Omni
Name-Email: $email
Name-Comment: Used for etcd data encryption
Expire-Date: 0
%commit
EOF
    
    # Generate GPG key using batch config
    if ! gpg --batch --gen-key "$batch_config" &> /dev/null 2>&1; then
        rm -f "$batch_config"
        rm -rf "$temp_gnupg"
        [ -n "$old_gnupg" ] && export GNUPGHOME="$old_gnupg" || unset GNUPGHOME
        print_error "Failed to generate GPG key"
        exit 1
    fi
    
    rm -f "$batch_config"
    
    # Get fingerprint
    local fingerprint=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep "^fpr" | head -1 | cut -d: -f10)
    
    if [ -z "$fingerprint" ]; then
        rm -rf "$temp_gnupg"
        [ -n "$old_gnupg" ] && export GNUPGHOME="$old_gnupg" || unset GNUPGHOME
        print_error "Failed to get GPG key fingerprint"
        exit 1
    fi
    
    # Create batch config for encryption subkey
    local subkey_config=$(mktemp)
    cat > "$subkey_config" <<EOF
addkey
rsa
4096
0
save
EOF
    
    # Add encryption subkey
    if ! echo -e "addkey\nrsa\n4096\n0\nsave" | gpg --batch --command-fd 0 --edit-key "$fingerprint" &> /dev/null 2>&1; then
        # Alternative: use quick-add-key if available
        gpg --batch --quick-add-key "$fingerprint" rsa4096 encr never &> /dev/null 2>&1 || true
    fi
    
    rm -f "$subkey_config"
    
    # Export key
    if ! gpg --batch --export-secret-key --armor "$email" > "$gpg_key_file" 2>/dev/null; then
        rm -rf "$temp_gnupg"
        [ -n "$old_gnupg" ] && export GNUPGHOME="$old_gnupg" || unset GNUPGHOME
        print_error "Failed to export GPG key"
        exit 1
    fi
    
    # Clean up temporary GPG home
    rm -rf "$temp_gnupg"
    [ -n "$old_gnupg" ] && export GNUPGHOME="$old_gnupg" || unset GNUPGHOME
    
    # Set proper permissions
    chmod 600 "$gpg_key_file"
    
    print_info "GPG encryption key generated successfully!"
}

# Setup environment file
setup_env_file() {
    print_info "Setting up environment file..."
    
    # Create .env from example if it doesn't exist
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            print_info "Created .env from .env.example"
        else
            # Create minimal .env file if .env.example doesn't exist
            print_warn ".env.example not found, creating minimal .env file"
            cat > .env <<EOF
# Omni Version
OMNI_VERSION=0.41.0

# Account UUID (will be generated if not set)
OMNI_ACCOUNT_UUID=

# Domain Configuration
OMNI_DOMAIN_NAME=
OMNI_WG_IP=

# Admin Configuration
OMNI_ADMIN_EMAIL=
OMNI_NAME=onprem-omni

# Certificate Paths
TLS_CERT_PATH=./certs/tls.crt
TLS_KEY_PATH=./certs/tls.key

# GPG Key Path
GPG_KEY_PATH=./omni.asc

# Auth0 Configuration
AUTH0_ENABLED=true
AUTH0_DOMAIN=
AUTH0_CLIENT_ID=
EOF
            print_info "Created minimal .env file"
        fi
    else
        if [ -f ".env.example" ]; then
            print_info "Using existing .env file (.env.example is available as reference)"
        else
            print_info "Using existing .env file"
        fi
    fi
    
    # Source .env to get current values
    set -a
    source .env 2>/dev/null || true
    set +a
    
    # Helper function to set or append variable in .env
    set_env_var() {
        local var_name=$1
        local var_value=$2
        if grep -q "^${var_name}=" .env 2>/dev/null; then
            # Variable exists, update it
            sed -i.bak "s|^${var_name}=.*|${var_name}=${var_value}|" .env
            rm -f .env.bak
        else
            # Variable doesn't exist, append it
            echo "${var_name}=${var_value}" >> .env
        fi
    }
    
    # Prompt for missing required variables
    if [ -z "$OMNI_DOMAIN_NAME" ]; then
        read -p "Enter Omni domain name (e.g., omni.example.com): " OMNI_DOMAIN_NAME
        set_env_var "OMNI_DOMAIN_NAME" "$OMNI_DOMAIN_NAME"
    fi
    
    if [ -z "$OMNI_WG_IP" ]; then
        read -p "Enter WireGuard IP address (e.g., 10.10.1.100): " OMNI_WG_IP
        set_env_var "OMNI_WG_IP" "$OMNI_WG_IP"
    fi
    
    if [ -z "$OMNI_ADMIN_EMAIL" ]; then
        read -p "Enter admin email address: " OMNI_ADMIN_EMAIL
        set_env_var "OMNI_ADMIN_EMAIL" "$OMNI_ADMIN_EMAIL"
    fi
    
    if [ "${AUTH0_ENABLED:-true}" = "true" ]; then
        if [ -z "$AUTH0_DOMAIN" ]; then
            read -p "Enter Auth0 domain (e.g., dev-xxxxx.us.auth0.com): " AUTH0_DOMAIN
            set_env_var "AUTH0_DOMAIN" "$AUTH0_DOMAIN"
        fi
        
        if [ -z "$AUTH0_CLIENT_ID" ]; then
            read -p "Enter Auth0 client ID: " AUTH0_CLIENT_ID
            set_env_var "AUTH0_CLIENT_ID" "$AUTH0_CLIENT_ID"
        fi
    fi
    
    # Generate account UUID if not set
    if [ -z "$OMNI_ACCOUNT_UUID" ]; then
        if command -v uuidgen &> /dev/null; then
            OMNI_ACCOUNT_UUID=$(uuidgen)
        elif command -v python3 &> /dev/null; then
            OMNI_ACCOUNT_UUID=$(python3 -c "import uuid; print(uuid.uuid4())")
        else
            print_warn "Could not generate UUID automatically. Please set OMNI_ACCOUNT_UUID in .env"
        fi
        
        if [ -n "$OMNI_ACCOUNT_UUID" ]; then
            set_env_var "OMNI_ACCOUNT_UUID" "$OMNI_ACCOUNT_UUID"
        fi
    fi
    
    # Update certificate paths based on mode
    if [ "$SELF_SIGNED" = true ]; then
        set_env_var "TLS_CERT_PATH" "./certs/tls.crt"
        set_env_var "TLS_KEY_PATH" "./certs/tls.key"
    fi
    
    print_info "Environment file configured!"
}

# Create necessary directories
create_directories() {
    print_info "Creating necessary directories..."
    
    mkdir -p ./etcd
    mkdir -p ./certs
    
    print_info "Directories created!"
}

# Deploy with docker compose
deploy_omni() {
    print_info "Deploying Omni..."
    
    # Source .env for docker compose
    set -a
    source .env
    set +a
    
    # Check if docker compose or docker-compose
    if command -v docker compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    else
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
    
    # Pull latest image
    print_info "Pulling Omni image..."
    $DOCKER_COMPOSE_CMD --env-file .env pull
    
    # Start containers
    print_info "Starting Omni container..."
    $DOCKER_COMPOSE_CMD --env-file .env up -d
    
    # Wait a moment for container to start
    sleep 3
    
    # Check container status
    if $DOCKER_COMPOSE_CMD --env-file .env ps | grep -q "Up"; then
        print_info "Omni deployed successfully!"
    else
        print_error "Omni container failed to start. Check logs with: docker compose logs omni"
        exit 1
    fi
}

# Show deployment information
show_deployment_info() {
    print_info "Deployment complete!"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Omni Deployment Information${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Source .env to get domain
    set -a
    source .env 2>/dev/null || true
    set +a
    
    local domain="${OMNI_DOMAIN_NAME:-localhost}"
    
    echo "  Web UI:     https://$domain"
    echo "  API:        https://$domain/api"
    echo "  Siderolink: https://$domain:8090"
    echo "  K8s Proxy:  https://$domain:8100"
    echo ""
    
    if [ "$SELF_SIGNED" = true ]; then
        echo -e "${YELLOW}  Note: Using self-signed certificates. Browser warnings are expected.${NC}"
        echo ""
    fi
    
    echo "  View logs:  docker compose logs -f omni"
    echo "  Stop:       docker compose down"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
}

# Main execution
main() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Omni On-Prem Deployment Script                 ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Prompt for mode if not specified
    if [ -z "$MODE" ]; then
        echo "Select deployment mode:"
        echo "  1) Self-signed certificates (for testing)"
        echo "  2) Production certificates (existing certs)"
        read -p "Enter choice [1-2]: " choice
        
        case $choice in
            1)
                SELF_SIGNED=true
                MODE="self-signed"
                ;;
            2)
                PRODUCTION=true
                MODE="production"
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_env_file
    
    # Source .env for certificate operations
    set -a
    source .env
    set +a
    
    # Handle certificates based on mode
    if [ "$SELF_SIGNED" = true ]; then
        generate_self_signed_certs
    elif [ "$PRODUCTION" = true ]; then
        validate_production_certs
    fi
    
    # Generate GPG key
    generate_gpg_key
    
    # Create directories
    create_directories
    
    # Deploy
    deploy_omni
    
    # Show info
    show_deployment_info
}

# Run main function
main

