# One-Click Dockerfile Deployment Guide

This guide explains how to use the custom Dockerfile for automatic certificate generation and one-click deployment on Dokploy.

## 📦 What's Included

The Dockerfile-based deployment includes:

✅ **Automatic SSL Certificate Generation** - From Let's Encrypt via Cloudflare  
✅ **Automatic GPG Key Generation** - For etcd encryption  
✅ **One-Click Deployment** - No manual setup.sh needed  
✅ **Self-Signed Fallback** - Works even without Cloudflare credentials  
✅ **Dokploy Ready** - Build and deploy directly  

---

## Files Overview

| File | Purpose |
|------|---------|
| `Dockerfile` | Custom image with cert generation tools |
| `docker-entrypoint.sh` | Startup script that generates certs automatically |
| `generate-certs.sh` | Helper for certificate generation |
| `generate-gpg-key.sh` | Helper for GPG key generation |
| `docker-compose.yml` | Updated to use custom image |

---

## Quick Start (One-Click)

### Step 1: Configure Environment Variables

```bash
cp .env.example .env
nano .env
```

**Minimum required settings:**
```env
DOMAIN_NAME=omni.example.com
PUBLIC_IP=203.0.113.42
ACCOUNT_ID=your-uuid-here  # Can be empty, will auto-generate
LETSENCRYPT_EMAIL=admin@example.com
INITIAL_USERS=admin@example.com

# For automatic Let's Encrypt certificate
ENABLE_CERT_GENERATION=true
CLOUDFLARE_API_TOKEN=your_token_here
CLOUDFLARE_ZONE_ID=your_zone_id
```

### Step 2: Build & Deploy

```bash
# Build the custom image (first time only)
docker-compose build

# Deploy (one command!)
docker-compose up -d

# Monitor startup
docker-compose logs -f omni
```

**That's it!** The container will:
1. ✅ Validate all settings
2. ✅ Generate SSL certificates (if needed)
3. ✅ Create GPG encryption keys (if needed)
4. ✅ Start Omni service

---

## How It Works

### Automatic Startup Flow

```
Container Start
    ↓
Docker Entrypoint Runs
    ↓
Validate Environment Variables
    ↓
Check for Existing Certs
    ├─ If valid → Use them
    └─ If missing → Generate
        ├─ With Cloudflare → Let's Encrypt
        └─ Without Cloudflare → Self-signed
    ↓
Check for GPG Key
    ├─ If exists → Use it
    └─ If missing → Generate
    ↓
Start Omni Service
```

### No Manual Steps Needed!

The old workflow was:
```bash
./setup.sh  # Manual certificate generation
docker-compose up -d  # Start service
```

The new workflow is:
```bash
docker-compose up -d  # Everything happens automatically!
```

---

## Deployment Options

### Option 1: With Cloudflare (Recommended)

Automatic Let's Encrypt certificates with DNS validation:

```env
ENABLE_CERT_GENERATION=true
CLOUDFLARE_API_TOKEN=z1a2b3c4d5e6f7g8h...
CLOUDFLARE_ZONE_ID=a1b2c3d4e5f6g7h8...
LETSENCRYPT_EMAIL=admin@example.com
DOMAIN_NAME=omni.example.com
```

**Startup logs will show:**
```
[OMNI] ℹ Generating SSL certificates...
[OMNI] ℹ Requesting certificate from Let's Encrypt...
[OMNI] ✓ Certificates generated and installed
[OMNI] ✓ GPG key generated
[OMNI] ✓ Pre-flight checks complete, starting Omni
```

### Option 2: Self-Signed (Development/Testing)

Uses self-signed certificates (not for production):

```env
ENABLE_CERT_GENERATION=true
# Don't set Cloudflare credentials
DOMAIN_NAME=omni.example.com
LETSENCRYPT_EMAIL=admin@example.com
```

**Startup logs will show:**
```
[OMNI] ⚠ Certificate files not found, attempting to generate...
[OMNI] ⚠ Cloudflare cert generation failed, using self-signed
[OMNI] ⚠ Self-signed certificate created (for testing only)
```

### Option 3: Pre-Generated Certificates

Use certificates you already have:

```bash
# Place your certificates in ./certs/ before starting
mkdir -p certs/
cp /path/to/your/tls.crt certs/
cp /path/to/your/tls.key certs/
cp /path/to/your/omni.asc certs/

# Then deploy (certs won't be regenerated)
docker-compose up -d
```

---

## Dokploy One-Click Deployment

### Using the Dockerfile in Dokploy

#### Method 1: From Docker Hub (Future)

```yaml
# Once published to Docker Hub
services:
  omni:
    image: yourusername/sidero-omni:latest
    # ... rest of config
```

#### Method 2: From Git with Build

1. **Push to GitHub:**
   ```bash
   git add .
   git commit -m "Add Dockerfile for one-click deployment"
   git push origin main
   ```

2. **In Dokploy Dashboard:**
   ```
   Projects → Create New Project
   Services → Add Service → Docker Compose
   Source: Git Repository
   Repository: https://github.com/yourusername/sidero-omni.git
   ```

3. **Add Environment Variables:**
   - All `.env` variables in Dokploy settings

4. **Deploy:**
   ```
   Click Deploy → Watch Logs
   ```

   The image will build automatically with Dockerfile!

#### Method 3: Direct Build Command

In Dokploy service settings, you can specify:
```
Build Command: docker-compose build
```

### Dokploy Environment Configuration

In Dokploy, set these environment variables:

```
# Required
DOMAIN_NAME              → omni.example.com
PUBLIC_IP               → 203.0.113.42
ACCOUNT_ID              → (auto-generated if empty)
LETSENCRYPT_EMAIL       → admin@example.com
INITIAL_USERS           → admin@example.com

# Cloudflare (for Let's Encrypt)
ENABLE_CERT_GENERATION  → true
CLOUDFLARE_API_TOKEN    → your_token
CLOUDFLARE_ZONE_ID      → your_zone_id

# URLs (auto-calculated if using defaults)
ADVERTISED_API_URL      → https://omni.example.com/
SIDEROLINK_API_ADVERTISED_URL → https://omni.example.com:8090/
WIREGUARD_ADVERTISED_ADDR → 203.0.113.42:50180
K8S_PROXY_URL           → https://omni.example.com:8100/

# Auth Method (choose one)
AUTH0_ENABLED           → true
AUTH0_DOMAIN            → your-tenant.us.auth0.com
AUTH0_CLIENT_ID         → your_client_id
```

### Expected Startup Behavior

Watch the logs in Dokploy:

```
[OMNI] ℹ === Sidero Omni - Container Startup ===
[OMNI] ℹ Validating environment variables...
[OMNI] ✓ All required environment variables are set
[OMNI] ℹ Initializing data directories...
[OMNI] ✓ Data directories initialized
[OMNI] ℹ Checking SSL certificates...
[OMNI] ⚠ Certificate files not found, attempting to generate...
[OMNI] ℹ Generating SSL certificates...
[OMNI] ℹ Requesting certificate from Let's Encrypt for domain: omni.example.com
[OMNI] ✓ Certificates generated and installed
[OMNI] ℹ Checking GPG key for etcd encryption...
[OMNI] ⚠ GPG key not found
[OMNI] ℹ Generating GPG key for etcd encryption...
[OMNI] ✓ GPG key generated
[OMNI] ✓ === Pre-flight checks complete, starting Omni ===
[Omni Service] INFO: Starting Omni service
[Omni Service] INFO: Listening on 0.0.0.0:443
```

---

## Certificate Management

### Automatic Certificate Renewal

Let's Encrypt certificates are valid for 90 days. To enable auto-renewal:

```bash
# On the host running Dokploy
sudo certbot renew --quiet

# Add to crontab for automatic renewal
sudo crontab -e
# Add: 0 3 * * * certbot renew --quiet
```

### Manual Certificate Update

If certificates expire or need replacement:

```bash
# SSH into Dokploy host
ssh user@dokploy-host
cd /path/to/sidero-omni

# Force renewal
sudo certbot renew --force-renewal

# Copy new certs
sudo cp /etc/letsencrypt/live/omni.example.com/fullchain.pem certs/tls.crt
sudo cp /etc/letsencrypt/live/omni.example.com/privkey.pem certs/tls.key
sudo chown $USER:$USER certs/tls.*

# Commit to git
git add certs/tls.*
git commit -m "Update SSL certificates"
git push origin main

# Redeploy in Dokploy
# Or restart: docker-compose restart omni
```

---

## Troubleshooting

### Issue: Build Fails

**Error:** `failed to solve with frontend dockerfile.v0`

**Solution:**
1. Ensure Dockerfile is in the root directory
2. Check file permissions: `chmod 755 Dockerfile`
3. Verify syntax: `docker build -t test .`

### Issue: Certificate Generation Timeout

**Error:** `Waiting for dns-01 challenge propagation: 60s, 50s, 40s...`

**Causes:**
- DNS not pointing to server yet
- Cloudflare API token is invalid
- Zone ID is incorrect

**Solutions:**
```bash
# Verify DNS points to your server
nslookup omni.example.com

# Test Cloudflare API
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify

# Check Let's Encrypt logs
docker-compose logs omni | grep -i "cloudflare\|dns\|error"
```

### Issue: Container Starts but Won't Generate Certs

**Solution 1 - Use Self-Signed:**
```env
ENABLE_CERT_GENERATION=false
```

Container will generate self-signed certs as fallback.

**Solution 2 - Pre-Generate Locally:**
```bash
# On your machine with certbot
./setup.sh

# Copy certs to repo
git add certs/
git push origin main

# Then deploy
```

### Issue: "Certificate already exists" but outdated

**Solution:**
```bash
# Force regeneration
ENABLE_CERT_GENERATION=true
docker-compose down -v  # Remove volumes
docker-compose up -d    # Will regenerate
```

### Issue: Access Denied in Docker Build

**Error:** `open /etc/letsencrypt: permission denied`

**Solution:**
The container runs as root during setup - this should work automatically. If not:

```bash
# On Dokploy host, ensure permissions
sudo chown -R root:root /etc/letsencrypt
sudo chmod -R 755 /etc/letsencrypt
```

---

## Environment Variables Reference

### Certificate Generation

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `ENABLE_CERT_GENERATION` | `true` | No | Enable automatic cert generation |
| `CLOUDFLARE_API_TOKEN` | - | No | Cloudflare API token for DNS validation |
| `CLOUDFLARE_ZONE_ID` | - | No | Cloudflare Zone ID for your domain |
| `LETSENCRYPT_EMAIL` | - | Yes | Email for Let's Encrypt notifications |
| `DOMAIN_NAME` | - | Yes | Your domain name |

### Omni Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `ACCOUNT_ID` | Yes* | Unique account ID (auto-generated if empty) |
| `INITIAL_USERS` | Yes | Initial admin user email |
| `AUTH0_ENABLED`, `SAML_ENABLED`, `OIDC_ENABLED` | Yes | At least one auth method must be enabled |

*Will be auto-generated if not provided

### API URLs

Auto-calculated from `DOMAIN_NAME` and `PUBLIC_IP`:

```env
ADVERTISED_API_URL=https://${DOMAIN_NAME}/
SIDEROLINK_API_ADVERTISED_URL=https://${DOMAIN_NAME}:8090/
WIREGUARD_ADVERTISED_ADDR=${PUBLIC_IP}:50180
K8S_PROXY_URL=https://${DOMAIN_NAME}:8100/
```

---

## Building Custom Image

### For Production/Docker Hub

```bash
# Build
docker build -t yourusername/sidero-omni:1.0.0 .

# Test locally
docker-compose up -d

# Push to Docker Hub
docker login
docker push yourusername/sidero-omni:1.0.0
```

Then reference in docker-compose.yml:
```yaml
services:
  omni:
    image: yourusername/sidero-omni:1.0.0
```

### For GitHub Container Registry

```bash
# Build
docker build -t ghcr.io/yourusername/sidero-omni:latest .

# Push
docker login ghcr.io
docker push ghcr.io/yourusername/sidero-omni:latest
```

---

## Comparison: Old vs New

### Old Workflow (Still Available)

```bash
# Step 1: Generate certs manually
./setup.sh

# Step 2: Deploy
docker-compose up -d
```

### New Workflow (Recommended)

```bash
# Everything in one command!
docker-compose up -d
```

---

## Support

- **Issues?** Check logs: `docker-compose logs -f omni`
- **Rebuild needed?** `docker-compose build --no-cache`
- **Need to customize?** Edit `Dockerfile` and helper scripts
- **GitHub Issues**: Report problems to the repository

---

**Last Updated:** December 2025  
**Tested on:** Docker 24+, Docker Compose 2.20+, Ubuntu 22.04+
