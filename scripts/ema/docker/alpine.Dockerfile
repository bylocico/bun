# dockerhub/alpine/Dockerfile, installing this release's own zip instead of
# downloading an oven-sh release. The build context (assembled by
# .github/workflows/ema-release.yml) holds:
#   docker-entrypoint.sh   copied from dockerhub/alpine/
#   SHASUMS256.txt         the release's checksums
#   bun-linux-x64-musl-baseline.zip, bun-linux-aarch64-musl.zip
FROM alpine:3.24 AS build

ARG TARGETARCH

COPY SHASUMS256.txt bun-linux-*.zip /tmp/bun/

RUN apk --no-cache add unzip \
    && case "$TARGETARCH" in \
      amd64) build="x64-musl-baseline";; \
      arm64) build="aarch64-musl";; \
      *) echo "error: unsupported architecture: $TARGETARCH"; exit 1 ;; \
    esac \
    && cd /tmp/bun \
    && grep " bun-linux-$build.zip\$" SHASUMS256.txt | sha256sum -c - \
      || (echo "error: failed to verify: bun-linux-$build.zip" && exit 1) \
    && unzip "bun-linux-$build.zip" \
    && mv "bun-linux-$build/bun" /usr/local/bin/bun \
    && chmod +x /usr/local/bin/bun \
    && rm -rf /tmp/bun

FROM alpine:3.24

# Disable the runtime transpiler cache by default inside Docker containers.
# On ephemeral containers, the cache is not useful
ARG BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
ENV BUN_RUNTIME_TRANSPILER_CACHE_PATH=${BUN_RUNTIME_TRANSPILER_CACHE_PATH}

# Ensure `bun install -g` works
ARG BUN_INSTALL_BIN=/usr/local/bin
ENV BUN_INSTALL_BIN=${BUN_INSTALL_BIN}

COPY --from=build /usr/local/bin/bun /usr/local/bin/
COPY docker-entrypoint.sh /usr/local/bin/
RUN mkdir -p /usr/local/bun-node-fallback-bin && ln -s /usr/local/bin/bun /usr/local/bun-node-fallback-bin/node
ENV PATH "${PATH}:/usr/local/bun-node-fallback-bin"

RUN addgroup -g 1000 bun \
    && adduser -u 1000 -G bun -s /bin/sh -D bun \
    && ln -s /usr/local/bin/bun /usr/local/bin/bunx \
    && apk add libgcc libstdc++ \
    && which bun \
    && which bunx \
    && bun --version

WORKDIR /home/bun/app
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/bun"]
