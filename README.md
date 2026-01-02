# Omni On-Prem Deployment

Easy deployment of Sidero Omni on-premises using Docker Compose with automated certificate handling.

## Prerequisites

- Docker and Docker Compose installed
- OpenSSL (for self-signed certificates)
- GPG (for etcd encryption key generation)
- For production: Valid SSL certificates (or use self-signed for testing)

## Quick Start

### 1. Clone or Download

Ensure you have the deployment files:
- `docker-compose.yml`
- `.env.example`
- `deploy.sh`

### 2. Run Deployment Script

The deployment script automates the entire setup process:

```bash
# For testing with self-signed certificates
./deploy.sh --self-signed

# For production with existing certificates
./deploy.sh --production
```

### 3. Access Omni

Once deployed, access Omni at:
- Web UI: `https://<your-domain>`
- API: `https://<your-domain>/api`

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure the following variables:

| Variable | Description | Required |
|----------|-------------|----------|
| `OMNI_VERSION` | Omni container version (use `latest` or specific version like `v1.0.0`) | Yes |
| `OMNI_DOMAIN_NAME` | Domain name for Omni | Yes |
| `OMNI_WG_IP` | WireGuard IP address | Yes |
| `OMNI_ADMIN_EMAIL` | Admin user email | Yes |
| `AUTH0_DOMAIN` | Auth0 domain | Yes (if using Auth0) |
| `AUTH0_CLIENT_ID` | Auth0 client ID | Yes (if using Auth0) |
| `TLS_CERT_PATH` | Path to TLS certificate | Yes |
| `TLS_KEY_PATH` | Path to TLS private key | Yes |
| `GPG_KEY_PATH` | Path to GPG encryption key | Yes |

### Authentication Setup

#### Auth0 (Default)

1. Create an [Auth0 account](https://auth0.com/signup)
2. Create a "Single Page Web Application"
3. Configure:
   - Allowed callback URLs: `https://<your-domain>`
   - Allowed web origins: `https://<your-domain>`
   - Allowed logout URLs: `https://<your-domain>`
4. Enable GitHub/Google login in Authentication → Social
5. Copy your Domain and Client ID to `.env`

#### SAML

To use SAML instead of Auth0, modify `docker-compose.yml` to use SAML flags:
- `--auth-saml-enabled=true`
- `--auth-saml-url=<your-saml-metadata-url>`

## Deployment Modes

### Self-Signed Certificates (Testing)

The script automatically generates self-signed certificates valid for 365 days:

```bash
./deploy.sh --self-signed
```

**Note:** Self-signed certificates will show browser warnings. This is normal for testing.

### Production Certificates

For production, you need valid SSL certificates. Options:

1. **Use Let's Encrypt with Certbot:**
   ```bash
   sudo certbot certonly --standalone -d <your-domain>
   ```
   Then point `TLS_CERT_PATH` and `TLS_KEY_PATH` to your certificates.

2. **Use existing certificates:**
   Place your certificate and key files in the `certs/` directory and update paths in `.env`.

Then deploy:
```bash
./deploy.sh --production
```

## Manual Deployment

If you prefer to deploy manually:

1. Copy `.env.example` to `.env` and configure variables
2. Generate GPG key (if not exists):
   ```bash
   gpg --quick-generate-key "Omni (Used for etcd data encryption) omni@example.com" rsa4096 cert never
   gpg --list-secret-keys  # Get fingerprint
   gpg --quick-add-key <fingerprint> rsa4096 encr never
   gpg --export-secret-key --armor omni@example.com > omni.asc
   ```
3. Ensure certificates are in place
4. Run:
   ```bash
   docker compose --env-file .env up -d
   ```

## Directory Structure

After deployment, you'll have:

```
.
├── docker-compose.yml
├── .env
├── .env.example
├── deploy.sh
├── omni.asc          # GPG encryption key (auto-generated)
├── certs/            # Certificate directory
│   ├── tls.crt       # TLS certificate
│   └── tls.key       # TLS private key
├── etcd/             # etcd data directory
└── sqlite/           # SQLite database directory
    └── omni.db       # Omni SQLite database
```

## Troubleshooting

### Docker Compose network_mode error in Dokploy

If you get an error like `"service omni declares mutually exclusive network_mode and networks"` when deploying with Dokploy:

This is a known issue with some versions of Dokploy that automatically create networks. The compose file is correct, but Dokploy may be injecting network configurations.

**Possible solutions:**
1. Check if Dokploy has a setting to disable automatic network creation
2. Try using a different deployment method (direct Docker Compose)
3. Contact Dokploy support about this issue

The compose file uses `network_mode: host` which is required for Omni's WireGuard functionality.

### Container won't start

- Check logs: `docker compose logs omni`
- Verify all environment variables are set in `.env`
- Ensure certificates exist and are readable
- Check that ports 443, 8090, 8100, and 50180 are available

### Certificate errors

- For self-signed: Browser warnings are expected
- For production: Ensure certificates are valid and not expired
- Verify certificate paths in `.env` are correct

### Authentication issues

- Verify Auth0 credentials are correct
- Check callback URLs match your domain
- Ensure Auth0 application is configured correctly

### GPG key issues

- The script auto-generates the key if missing
- Ensure GPG is installed: `gpg --version`
- Check key file exists: `ls -la omni.asc`

**If you get "private key checksum failure" errors:**

This usually happens when the GPG key file has Windows line endings (CRLF) instead of Unix line endings (LF). To fix:

1. **Option 1: Fix line endings (if you have the original key):**
   ```bash
   # On Linux/Mac or WSL
   dos2unix omni.asc
   # Or using sed
   sed -i 's/\r$//' omni.asc
   ```

2. **Option 2: Regenerate the key (will require clearing etcd data):**
   ```bash
   # Backup existing etcd data if needed
   mv etcd etcd.backup
   # Remove the corrupted key
   rm omni.asc
   # Regenerate using deploy.sh
   ./deploy.sh --production  # or --self-signed
   ```

3. **Option 3: Ensure proper line endings in Git:**
   - The `.gitattributes` file ensures `omni.asc` uses LF line endings
   - If the file is already in Git with wrong endings, fix it:
     ```bash
     git rm --cached omni.asc
     dos2unix omni.asc  # or sed -i 's/\r$//' omni.asc
     git add omni.asc
     ```

## Stopping and Removing

```bash
# Stop containers
docker compose down

# Remove containers and volumes (WARNING: deletes etcd data)
docker compose down -v
```

## Updating Omni

1. Update `OMNI_VERSION` in `.env`
2. Run: `docker compose --env-file .env up -d --pull always`

## License

Omni is available via a [Business Source License](https://github.com/siderolabs/omni/blob/main/LICENSE) which allows free installations in non-production environments. For production use, please contact [Sidero sales](mailto:sales@siderolabs.com).

## Support

For issues and questions:
- [Omni Documentation](https://omni.siderolabs.com/docs/)
- [Sidero Labs](https://www.siderolabs.com/)

