# Sidero Omni - Self-Hosted Deployment Guide

Complete step-by-step guide to deploy Sidero Omni on-premises using Docker Compose with automated Cloudflare certificate generation and Dokploy compatibility.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Step-by-Step Installation](#step-by-step-installation)
- [Configuration](#configuration)
- [Authentication Setup](#authentication-setup)
- [Dokploy Deployment](#dokploy-deployment)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements

- **OS**: Ubuntu 20.04+ or any Linux distribution with Docker support
- **RAM**: Minimum 4GB (8GB+ recommended)
- **CPU**: 2+ cores
- **Storage**: 50GB+ free disk space
- **Network**: Public IP address or domain with DNS access

### Required Software

```bash
# Docker & Docker Compose
sudo apt update
sudo apt install -y docker.io docker-compose-plugin

# Additional dependencies
sudo apt install -y curl git gnupg certbot python3-certbot-dns-cloudflare uuid-runtime

# Add your user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### Domain & DNS Setup

1. **Register a domain** (e.g., `omni.example.com`)
2. **Point DNS to your server**: Create an A record pointing to your server's public IP
3. **Cloudflare Account**: [Create account](https://dash.cloudflare.com/sign-up)
   - Add your domain to Cloudflare
   - Update nameservers (Cloudflare will guide you)
   - Generate API token for certificate automation

### Cloudflare API Setup

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Navigate to **Profile** → **API Tokens**
3. Click **Create Token**
4. Use template: **Edit zone DNS**
   - **Zone Resources**: Include → Specific zone → Your domain
   - **TTL**: 1 hour recommended
5. Copy the token (you'll need it in the next step)
6. Get your **Zone ID**: Dashboard → Domain → Right sidebar → Zone ID

---

## Quick Start

### 1️⃣ Clone or Download This Repository

```bash
cd /opt
git clone https://github.com/yourusername/sidero-omni.git
cd sidero-omni
```

### 2️⃣ Configure Environment

```bash
# Copy example configuration
cp .env.example .env

# Edit with your settings
nano .env
```

**Essential settings in `.env`:**
```env
DOMAIN_NAME=omni.example.com
PUBLIC_IP=203.0.113.42
CLOUDFLARE_API_TOKEN=your_token_here
CLOUDFLARE_ZONE_ID=your_zone_id
LETSENCRYPT_EMAIL=admin@example.com
INITIAL_USERS=admin@example.com
AUTH0_ENABLED=true  # or SAML_ENABLED/OIDC_ENABLED
```

### 3️⃣ Run Setup Script

```bash
chmod +x setup.sh
./setup.sh
```

This script will:
- ✅ Validate prerequisites
- ✅ Install certbot if needed
- ✅ Generate SSL certificates via Cloudflare DNS
- ✅ Create GPG encryption keys
- ✅ Generate Account ID
- ✅ Configure auto-renewal

### 4️⃣ Start Omni

```bash
docker-compose up -d
```

### 5️⃣ Verify Deployment

```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs -f omni

# Test HTTPS access
curl -k https://localhost/health
```

---

## Step-by-Step Installation

### Step 1: Prepare Your Server

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -L https://get.docker.io | sh

# Install Docker Compose plugin
sudo apt install -y docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify installation
docker --version
docker compose version
```

### Step 2: Clone Repository

```bash
mkdir -p /opt/sidero-omni
cd /opt/sidero-omni

# Initialize git (if starting fresh)
git init

# Or clone if you have a repo
git clone https://github.com/yourusername/sidero-omni.git .
```

### Step 3: Create Configuration File

```bash
cp .env.example .env
nano .env
```

**Configure these values:**

| Variable | Example | Description |
|----------|---------|-------------|
| `DOMAIN_NAME` | `omni.example.com` | Your public domain |
| `PUBLIC_IP` | `203.0.113.42` | Server's public IP address |
| `CLOUDFLARE_API_TOKEN` | `z1a2... (64 chars)` | From Cloudflare dashboard |
| `CLOUDFLARE_ZONE_ID` | `a1b2c3d4e5...` | From Cloudflare dashboard |
| `LETSENCRYPT_EMAIL` | `admin@example.com` | For certificate renewal notifications |
| `INITIAL_USERS` | `admin@example.com` | First admin user email |

### Step 4: Generate Certificates

```bash
# Make script executable
chmod +x setup.sh

# Run setup (will prompt for confirmations)
./setup.sh
```

**What it does:**
1. Validates all prerequisites
2. Installs certbot if missing
3. Requests certificates from Let's Encrypt using Cloudflare DNS validation
4. Generates GPG keys for etcd encryption
5. Creates Account ID (UUID)
6. Configures automatic renewal

**Output files created:**
```
certs/
├── tls.crt              # SSL certificate (fullchain)
├── tls.key              # SSL private key
├── omni.asc             # GPG key for etcd
└── cloudflare.ini       # Cloudflare API credentials
```

### Step 5: Verify File Structure

```bash
tree -L 2
```

Expected structure:
```
.
├── docker-compose.yml
├── setup.sh
├── .env
├── .env.example
├── certs/
│   ├── tls.crt
│   ├── tls.key
│   ├── omni.asc
│   └── cloudflare.ini
├── data/
│   ├── etcd/
│   └── state/
└── README.md
```

### Step 6: Start the Service

```bash
# Start in background
docker-compose up -d

# Monitor startup (wait 30-60 seconds)
docker-compose logs -f omni
```

Wait for logs showing:
```
...ready to accept connections
...listening on :443
```

### Step 7: Access Omni

Open your browser:
```
https://omni.example.com
```

You should see the Omni login page.

---

## Configuration

### Authentication Methods

#### Option A: Auth0

1. **Create Auth0 Account**
   - Visit [auth0.com](https://auth0.com)
   - Sign up and create a new tenant

2. **Create Application**
   - Navigate to Applications → New Application
   - Choose "Single Page Web Application"
   - Name: "Omni"

3. **Configure URLs**
   - Settings tab:
     - Allowed Callback URLs: `https://omni.example.com`
     - Allowed Web Origins: `https://omni.example.com`
     - Allowed Logout URLs: `https://omni.example.com`

4. **Enable Social Logins**
   - Authentication → Social
   - Enable GitHub and Google

5. **Update `.env`**
   ```env
   AUTH0_ENABLED=true
   AUTH0_DOMAIN=your-tenant.us.auth0.com
   AUTH0_CLIENT_ID=xxxxxxxxxxx
   SAML_ENABLED=false
   OIDC_ENABLED=false
   ```

6. **Restart service**
   ```bash
   docker-compose restart omni
   ```

#### Option B: SAML (Azure AD / EntraID)

1. **Create Azure AD Application**
   - Azure Portal → Enterprise Applications → New Application
   - Create your own application
   - Name: "Omni"

2. **Configure SAML**
   - Single sign-on → SAML
   - Basic SAML Configuration:
     - Identifier: `https://omni.example.com`
     - Reply URL: `https://omni.example.com/auth/saml/acs`

3. **Get Federation Metadata URL**
   - Copy from "SAML Signing Certificate" section
   - Looks like: `https://login.microsoftonline.com/.../federationmetadata/...`

4. **Update `.env`**
   ```env
   SAML_ENABLED=true
   SAML_URL=https://login.microsoftonline.com/your-tenant-id/federationmetadata/2007-06/federationmetadata.xml
   AUTH0_ENABLED=false
   OIDC_ENABLED=false
   ```

5. **Restart service**
   ```bash
   docker-compose restart omni
   ```

#### Option C: OIDC (Keycloak, Okta, etc.)

1. **Create OIDC Application** in your provider
   - Redirect URI: `https://omni.example.com/auth/oidc/callback`

2. **Get Configuration Details**
   - Provider URL
   - Client ID
   - Client Secret
   - (Optional) Logout URL

3. **Update `.env`**
   ```env
   OIDC_ENABLED=true
   OIDC_PROVIDER_URL=https://your-provider.com
   OIDC_CLIENT_ID=client_id
   OIDC_CLIENT_SECRET=client_secret
   OIDC_LOGOUT_URL=https://your-provider.com/logout
   AUTH0_ENABLED=false
   SAML_ENABLED=false
   ```

4. **Restart service**
   ```bash
   docker-compose restart omni
   ```

### Environment Variables

Complete list of environment variables in `docker-compose.yml`:

```yaml
# Data persistence
- OMNI_NAME: Installation name
- DATA_DIR: Data directory path

# SSL/TLS
- OMNI_CERT: Certificate path
- OMNI_KEY: Private key path

# API URLs (must match your domain)
- OMNI_ADVERTISED_API_URL: Main API endpoint
- OMNI_SIDEROLINK_API_ADVERTISED_URL: Siderolink API
- OMNI_SIDEROLINK_WIREGUARD_ADVERTISED_ADDR: WireGuard endpoint

# Ports (defaults shown)
- OMNI_BIND_ADDR: 0.0.0.0:443
- OMNI_SIDEROLINK_API_BIND_ADDR: 0.0.0.0:8090
- OMNI_K8S_PROXY_BIND_ADDR: 0.0.0.0:8100
```

---

## Dokploy Deployment

### Option 1: Direct Docker Compose in Dokploy

1. **Log into Dokploy Dashboard**

2. **Create New Project**
   - Project Name: "Sidero Omni"

3. **Add Docker Compose Service**
   - Service Type: Docker Compose
   - Paste the contents of `docker-compose.yml`

4. **Set Environment Variables**
   - Add all variables from `.env` in Dokploy's environment section
   - Or upload `.env` file if Dokploy supports it

5. **Configure Volumes**
   - Name: `omni_etcd_data` → Mount: `./data/etcd`
   - Name: `omni_state` → Mount: `./data/state`

6. **Configure Port Mappings**
   - 443 → 443 (HTTPS)
   - 8090 → 8090 (Siderolink API)
   - 8100 → 8100 (K8s Proxy)
   - 8091 → 8091 (Event Sink)
   - 50180 → 50180 (WireGuard)

7. **Deploy**
   - Click Deploy
   - Monitor logs

### Option 2: Deploy from Git

1. **Push to Git Repository**
   ```bash
   git add .
   git commit -m "Add Sidero Omni deployment"
   git push origin main
   ```

2. **In Dokploy**
   - Create new project
   - Choose "Docker Compose from Git"
   - Enter repository URL
   - Branch: `main`
   - Path: `./docker-compose.yml`

3. **Configure as above**

### Option 3: Dokploy Native Setup

```bash
# Install Dokploy (if not already installed)
docker run -d \
  --name dokploy \
  -p 3000:3000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v dokploy-data:/root/.dokploy \
  dokploy/dokploy:latest

# Access at http://localhost:3000
```

---

## Maintenance

### Monitoring

```bash
# View real-time logs
docker-compose logs -f omni

# Check container status
docker-compose ps

# Check resource usage
docker stats sidero-omni
```

### Backup

```bash
# Backup etcd data
docker-compose down
tar -czf omni-backup-$(date +%s).tar.gz data/
docker-compose up -d

# Restore from backup
docker-compose down
tar -xzf omni-backup-*.tar.gz
docker-compose up -d
```

### Certificate Renewal

Certificates auto-renew automatically. Manual renewal:

```bash
sudo certbot renew --force-renewal
sudo cp /etc/letsencrypt/live/omni.example.com/fullchain.pem certs/tls.crt
sudo cp /etc/letsencrypt/live/omni.example.com/privkey.pem certs/tls.key
sudo chown $USER:$USER certs/tls.*
docker-compose restart omni
```

### Update Omni

```bash
# Pull latest image
docker pull ghcr.io/siderolabs/omni:latest

# Update .env with new version
# OMNI_VERSION=latest

# Restart with new image
docker-compose down
docker-compose up -d

# Verify
docker-compose logs omni
```

---

## Troubleshooting

### Issue: Certificate Generation Fails

**Error**: `DNS problem: NXDOMAIN looking up DOMAIN_NAME`

**Solutions:**
1. Verify DNS is pointing to your server:
   ```bash
   nslookup omni.example.com
   # Should return your server's IP
   ```

2. Ensure Cloudflare API credentials are correct:
   ```bash
   # Test API token
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.cloudflare.com/client/v4/user/tokens/verify
   ```

3. Wait for DNS propagation (up to 48 hours)

### Issue: Container Won't Start

**Error**: `docker: bind: address already in use`

**Solutions:**
```bash
# Check what's using the port
sudo lsof -i :443

# Kill the process or use different port in docker-compose.yml
```

### Issue: HTTPS Certificate Error in Browser

**Error**: `ERR_CERT_AUTHORITY_INVALID`

**Solutions:**
1. Wait for Let's Encrypt to provision (up to 10 minutes)
2. Check certificate validity:
   ```bash
   openssl x509 -in certs/tls.crt -text -noout | grep "Validity" -A 2
   ```

3. Verify certificate matches domain:
   ```bash
   openssl x509 -in certs/tls.crt -text -noout | grep "CN\|DNS"
   ```

### Issue: Authentication Loop

**Causes**: Callback URL mismatch in auth provider

**Solutions:**
1. **Auth0**: Verify in Application Settings:
   - Allowed Callback URLs: `https://omni.example.com`
   - Allowed Web Origins: `https://omni.example.com`

2. **SAML**: Verify Azure AD configuration:
   - Reply URL: `https://omni.example.com/auth/saml/acs`
   - Identifier: `https://omni.example.com`

3. **OIDC**: Verify Redirect URI matches exactly

### Issue: No Users Can Log In

**Causes**: No valid authentication method enabled

**Solutions:**
```bash
# Check logs
docker-compose logs omni | grep -i auth

# Ensure at least one auth method is enabled in .env
AUTH0_ENABLED=true  # at least one should be true
```

### Restart Services

```bash
# Soft restart (keeps data)
docker-compose restart omni

# Hard restart (full recreation)
docker-compose down
docker-compose up -d

# Full reset (loses data!)
docker-compose down -v
docker-compose up -d
```

---

## Advanced Configuration

### Custom Volumes

Modify `docker-compose.yml`:

```yaml
volumes:
  omni_etcd_data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=192.168.1.100,vers=4,soft,timeo=180,bg,tcp
      device: ":/path/to/nfs"
```

### Network Configuration

```yaml
networks:
  omni-network:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.9.0/24
```

### Reverse Proxy (Nginx)

```nginx
upstream omni {
    server 127.0.0.1:443;
}

server {
    listen 80;
    server_name omni.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name omni.example.com;

    ssl_certificate /etc/letsencrypt/live/omni.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/omni.example.com/privkey.pem;

    location / {
        proxy_pass https://omni;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## Support & Resources

- **Official Docs**: [https://omni.siderolabs.com/docs](https://omni.siderolabs.com/docs)
- **GitHub Issues**: [Report bugs](https://github.com/siderolabs/omni/issues)
- **Community**: [Slack Channel](https://slack.siderolabs.com)
- **Certbot Docs**: [https://certbot.eff.org](https://certbot.eff.org)
- **Cloudflare API**: [https://api.cloudflare.com](https://api.cloudflare.com)

---

## License & Terms

- Omni is available under the Business Source License
- Free for non-production environments
- Contact [Sidero Sales](https://siderolabs.com) for production use

---

**Last Updated**: December 2025  
**Tested on**: Ubuntu 24.04 LTS, Docker 25.x, Docker Compose 2.x
