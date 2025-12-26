# Quick Reference - One-Click Dockerfile Deployment

## TL;DR - Get Running in 2 Minutes

### 1. Configure
```bash
cp .env.example .env
# Edit .env with your domain and credentials
nano .env
```

### 2. Deploy
```bash
docker-compose up -d
```

**That's it!** The Dockerfile will automatically:
- ✅ Generate SSL certificates from Let's Encrypt
- ✅ Create GPG encryption keys
- ✅ Start Omni service

---

## What's New

| Before | After |
|--------|-------|
| Run `./setup.sh` | (not needed) |
| Wait for certs | Automatic on startup |
| `docker-compose up` | One command does it all |

---

## Minimal .env Configuration

```env
DOMAIN_NAME=omni.example.com
PUBLIC_IP=203.0.113.42
CLOUDFLARE_API_TOKEN=your_token
CLOUDFLARE_ZONE_ID=your_zone_id
LETSENCRYPT_EMAIL=admin@example.com
INITIAL_USERS=admin@example.com
AUTH0_ENABLED=true
AUTH0_DOMAIN=your-tenant.us.auth0.com
AUTH0_CLIENT_ID=your_client_id
```

---

## Verify Deployment

```bash
# Watch startup
docker-compose logs -f omni

# Should see:
# [OMNI] ✓ Certificates generated and installed
# [OMNI] ✓ GPG key generated
# [OMNI] ✓ Pre-flight checks complete, starting Omni
```

---

## Dokploy One-Click

1. Create project in Dokploy
2. Add Docker Compose service from Git
3. Paste `.env` variables into Dokploy
4. Click Deploy
5. Watch logs - done!

---

## Files

```
Dockerfile              → Custom image with cert tools
docker-entrypoint.sh   → Auto-setup on startup
docker-compose.yml     → Uses custom Dockerfile
.env.example           → Configuration template
DOCKERFILE_GUIDE.md    → Complete guide
```

---

## Troubleshooting

**Certificates won't generate?**
```bash
# Check logs
docker-compose logs omni | tail -20

# Verify DNS
nslookup omni.example.com
```

**Need self-signed certs?**
```env
ENABLE_CERT_GENERATION=true
# Don't set Cloudflare credentials
```

**Want to use existing certs?**
```bash
# Place in ./certs/
cp /path/to/tls.crt certs/
cp /path/to/tls.key certs/
cp /path/to/omni.asc certs/
docker-compose up -d
```

---

## Key Differences from Old Setup

### Old Way (Still Works)
```bash
./setup.sh              # Manual cert generation
docker-compose up -d    # Start service
```

### New Way (Recommended)
```bash
docker-compose up -d    # Everything automatic!
```

### Benefits of Dockerfile Approach
- ✅ No pre-generation needed
- ✅ One-click deployment
- ✅ Perfect for Dokploy
- ✅ Self-healing (regenerates if certs missing)
- ✅ No manual steps
- ✅ Works with CI/CD

---

## Troubleshooting Matrix

| Problem | Solution |
|---------|----------|
| Build fails | Check Dockerfile syntax: `docker build .` |
| Certs don't generate | Verify DNS: `nslookup domain` |
| Cloudflare error | Test API: `curl -H "Authorization: Bearer TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify` |
| Permission denied | Ensure correct file permissions |
| Container won't start | Check logs: `docker-compose logs omni` |

---

## Documentation Files

- **DOCKERFILE_GUIDE.md** - Complete Dockerfile guide
- **DEPLOYMENT_GUIDE.md** - General deployment guide
- **DOKPLOY_DEPLOYMENT.md** - Dokploy-specific guide
- **setup.sh** - Old method (still available)

---

## Support

```bash
# Full logs
docker-compose logs -f omni

# System info
docker-compose ps
docker stats

# Rebuild
docker-compose build --no-cache
```

---

**Ready to deploy?** Start with `.env` configuration, then `docker-compose up -d`! 🚀
