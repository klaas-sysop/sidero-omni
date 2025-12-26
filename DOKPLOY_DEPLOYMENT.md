# Sidero Omni - Dokploy Deployment Guide

Complete step-by-step guide to deploy Sidero Omni on Dokploy platform.

## Prerequisites

- Dokploy instance running (cloud or self-hosted)
- All files prepared (docker-compose.yml, .env, certs/)
- Git repository with all files (recommended)
- Cloudflare API credentials ready

---

## Option 1: Deploy from Git Repository (Recommended)

### Step 1: Prepare Git Repository

```bash
# Initialize or update your repository
cd /opt/sidero-omni
git init
git remote add origin https://github.com/yourusername/sidero-omni.git
git add .
git commit -m "Initial Sidero Omni deployment configuration"
git push origin main
```

**Repository structure on GitHub:**
```
sidero-omni/
├── docker-compose.yml
├── .env.example
├── .env                    (add to .gitignore!)
├── setup.sh
├── certs/
│   ├── tls.crt
│   ├── tls.key
│   ├── omni.asc
│   └── cloudflare.ini     (add to .gitignore!)
├── data/                   (add to .gitignore!)
├── README.md
└── DEPLOYMENT_GUIDE.md
```

**Create `.gitignore`:**
```bash
cat > .gitignore << EOF
.env
certs/cloudflare.ini
certs/*.pem
certs/*.key
certs/*.asc
data/
*.backup.*
.DS_Store
EOF

git add .gitignore
git commit -m "Add gitignore"
git push origin main
```

### Step 2: Access Dokploy Dashboard

1. Open your Dokploy instance: `http://dokploy.example.com` or `http://localhost:3000`
2. Log in with your credentials
3. Accept terms if first time

### Step 3: Create New Project

**Navigation:**
```
Dashboard → Projects → Create New Project
```

**Fill in:**
- **Project Name**: `Sidero Omni`
- **Description**: `Self-hosted Sidero Omni cluster management`

Click **Create**

### Step 4: Add Docker Compose Service

**Inside Project:**
```
Services → Add Service → Docker Compose
```

**Choose Source:**
- Select: `Git Repository`
- **Repository**: `https://github.com/yourusername/sidero-omni.git`
- **Branch**: `main`
- **Root Path**: `/` (or the folder containing docker-compose.yml)
- **Docker Compose Path**: `./docker-compose.yml`

Click **Create Service**

### Step 5: Configure Environment Variables

**In Service Settings:**
```
Settings → Environment Variables
```

Click **Add Variable** for each required setting:

| Key | Value | Required |
|-----|-------|----------|
| `DOMAIN_NAME` | `omni.example.com` | ✅ |
| `PUBLIC_IP` | `203.0.113.42` | ✅ |
| `CLOUDFLARE_API_TOKEN` | Your token | ✅ |
| `CLOUDFLARE_ZONE_ID` | Your zone ID | ✅ |
| `LETSENCRYPT_EMAIL` | `admin@example.com` | ✅ |
| `ACCOUNT_ID` | UUID (from setup.sh output) | ✅ |
| `OMNI_NAME` | `onprem-omni` | ⭕ |
| `DATA_DIR` | `./data` | ⭕ |
| `INITIAL_USERS` | `admin@example.com` | ✅ |
| `AUTH0_ENABLED` | `true` or `false` | ⭕ |
| `AUTH0_DOMAIN` | Your Auth0 domain | ⭕ |
| `AUTH0_CLIENT_ID` | Your client ID | ⭕ |
| `SAML_ENABLED` | `true` or `false` | ⭕ |
| `SAML_URL` | Federation metadata URL | ⭕ |

**Or paste all at once:**

Go to **Settings** → **Edit .env** and paste:
```
DOMAIN_NAME=omni.example.com
PUBLIC_IP=203.0.113.42
OMNI_VERSION=latest
CLOUDFLARE_API_TOKEN=your_api_token_here
CLOUDFLARE_ZONE_ID=your_zone_id_here
LETSENCRYPT_EMAIL=admin@example.com
ACCOUNT_ID=your-account-id-here
OMNI_NAME=onprem-omni
DATA_DIR=./data
ADVERTISED_API_URL=https://omni.example.com/
SIDEROLINK_API_ADVERTISED_URL=https://omni.example.com:8090/
WIREGUARD_ADVERTISED_ADDR=203.0.113.42:50180
K8S_PROXY_URL=https://omni.example.com:8100/
AUTH0_ENABLED=true
AUTH0_DOMAIN=your-tenant.us.auth0.com
AUTH0_CLIENT_ID=xxxxxxxxxxx
SAML_ENABLED=false
OIDC_ENABLED=false
INITIAL_USERS=admin@example.com
```

### Step 6: Configure Volumes

**In Service Settings:**
```
Settings → Volumes
```

Add these volumes:

| Volume Name | Mount Path | Host Path |
|-------------|-----------|-----------|
| `omni_etcd_data` | `/_out/etcd` | `./data/etcd` |
| `omni_state` | `/_out` | `./data/state` |

Or manually edit volumes in docker-compose.yml:
```yaml
volumes:
  omni_etcd_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/etcd
  omni_state:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_DIR:-./data}/state
```

### Step 7: Configure Ports

**In Service Settings:**
```
Settings → Ports
```

Add port mappings:

| Host Port | Container Port | Protocol | Public |
|-----------|----------------|----------|--------|
| `443` | `443` | TCP | ✅ |
| `8090` | `8090` | TCP | ✅ |
| `8100` | `8100` | TCP | ✅ |
| `8091` | `8091` | TCP | ✅ |
| `50180` | `50180` | UDP | ✅ |

### Step 8: Deploy

**Click Deploy Button:**
```
Services → [Sidero Omni] → Deploy
```

**Monitor deployment:**
- Watch real-time logs
- Wait for container to start (30-60 seconds)
- Look for "listening on :443" message

### Step 9: Verify Deployment

**Check Status:**
```
Services → [Sidero Omni] → Logs
```

Expected output:
```
INFO: Starting Omni
INFO: Loading certificates from /etc/omni/tls/tls.crt
INFO: Listening on 0.0.0.0:443
INFO: Siderolink API listening on 0.0.0.0:8090
```

**Test Access:**
```bash
# From terminal
curl -k https://omni.example.com/health

# Or open in browser
https://omni.example.com
```

---

## Option 2: Manual Docker Compose Upload

### Step 1: Create Project

```
Dashboard → Projects → Create New Project
```

### Step 2: Add Service

```
Services → Add Service → Docker Compose
```

**Choose Source:**
- Select: `Raw Docker Compose`

### Step 3: Paste Docker Compose

Copy entire contents of `docker-compose.yml` into the editor:

```yaml
version: '3.8'

services:
  omni:
    image: ghcr.io/siderolabs/omni:${OMNI_VERSION:-latest}
    # ... rest of config
```

### Step 4-9: Follow Steps 5-9 from Option 1 above

---

## Option 3: Deploy via Dokploy API

If you have API access enabled:

```bash
#!/bin/bash

DOKPLOY_URL="https://dokploy.example.com"
API_TOKEN="your_api_token"
PROJECT_ID="your_project_id"

# Create service
curl -X POST "$DOKPLOY_URL/api/services" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "sidero-omni",
    "projectId": "'$PROJECT_ID'",
    "type": "docker-compose",
    "source": "git",
    "gitRepository": "https://github.com/yourusername/sidero-omni.git",
    "branch": "main",
    "dockerComposePath": "./docker-compose.yml"
  }'
```

---

## Post-Deployment Configuration

### Generate Certificates (If Not Done Before)

If you haven't generated certificates yet, do it on the Dokploy host:

```bash
# SSH into Dokploy host
ssh dokploy-user@dokploy-host

# Clone repository
cd /opt
git clone https://github.com/yourusername/sidero-omni.git
cd sidero-omni

# Copy env
cp .env.example .env
nano .env  # Update with your values

# Run setup
chmod +x setup.sh
./setup.sh

# Commit certs to git
git add certs/
git commit -m "Add generated certificates"
git push origin main
```

Then redeploy in Dokploy.

### Setup Authentication

After deployment, configure authentication provider:

#### Auth0
1. Create application at [Auth0](https://auth0.com)
2. Set Callback URL: `https://omni.example.com`
3. Update Dokploy environment variables:
   ```
   AUTH0_ENABLED=true
   AUTH0_DOMAIN=your-tenant.us.auth0.com
   AUTH0_CLIENT_ID=xxxxx
   ```
4. Redeploy

#### SAML (Azure AD)
1. Setup in Azure Portal
2. Get Federation Metadata URL
3. Update Dokploy environment:
   ```
   SAML_ENABLED=true
   SAML_URL=https://login.microsoftonline.com/.../federationmetadata...
   ```
4. Redeploy

#### OIDC
1. Setup in your OIDC provider
2. Update Dokploy environment:
   ```
   OIDC_ENABLED=true
   OIDC_PROVIDER_URL=https://provider.com
   OIDC_CLIENT_ID=xxxxx
   OIDC_CLIENT_SECRET=xxxxx
   ```
3. Redeploy

---

## Managing in Dokploy

### View Logs

```
Services → [Sidero Omni] → Logs
```

Real-time container logs appear here.

### Restart Service

```
Services → [Sidero Omni] → Actions → Restart
```

### Stop/Start

```
Services → [Sidero Omni] → Actions → Stop
Services → [Sidero Omni] → Actions → Start
```

### Pull Latest Updates

```
Services → [Sidero Omni] → Update → Pull Latest
```

### Update Environment Variables

```
Services → [Sidero Omni] → Settings → Environment Variables
# Make changes
# Redeploy
```

### View Resource Usage

```
Services → [Sidero Omni] → Monitoring
```

Shows CPU, Memory, Network usage.

---

## Troubleshooting Dokploy Deployment

### Issue: Service Won't Start

**Check logs:**
```
Services → [Sidero Omni] → Logs
```

Look for errors like:
- `Error: bind: address already in use` → Port conflict
- `Error: cannot find certificate file` → Certs not in repo
- `Error: invalid environment variable` → Missing .env value

**Solution:**
1. Fix the issue
2. Commit to git: `git push origin main`
3. Redeploy in Dokploy

### Issue: Certificates Not Found

**Error:** `Error: cannot find /etc/omni/tls/tls.crt`

**Solutions:**
1. Generate certificates locally:
   ```bash
   ./setup.sh
   git add certs/
   git commit -m "Add certs"
   git push
   ```

2. Or mount from host in Dokploy volumes

### Issue: Environment Variables Not Working

**Check:**
```
Services → [Sidero Omni] → Settings → Environment Variables
```

Ensure all required variables are set. Then **Redeploy**.

### Issue: Database Won't Initialize

**Check logs for:** `etcd: connection refused`

**Solution:**
1. Ensure volumes are properly mounted
2. Check disk space: `df -h`
3. Reset data volume:
   ```
   Services → [Sidero Omni] → Settings → Volumes → Reset
   ```

### Issue: HTTPS Certificate Error

**Cause:** Self-signed or invalid certificate

**Solution:**
1. Verify certificates:
   ```bash
   openssl x509 -in certs/tls.crt -text -noout | grep -A 2 "Validity"
   ```

2. If expired, regenerate:
   ```bash
   sudo certbot renew --force-renewal
   git add certs/tls.crt
   git push origin main
   docker-compose restart omni
   ```

---

## Backup & Restore

### Backup in Dokploy

```bash
# SSH into Dokploy host
ssh user@dokploy-host

# Navigate to service
cd /path/to/sidero-omni

# Create backup
tar -czf omni-backup-$(date +%s).tar.gz data/ certs/

# Copy to safe location
scp omni-backup-*.tar.gz backup-server:/backups/
```

### Restore in Dokploy

```bash
# SSH into Dokploy host
cd /path/to/sidero-omni

# Stop service
docker-compose down

# Restore backup
tar -xzf omni-backup-*.tar.gz

# Start service
docker-compose up -d

# Verify
docker-compose logs -f omni
```

---

## Auto-Updates

### Enable Git Auto-Sync (If Available)

In Dokploy service settings:
```
Settings → Auto Update → Enable
Auto-update interval: 1 hour
```

This will automatically pull latest changes from git repository.

### Manual Git Sync

```
Services → [Sidero Omni] → Update → Pull Latest
```

Then redeploy.

---

## Scaling & Optimization

### Resource Limits

Edit docker-compose.yml:
```yaml
services:
  omni:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G
```

### Storage Optimization

```bash
# Check data directory size
du -sh ./data/

# Clean old logs (if needed)
docker-compose exec omni find /_out/etcd -name "*.log*" -mtime +30 -delete
```

---

## Monitoring & Alerting (Optional)

### Enable Prometheus Metrics

Add to docker-compose.yml:
```yaml
services:
  omni:
    environment:
      - OMNI_METRICS_BIND_ADDR=0.0.0.0:8092
    ports:
      - "8092:8092"
```

Then configure Dokploy monitoring to scrape `localhost:8092/metrics`.

---

## Support

- **Dokploy Docs**: https://dokploy.com/docs
- **Sidero Omni Docs**: https://omni.siderolabs.com/docs
- **GitHub Issues**: Report problems to the project repository

---

**Last Updated:** December 2025  
**Tested on:** Dokploy v0.7+
