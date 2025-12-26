# Build stage: prepare scripts and tools
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    certbot \
    python3-certbot-dns-cloudflare \
    openssl \
    gnupg \
    uuid-runtime \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create directories for certs and scripts
RUN mkdir -p /etc/omni/tls /scripts

# Copy scripts from build context
COPY docker-entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/entrypoint.sh

COPY generate-certs.sh /scripts/generate-certs.sh
RUN chmod +x /scripts/generate-certs.sh

COPY generate-gpg-key.sh /scripts/generate-gpg-key.sh
RUN chmod +x /scripts/generate-gpg-key.sh

# Final stage: use omni base image
FROM ghcr.io/siderolabs/omni:latest

# Copy bash and runtime libraries from builder
COPY --from=builder /bin/bash /bin/bash
COPY --from=builder /bin/sh /bin/sh
COPY --from=builder /bin/mkdir /bin/mkdir
COPY --from=builder /bin/chmod /bin/chmod
COPY --from=builder /usr/bin/curl /usr/bin/curl
# Copy essential binaries and libraries from builder
COPY --from=builder /bin /bin
COPY --from=builder /usr/bin /usr/bin
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /lib/x86_64-linux-gnu /lib/x86_64-linux-gnu
COPY --from=builder /usr/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu
COPY --from=builder /lib64 /lib64
COPY --from=builder /etc/ssl /etc/ssl
COPY --from=builder /usr/share/ca-certificates /usr/share/ca-certificates
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /usr/lib/ssl /usr/lib/ssl

# Copy scripts and tools from builder
COPY --from=builder /scripts /scripts
COPY --from=builder /etc/omni/tls /etc/omni/tls
COPY --from=builder /usr/lib/python3 /usr/lib/python3
COPY --from=builder /usr/lib/python3.11 /usr/lib/python3.11

# Set working directory
WORKDIR /workspace

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=40s \
    CMD curl -f https://localhost/health -k || exit 1

# Use our custom entrypoint
ENTRYPOINT ["/bin/bash", "/scripts/entrypoint.sh"]
