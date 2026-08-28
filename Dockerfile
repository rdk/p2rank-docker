# syntax=docker/dockerfile:1

# P2Rank — ligand binding site prediction from protein structure.
# Upstream: https://github.com/rdk/p2rank

ARG P2RANK_VERSION=2.5.1
ARG JAVA_IMAGE=eclipse-temurin:25-jre-noble

# ---------------------------------------------------------------------------
# Fetch stage. Keeps curl and the 275 MB tarball out of the runtime image.
# ---------------------------------------------------------------------------
FROM alpine:3.21 AS fetch

ARG P2RANK_VERSION
# Checksum of p2rank_${P2RANK_VERSION}.tar.gz. Update it with the version:
#   curl -fsSL <release-url> | sha256sum
ARG P2RANK_SHA256=d243f2d9036ac053fefb9407b5fe1c85f4fe077c519fd975ac585e995feab274

# BuildKit verifies the checksum before the layer is created, so a tampered or
# truncated download fails the build instead of being unpacked. Alpine's busybox
# tar does the extraction, so this stage installs nothing at all.
ADD --checksum=sha256:${P2RANK_SHA256} \
    https://github.com/rdk/p2rank/releases/download/${P2RANK_VERSION}/p2rank_${P2RANK_VERSION}.tar.gz \
    /tmp/p2rank.tar.gz

RUN mkdir -p /opt/p2rank && \
    tar -xzf /tmp/p2rank.tar.gz -C /opt/p2rank --strip-components=1

# ---------------------------------------------------------------------------
# Runtime stage. P2Rank needs a JRE 17+ and a bash launcher, and it bundles
# native libraries (zstd-jni, Netty), so this stays on glibc rather than musl.
# ---------------------------------------------------------------------------
FROM ${JAVA_IMAGE}

ARG P2RANK_VERSION
# Container-aware heap. See the sed below for why this is not a plain -Xmx.
ARG P2RANK_HEAP="-XX:MaxRAMPercentage=75.0"

LABEL org.opencontainers.image.title="P2Rank" \
      org.opencontainers.image.description="Machine learning based tool for rapid and accurate prediction of ligand binding sites from protein structure" \
      org.opencontainers.image.version="${P2RANK_VERSION}" \
      org.opencontainers.image.url="https://github.com/rdk/p2rank" \
      org.opencontainers.image.documentation="https://github.com/rdk/p2rank/blob/master/documentation/user-guide.md" \
      org.opencontainers.image.licenses="MIT"

COPY --from=fetch /opt/p2rank /opt/p2rank

# Put the install directory on PATH. Do NOT symlink the launcher into
# /usr/local/bin: it derives its classpath from `dirname "${BASH_SOURCE[0]}"`,
# which does not follow symlinks, so a symlinked entrypoint breaks the classpath.
ENV PATH="/opt/p2rank:${PATH}"

# The launcher hardcodes `-Xmx2048m` and appends it *after* $JAVA_OPTS, and the
# last -Xmx wins — so out of the box the heap is stuck at 2 GB no matter what
# the caller sets. Swapping in MaxRAMPercentage fixes both problems at once:
# the heap follows the container's memory limit, and because the JVM ignores
# MaxRAMPercentage whenever an explicit -Xmx is present, `JAVA_OPTS=-Xmx8g`
# now works as users expect.
RUN sed -i "s|-Xmx2048m|${P2RANK_HEAP}|" /opt/p2rank/prank

# BioJava caches chemical component definitions here. Pre-create it world
# writable so the image works under any --user, and leave it empty so no
# root-owned entries can block a later run.
RUN mkdir -p /tmp/chemcomp && chmod 1777 /tmp/chemcomp

# Run as a normal user by default. uid 1000 matches the typical single-user
# Linux host, so bind-mounted output lands with sane ownership. Declared
# numerically below so it resolves without a passwd lookup (k8s runAsNonRoot).
RUN userdel -r ubuntu 2>/dev/null || true; \
    groupadd -g 1000 p2rank && \
    useradd -u 1000 -g 1000 -m -s /bin/bash p2rank && \
    mkdir -p /data && chown p2rank:p2rank /data

USER 1000:1000
WORKDIR /data

# Fail the build if P2Rank cannot run. This is a real prediction, executed as
# the unprivileged runtime user, so it exercises the JVM, the classpath, the
# trained model and the filesystem permissions the way users will.
RUN prank predict -f /opt/p2rank/test_data/1fbl.pdb -o /tmp/smoke > /dev/null \
    && test -s /tmp/smoke/1fbl.pdb_predictions.csv \
    && rm -rf /tmp/smoke /tmp/chemcomp/* \
    && echo "P2Rank ${P2RANK_VERSION} OK"

# No ENTRYPOINT on purpose: Nextflow and other workflow engines invoke images
# as `docker run <image> /bin/bash -c '...'`, which an ENTRYPOINT would break.
# For the short form, run with `--entrypoint prank`.
CMD ["prank", "help"]
