# dockerhub/debian/Dockerfile, installing this release's own zip instead of
# downloading an oven-sh release. The build context (assembled by
# .github/workflows/ema-release.yml) holds:
#   docker-entrypoint.sh   copied from dockerhub/debian/
#   SHASUMS256.txt         the release's checksums
#   bun-linux-x64-baseline.zip, bun-linux-aarch64.zip
FROM debian:trixie-slim AS build

ARG TARGETARCH

COPY SHASUMS256.txt bun-linux-*.zip /tmp/bun/

RUN apt-get update -qq \
    && apt-get install -qq --no-install-recommends unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && case "$TARGETARCH" in \
      amd64) build="x64-baseline";; \
      arm64) build="aarch64";; \
      *) echo "error: unsupported architecture: $TARGETARCH"; exit 1 ;; \
    esac \
    && cd /tmp/bun \
    && grep " bun-linux-$build.zip\$" SHASUMS256.txt | sha256sum -c - \
      || (echo "error: failed to verify: bun-linux-$build.zip" && exit 1) \
    && unzip "bun-linux-$build.zip" \
    && mv "bun-linux-$build/bun" /usr/local/bin/bun \
    && chmod +x /usr/local/bin/bun \
    && rm -rf /tmp/bun

FROM debian:trixie

# Install CA certificates so tools that verify TLS (e.g. apt over HTTPS on
# Debian 13) have a trust store. The base image ships none.
RUN apt-get update -qq \
    && apt-get install -qq --no-install-recommends ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin
COPY --from=build /usr/local/bin/bun /usr/local/bin/bun
RUN mkdir -p /usr/local/bun-node-fallback-bin && ln -s /usr/local/bin/bun /usr/local/bun-node-fallback-bin/node
ENV PATH "${PATH}:/usr/local/bun-node-fallback-bin"

# Disable the runtime transpiler cache by default inside Docker containers.
# On ephemeral containers, the cache is not useful
ARG BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
ENV BUN_RUNTIME_TRANSPILER_CACHE_PATH=${BUN_RUNTIME_TRANSPILER_CACHE_PATH}

# Ensure `bun install -g` works
ARG BUN_INSTALL_BIN=/usr/local/bin
ENV BUN_INSTALL_BIN=${BUN_INSTALL_BIN}

RUN groupadd bun \
      --gid 1000 \
    && useradd bun \
      --uid 1000 \
      --gid bun \
      --shell /bin/sh \
      --create-home \
    && ln -s /usr/local/bin/bun /usr/local/bin/bunx \
    && which bun \
    && which bunx \
    && bun --version

WORKDIR /home/bun/app
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/bun"]
