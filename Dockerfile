ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:33e021267790132e63be2cea08e77d64ec5d0434355734e94f8ff2d90c6f8944
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:eb822683575d68ccbdf62b092e1715c676b9650a695d8c0235db4ed5de3e8534
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:7072702dab130c1bbff5e5c4a0adac9c9f2ef59614f24e7ee43d8730fae2764c
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:e8ec2d1d185177605736ba594027f27334e68d7984bbfe708a0b37f4b6f2dbd7

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Mongo
#######################
# FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder-main
# libcurl4-nss-dev liblzma-dev
# arm64, ppc64le, s390x, and x86-64
# XXX unfortunately, mongo is not on bullseye yet

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS builder

RUN           mkdir -p /dist/boot/bin

COPY          --from=builder-tools /boot/bin/goello-server-ng /dist/boot/bin
COPY          --from=builder-tools /boot/bin/http-health   /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

ENV           MONGO_MAJOR=5.0
ENV           MONGO_VERSION=5.0.1

USER          root

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              --mount=type=secret,id=.curlrc \
              apt-get update -qq            && \
              apt-get install -qq --no-install-recommends \
                curl=7.74.0-1.3+b1 \
                gnupg=2.2.27-2      && \
              curl -sSfL https://www.mongodb.org/static/pgp/server-"$MONGO_MAJOR".asc | apt-key add - && \
              echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/$MONGO_MAJOR main" | tee /etc/apt/sources.list.d/mongodb-org.list && \
              # starting with MongoDB 4.3, the postinst for server includes "systemctl daemon-reload" (and we don't have "systemctl")
              ln -s /bin/true /usr/bin/systemctl && \
              apt-get update -qq            && \
              apt-get install -qq --no-install-recommends \
                mongodb-org="$MONGO_VERSION"  && \
              apt-get purge -qq curl gnupg  && \
              apt-get -qq autoremove        && \
              apt-get -qq clean             && \
              rm -rf /var/lib/apt/lists/*   && \
              rm -rf /tmp/*                 && \
              rm -rf /var/tmp/*

USER          dubo-dubon-duponey

COPY          --from=builder --chown=$BUILD_UID:root /dist /

EXPOSE        5000

VOLUME        /data

# mDNS
ENV           MDNS_NAME="Mongo mDNS display name"
ENV           MDNS_HOST="mongo"
ENV           MDNS_TYPE=_mongo._tcp

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

# Log level and port
ENV           LOG_LEVEL=warn
ENV           PORT=5000

ENV           HEALTHCHECK_URL=http://127.0.0.1:5000/

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
