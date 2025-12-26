# Sidero Omni - One-Click Docker Deployment

Complete self-hosted deployment solution for Sidero Omni with automatic SSL certificate generation and one-click Dokploy deployment.

## 🚀 Quick Start

```bash
# 1. Configure
cp .env.example .env
nano .env  # Fill in your domain and credentials

# 2. Deploy (everything automatic!)
docker-compose up -d

# 3. Access
https://omni.example.com
```

That's it! SSL certificates, GPG keys, and Omni service all start automatically.

---

## 📋 What's Included

### Docker Ecosystem
- **Dockerfile** - Custom image with automatic certificate generation
- **docker-compose.yml** - Production-ready configuration
- **docker-entrypoint.sh** - Smart startup script with cert generation
- **Helper Scripts** - Certificate and GPG key generators

### Documentation
- **DOCKERFILE_QUICKREF.md** - 2-minute quick reference
- **DOCKERFILE_GUIDE.md** - Complete Dockerfile guide with examples
- **DEPLOYMENT_GUIDE.md** - General deployment guide
- **DOKPLOY_DEPLOYMENT.md** - Dokploy-specific instructions

### Configuration
- **.env.example** - Template with all variables
- **setup.sh** - Manual setup script (optional, for pre-generation)

---

## ⚡ Key Features

✅ **One-Click Deployment** - No manual setup needed  
✅ **Automatic SSL Certificates** - Let's Encrypt via Cloudflare DNS  
✅ **Automatic GPG Keys** - For etcd encryption  
✅ **Self-Healing** - Regenerates missing certs/keys  
✅ **Dokploy Ready** - Deploy directly from Dokploy dashboard  
✅ **Multiple Auth Methods** - Auth0, SAML, OIDC support  
✅ **Production Ready** - Health checks, logging, persistence  
✅ **Backward Compatible** - Old setup.sh method still works  

---

## 📚 Documentation

Choose your deployment path:

### 🎯 Just Want to Deploy?
→ Read **[DOCKERFILE_QUICKREF.md](docs/DOCKERFILE_QUICKREF.md)** (2 minutes)

### 🏗️ Self-Hosted on Linux
→ Read **[DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)** (10 minutes)

### 🐳 Using Docker & Dockerfile
→ Read **[DOCKERFILE_GUIDE.md](docs/DOCKERFILE_GUIDE.md)** (detailed reference)

### ☁️ Deploying on Dokploy
→ Read **[DOKPLOY_DEPLOYMENT.md](docs/DOKPLOY_DEPLOYMENT.md)** (step-by-step)

---

## 🎬 Deployment Methods

### Method 1: Local Docker (Fastest)

```bash
# Configure
cp .env.example .env
nano .env

# Deploy
docker-compose up -d

# Done! Access at https://your-domain.com
```

**Time to production: 5 minutes**

### Method 2: Dokploy Cloud/Self-Hosted

1. Push to GitHub: `git push origin main`
2. In Dokploy dashboard: Create project → Add Docker Compose service
3. Set environment variables from `.env`
4. Click Deploy
5. Watch logs - done!

**Time to production: 10 minutes**

### Method 3: Manual Pre-Generation (Advanced)

```bash
# Pre-generate certificates locally
./setup.sh

# Commit to git
git add certs/
git push origin main

# Then deploy with docker-compose
docker-compose up -d
```

---

## 🔑 Essential Configuration

### Minimum Required Variables

```env
DOMAIN_NAME=omni.example.com
PUBLIC_IP=203.0.113.42
CLOUDFLARE_API_TOKEN=your_token
CLOUDFLARE_ZONE_ID=your_zone_id
LETSENCRYPT_EMAIL=admin@example.com
INITIAL_USERS=admin@example.com
AUTH0_ENABLED=true              # Or SAML_ENABLED / OIDC_ENABLED
AUTH0_DOMAIN=your-tenant.us.auth0.com
AUTH0_CLIENT_ID=your_client_id
```

See **.env.example** for complete list of 50+ variables.

---

## 🏗️ How It Works

### Traditional Workflow (Before)
```
1. Run ./setup.sh manually
2. Wait for certificates
3. docker-compose up -d
4. Service starts
```

### New Workflow (With Dockerfile)
```
1. Set .env variables
2. docker-compose up -d
   ├─ Docker builds image with certificate tools
   ├─ Container starts entrypoint script
   ├─ Entrypoint validates settings
   ├─ Entrypoint generates certs (if needed)
   ├─ Entrypoint generates GPG key (if needed)
   └─ Entrypoint starts Omni service
3. Done!
```

### What Happens on Container Start

```
Container Boot
  ↓
Validate Environment Variables
  ├─ DOMAIN_NAME ✓
  ├─ PUBLIC_IP ✓
  ├─ ACCOUNT_ID ✓ (auto-generate if empty)
  └─ ... (other required vars)
  ↓
Check for Existing Certificates
  ├─ If valid → Use them
  └─ If missing → Generate
      ├─ If Cloudflare credentials set → Let's Encrypt
      └─ If not → Self-signed (fallback)
  ↓
Check for Existing GPG Key
  ├─ If exists → Use it
  └─ If missing → Generate new
  ↓
Start Omni Service
  ├─ Listen on :443 (HTTPS)
  ├─ Listen on :8090 (Siderolink API)
  ├─ Listen on :8100 (K8s Proxy)
  ├─ Health check: /health
  └─ Ready for connections
```

---

## 📁 Directory Structure

```
sidero-omni/
├── Dockerfile                      # Custom image with cert tools
├── docker-compose.yml              # Production config
├── docker-entrypoint.sh            # Smart startup script
├── generate-certs.sh               # Certificate helper
├── generate-gpg-key.sh             # GPG key helper
├── setup.sh                        # Manual setup (optional)
│
├── .env.example                    # Configuration template
├── .env                            # Your configuration (git ignored)
│
├── certs/                          # Generated files (git ignored)
│   ├── tls.crt                     # SSL certificate
│   ├── tls.key                     # SSL private key
│   ├── omni.asc                    # GPG key
│   └── cloudflare.ini              # API credentials
│
├── data/                           # Persistent data (git ignored)
│   ├── etcd/                       # Omni database
│   └── state/                      # Service state
│
└── Documentation/
    ├── README.md                   # This file
    ├── DOCKERFILE_QUICKREF.md      # 2-minute guide
    ├── DOCKERFILE_GUIDE.md         # Complete reference
    ├── DEPLOYMENT_GUIDE.md         # General deployment
    └── DOKPLOY_DEPLOYMENT.md       # Dokploy-specific
```

---

## 🔐 Certificate Options

### Option 1: Automatic Let's Encrypt (Recommended)

```env
ENABLE_CERT_GENERATION=true
CLOUDFLARE_API_TOKEN=your_token
CLOUDFLARE_ZONE_ID=your_zone_id
```

Certificates auto-generate on container start.

### Option 2: Self-Signed (Testing Only)

```env
ENABLE_CERT_GENERATION=true
# Don't set Cloudflare credentials
```

Self-signed certs generated on startup (replace with valid certs for production).

### Option 3: Pre-Generated Certificates

```bash
# Place your certs before starting
cp /path/to/tls.crt certs/
cp /path/to/tls.key certs/
cp /path/to/omni.asc certs/

docker-compose up -d
```

---

## 🔐 Authentication Methods

Choose one (or more) authentication provider:

### Auth0
```env
AUTH0_ENABLED=true
AUTH0_DOMAIN=your-tenant.us.auth0.com
AUTH0_CLIENT_ID=your_client_id
```

### SAML (Azure AD)
```env
SAML_ENABLED=true
SAML_URL=https://login.microsoftonline.com/.../federationmetadata...
```

### OIDC (Keycloak, Okta, etc.)
```env
OIDC_ENABLED=true
OIDC_PROVIDER_URL=https://your-provider.com
OIDC_CLIENT_ID=your_client_id
OIDC_CLIENT_SECRET=your_client_secret
```

See **DEPLOYMENT_GUIDE.md** for detailed setup of each provider.

---

## ☁️ Dokploy Deployment

### One-Click in Dokploy Dashboard

1. **Create Project**
   ```
   Dashboard → Projects → Create New Project
   ```

2. **Add Docker Compose Service**
   ```
   Services → Add Service → Docker Compose
   Source: Git Repository
   Repository: https://github.com/yourusername/sidero-omni
   ```

3. **Configure Environment**
   Copy all variables from your `.env` into Dokploy

4. **Deploy**
   Click Deploy button and watch logs

See **[DOKPLOY_DEPLOYMENT.md](DOKPLOY_DEPLOYMENT.md)** for detailed steps with screenshots.

---

## 📊 Ports & Services

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| 443 | Omni API | TCP/HTTPS | Web interface |
| 8090 | Siderolink API | TCP | Cluster communication |
| 8100 | K8s Proxy | TCP | Kubernetes proxy |
| 8091 | Event Sink | TCP | Event streaming |
| 50180 | WireGuard | UDP | VPN tunnel |

---

## 🔍 Monitoring & Management

### View Logs
```bash
docker-compose logs -f omni
```

### Check Status
```bash
docker-compose ps
```

### Resource Usage
```bash
docker stats sidero-omni
```

### Restart Service
```bash
docker-compose restart omni
```

### Full Restart
```bash
docker-compose down
docker-compose up -d
```

### Rebuild Image
```bash
docker-compose build --no-cache
docker-compose up -d
```

---

## 🛠️ Troubleshooting

### Certificate Generation Fails

**Check DNS:**
```bash
nslookup omni.example.com
# Should return your server IP
```

**Test Cloudflare API:**
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify
```

**View logs:**
```bash
docker-compose logs omni | grep -i "cert\|cloudflare\|error"
```

### Container Won't Start

```bash
# Full logs
docker-compose logs omni

# Check image
docker images | grep omni

# Rebuild
docker-compose build --no-cache
```

### Access Denied After Login

**Verify authentication is configured:**
```bash
docker-compose logs omni | grep -i "auth"
```

**Check .env has at least one auth method enabled:**
```bash
grep "AUTH0_ENABLED\|SAML_ENABLED\|OIDC_ENABLED" .env
```

---

## 🔄 Updates & Maintenance

### Update Omni Version
```bash
# Update .env
OMNI_VERSION=latest

# Rebuild and restart
docker-compose build --no-cache
docker-compose down
docker-compose up -d
```

### Backup Data
```bash
docker-compose down
tar -czf omni-backup-$(date +%s).tar.gz data/
docker-compose up -d
```

### Restore Data
```bash
docker-compose down
tar -xzf omni-backup-*.tar.gz
docker-compose up -d
```

### Renew Certificates
```bash
sudo certbot renew --force-renewal
sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem certs/tls.crt
sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem certs/tls.key
docker-compose restart omni
```

---

## 📦 Dockerfile Details

The custom Dockerfile:
- Extends `ghcr.io/siderolabs/omni:latest`
- Installs certbot and DNS plugins
- Includes certificate generation tools
- Runs smart startup script
- Handles all setup automatically

No need to understand Docker internals - it just works!

---

## ⚙️ Environment Variables

### Certificate Generation (New)
- `ENABLE_CERT_GENERATION` - Enable auto-generation (default: true)
- `CLOUDFLARE_API_TOKEN` - Cloudflare API token
- `CLOUDFLARE_ZONE_ID` - Cloudflare zone ID
- `LETSENCRYPT_EMAIL` - Let's Encrypt email
- `DOMAIN_NAME` - Your domain

### Omni Core
- `OMNI_ACCOUNT_ID` - Unique account ID
- `OMNI_NAME` - Installation name
- `INITIAL_USERS` - Admin user email

### Authentication
- `AUTH0_ENABLED`, `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`
- `SAML_ENABLED`, `SAML_URL`
- `OIDC_ENABLED`, `OIDC_PROVIDER_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`

See **.env.example** for complete list of 50+ variables.

---

## 🤝 Contributing

Found an issue? Have improvements?
1. Fork the repository
2. Make changes
3. Test locally
4. Submit pull request

---

## 📄 License

Sidero Omni is available under the Business Source License (BSL).
Free for non-production environments.
Contact Sidero for production licensing.

---

## 🔗 Resources

- **Omni Docs**: https://omni.siderolabs.com/docs
- **Sidero Labs**: https://siderolabs.com
- **Dokploy**: https://dokploy.com
- **Let's Encrypt**: https://letsencrypt.org
- **Cloudflare**: https://cloudflare.com

---

## 📞 Support

- **Documentation**: See guides above
- **Issues**: Check troubleshooting section
- **Logs**: `docker-compose logs -f omni`
- **GitHub Issues**: Report bugs in repository

---

## 🎉 Quick Reference

| Task | Command |
|------|---------|
| Configure | `cp .env.example .env && nano .env` |
| Deploy | `docker-compose up -d` |
| View logs | `docker-compose logs -f omni` |
| Check status | `docker-compose ps` |
| Restart | `docker-compose restart omni` |
| Stop | `docker-compose down` |
| Rebuild | `docker-compose build --no-cache` |
| Access Omni | `https://your-domain.com` |

---

**Ready to deploy? Start with `.env.example` and `docker-compose up -d`!** 🚀

Last updated: December 2025  
Tested on: Ubuntu 22.04+, Docker 24+, Docker Compose 2.20+
Docker Compose deployment for Sidero Omni
