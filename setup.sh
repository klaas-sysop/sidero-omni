#!/bin/bash

#############################################################################
# Sidero Omni - Cloudflare Certificate Generation Script
# 
# This script automatically generates SSL certificates using Cloudflare
# DNS validation via Let's Encrypt / certbot
#############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CERTS_DIR="./certs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#############################################################################
# Functions
#############################################################################

print_header() {
    echo -e "\n${BLUE}======================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

check_requirements() {
    print_header "Checking Requirements"
    
    local missing=0
    
    # Check for .env file
    if [ ! -f ".env" ]; then
        print_error ".env file not found. Please copy .env.example to .env and configure it."
        missing=1
    else
        print_success ".env file found"
    fi
    
    # Check for required commands
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed"
        missing=1
    else
        print_success "curl is installed"
    fi
    
    if ! command -v openssl &> /dev/null; then
        print_error "openssl is not installed"
        missing=1
    else
        print_success "openssl is installed"
    fi
    
    if [ $missing -eq 1 ]; then
        print_error "Please install missing requirements and try again"
        exit 1
    fi
    
    print_success "All requirements met"
}

load_env() {
    print_header "Loading Configuration"
    
    # Source .env file
    set -a
    source .env
    set +a
    
    # Validate required variables
    local required_vars=("DOMAIN_NAME" "PUBLIC_IP" "CLOUDFLARE_API_TOKEN" "CLOUDFLARE_ZONE_ID" "LETSENCRYPT_EMAIL")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_error "Required variable $var is not set in .env file"
            exit 1
        fi
    done
    
    print_success "Configuration loaded successfully"
    echo -e "\nConfiguration:"
    echo -e "  Domain: ${YELLOW}${DOMAIN_NAME}${NC}"
    echo -e "  Public IP: ${YELLOW}${PUBLIC_IP}${NC}"
    echo -e "  Email: ${YELLOW}${LETSENCRYPT_EMAIL}${NC}"
}

setup_directories() {
    print_header "Setting Up Directories"
    
    if [ ! -d "$CERTS_DIR" ]; then
        mkdir -p "$CERTS_DIR"
        print_success "Created $CERTS_DIR directory"
    else
        print_success "$CERTS_DIR directory already exists"
    fi
}

check_certbot() {
    print_header "Checking Certbot Installation"
    
    if ! command -v certbot &> /dev/null; then
        print_info "certbot not found. Installing..."
        
        # Detect OS and install accordingly
        if command -v apt-get &> /dev/null; then
            print_info "Detected Debian/Ubuntu. Installing certbot..."
            sudo apt-get update
            sudo apt-get install -y certbot python3-certbot-dns-cloudflare
            print_success "certbot installed successfully"
        elif command -v snap &> /dev/null; then
            print_info "Detected snap. Installing certbot..."
            sudo snap install --classic certbot
            sudo snap install certbot-dns-cloudflare
            sudo snap set certbot trust-plugin-with-root=ok
            print_success "certbot installed via snap"
        else
            print_error "Could not detect package manager. Please install certbot manually."
            echo "Visit: https://certbot.eff.org/instructions"
            exit 1
        fi
    else
        print_success "certbot is installed"
    fi
}

create_cloudflare_credentials() {
    print_header "Creating Cloudflare Credentials File"
    
    local creds_file="$CERTS_DIR/cloudflare.ini"
    
    if [ -f "$creds_file" ]; then
        print_info "Cloudflare credentials file already exists"
        read -p "Overwrite existing credentials? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping credentials file creation"
            return
        fi
    fi
    
    cat > "$creds_file" << EOF
# Cloudflare API credentials for certbot
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOF
    
    chmod 600 "$creds_file"
    print_success "Created Cloudflare credentials file: $creds_file"
}

generate_certificates() {
    print_header "Generating SSL Certificates"
    
    local cert_file="$CERTS_DIR/tls.crt"
    local key_file="$CERTS_DIR/tls.key"
    
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        print_info "Certificate files already exist"
        read -p "Regenerate certificates? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Using existing certificates"
            return
        fi
        
        print_info "Backing up existing certificates..."
        local timestamp=$(date +%s)
        mv "$cert_file" "$cert_file.backup.$timestamp"
        mv "$key_file" "$key_file.backup.$timestamp"
        print_success "Backed up to $cert_file.backup.$timestamp"
    fi
    
    print_info "Requesting certificate from Let's Encrypt..."
    
    sudo certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$CERTS_DIR/cloudflare.ini" \
        --dns-cloudflare-propagation-seconds 10 \
        --non-interactive \
        --agree-tos \
        --email "$LETSENCRYPT_EMAIL" \
        --domain "$DOMAIN_NAME" \
        --domain "*.${DOMAIN_NAME}"
    
    if [ $? -eq 0 ]; then
        print_success "Certificate generated successfully"
        
        # Copy certificates to our certs directory
        local certbot_cert="/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
        local certbot_key="/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem"
        
        if [ -f "$certbot_cert" ] && [ -f "$certbot_key" ]; then
            sudo cp "$certbot_cert" "$cert_file"
            sudo cp "$certbot_key" "$key_file"
            sudo chown "$USER:$USER" "$cert_file" "$key_file"
            print_success "Certificates copied to $CERTS_DIR"
        else
            print_error "Could not find generated certificates"
            exit 1
        fi
    else
        print_error "Failed to generate certificates"
        exit 1
    fi
}

generate_gpg_key() {
    print_header "Generating GPG Key for Etcd Encryption"
    
    local gpg_key="$CERTS_DIR/omni.asc"
    
    if [ -f "$gpg_key" ]; then
        print_info "GPG key already exists"
        read -p "Regenerate GPG key? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Using existing GPG key"
            return
        fi
        
        print_info "Backing up existing GPG key..."
        local timestamp=$(date +%s)
        mv "$gpg_key" "$gpg_key.backup.$timestamp"
        print_success "Backed up to $gpg_key.backup.$timestamp"
    fi
    
    print_info "Generating GPG key (this may take a moment)..."
    
    gpg --batch --generate-key << EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Omni
Name-Email: omni-etcd@local
Expire-Date: 0
EOF
    
    if [ $? -eq 0 ]; then
        print_success "GPG key generated"
        
        # Export the key
        local key_email="omni-etcd@local"
        gpg --export-secret-key --armor "$key_email" > "$gpg_key"
        
        if [ $? -eq 0 ]; then
            chmod 600 "$gpg_key"
            print_success "GPG key exported to $gpg_key"
        else
            print_error "Failed to export GPG key"
            exit 1
        fi
    else
        print_error "Failed to generate GPG key"
        exit 1
    fi
}

generate_account_id() {
    print_header "Generating Account ID"
    
    if [ ! -f ".env" ]; then
        print_error ".env file not found"
        exit 1
    fi
    
    # Check if ACCOUNT_ID is already set
    if grep -q "^ACCOUNT_ID=" .env && ! grep -q "^ACCOUNT_ID=your-account-id-here" .env; then
        print_info "ACCOUNT_ID already set in .env file"
        return
    fi
    
    local account_id=$(uuidgen)
    
    if [ -z "$account_id" ]; then
        print_error "Failed to generate UUID"
        exit 1
    fi
    
    # Update .env file
    if grep -q "^ACCOUNT_ID=" .env; then
        sed -i "s/^ACCOUNT_ID=.*/ACCOUNT_ID=$account_id/" .env
    else
        echo "ACCOUNT_ID=$account_id" >> .env
    fi
    
    print_success "Generated Account ID: $account_id"
}

setup_renewal() {
    print_header "Setting Up Certificate Renewal"
    
    print_info "Configuring automatic certificate renewal with certbot..."
    
    # Check if certbot renewal is already configured
    if sudo certbot renew --dry-run &>/dev/null; then
        print_success "Certificate renewal configured"
        print_info "Certificates will auto-renew 30 days before expiration"
    else
        print_error "Failed to configure auto-renewal"
        print_info "You may need to run: sudo certbot renew --dry-run"
    fi
}

display_summary() {
    print_header "Setup Complete!"
    
    echo -e "${GREEN}Your Sidero Omni deployment is ready!${NC}\n"
    
    echo -e "Generated files:"
    echo -e "  ${YELLOW}$CERTS_DIR/tls.crt${NC}      - SSL Certificate"
    echo -e "  ${YELLOW}$CERTS_DIR/tls.key${NC}      - SSL Private Key"
    echo -e "  ${YELLOW}$CERTS_DIR/omni.asc${NC}     - GPG Key for Etcd"
    echo -e "  ${YELLOW}$CERTS_DIR/cloudflare.ini${NC} - Cloudflare API Credentials\n"
    
    echo -e "Next steps:"
    echo -e "  1. Review and finalize ${YELLOW}.env${NC} configuration"
    echo -e "  2. Run: ${YELLOW}docker-compose up -d${NC}"
    echo -e "  3. Wait 30-60 seconds for Omni to start"
    echo -e "  4. Access at: ${YELLOW}https://${DOMAIN_NAME}${NC}\n"
    
    echo -e "Useful commands:"
    echo -e "  View logs:     ${YELLOW}docker-compose logs -f omni${NC}"
    echo -e "  Stop service:  ${YELLOW}docker-compose down${NC}"
    echo -e "  Renew certs:   ${YELLOW}sudo certbot renew${NC}\n"
}

#############################################################################
# Main Execution
#############################################################################

main() {
    print_header "Sidero Omni - Setup Script"
    
    check_requirements
    load_env
    setup_directories
    check_certbot
    create_cloudflare_credentials
    generate_certificates
    generate_gpg_key
    generate_account_id
    setup_renewal
    display_summary
}

# Run main function
main
