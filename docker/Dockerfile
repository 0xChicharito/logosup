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
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
        amd64)  LOGOS_ARCH="x86_64" ;; \
        arm64)  LOGOS_ARCH="aarch64" ;; \
        *)      echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac; \
    \
    echo "Installing logos-blockchain-node ${NODE_VERSION} for ${LOGOS_ARCH}"; \
    \
    # 1. Tải và giải nén Node (Tách rời tải và giải nén để bắt lỗi)
    NODE_URL="https://github.com/logos-blockchain/logos-blockchain/releases/download/${NODE_VERSION}/logos-blockchain-node-linux-${LOGOS_ARCH}-${NODE_VERSION}.tar.gz"; \
    echo "Downloading Node from: $NODE_URL"; \
    curl -fL -o /tmp/node.tar.gz "$NODE_URL"; \
    tar -xzf /tmp/node.tar.gz -C /usr/local/bin/; \
    chmod +x /usr/local/bin/logos-blockchain-node; \
    rm -f /tmp/node.tar.gz; \
    \
    # 2. Tải và giải nén Circuits
    CIRCUITS_URL="https://github.com/logos-blockchain/logos-blockchain/releases/download/${NODE_VERSION}/logos-blockchain-circuits-v${CIRCUITS_VERSION}-linux-${LOGOS_ARCH}.tar.gz"; \
    echo "Downloading Circuits from: $CIRCUITS_URL"; \
    curl -fL -o /tmp/circuits.tar.gz "$CIRCUITS_URL"; \
    tar -xzf /tmp/circuits.tar.gz -C /tmp/; \
    \
    # 3. Di chuyển file vào đúng thư mục
    # Dùng find để tìm mọi file/thư mục vừa giải nén và chuyển vào /app/circuits
    mv /tmp/logos-blockchain-circuits-*/* /app/circuits/ 2>/dev/null || echo "Info: No wrapper directory found, files might be extracted differently."; \
    rm -rf /tmp/logos-blockchain-circuits-* /tmp/circuits.tar.gz; \
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
