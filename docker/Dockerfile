FROM debian:trixie-slim

ARG NODE_VERSION
ARG CIRCUITS_VERSION
ARG TARGETARCH

# Install minimal runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Create app directory (owned by root, readable by all)
RUN mkdir -p /app/circuits /app/data

# Map Docker TARGETARCH to Logos release naming
# Download and install node binary + circuits in a single layer
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64)  LOGOS_ARCH="x86_64" ;; \
        arm64)  LOGOS_ARCH="aarch64" ;; \
        *)      echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac; \
    \
    echo "Installing logos-blockchain-node ${NODE_VERSION} for ${LOGOS_ARCH}"; \
    \
    # Download and extract node binary
    curl -fsSL "https://github.com/logos-blockchain/logos-blockchain/releases/download/${NODE_VERSION}/logos-blockchain-node-linux-${LOGOS_ARCH}-${NODE_VERSION}.tar.gz" \
        | tar -xz -C /usr/local/bin/; \
    chmod +x /usr/local/bin/logos-blockchain-node; \
    \
    # Download and extract circuits
    curl -fsSL "https://github.com/logos-blockchain/logos-blockchain/releases/download/${NODE_VERSION}/logos-blockchain-circuits-v${CIRCUITS_VERSION}-linux-${LOGOS_ARCH}.tar.gz" \
        | tar -xz -C /tmp/; \
    mv /tmp/logos-blockchain-circuits-* /app/circuits; \
    chmod -R a+rX /app/circuits

WORKDIR /app

ENV LOGOS_BLOCKCHAIN_CIRCUITS=/app/circuits

# Data volume
VOLUME ["/app/data"]

# API port
EXPOSE 8080
# libp2p UDP port
EXPOSE 3000/udp

ENTRYPOINT ["logos-blockchain-node"]
CMD ["user_config.yaml"]
