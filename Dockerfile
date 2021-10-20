ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:1609d1af44c0048ec0f2e208e6d4e6a525c6d6b1c0afcc9d71fccf985a8b0643
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:2c95e3bf69bc3a463b00f3f199e0dc01cab773b6a0f583904ba6766b3401cb7b
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:5c54594a24e3dde2a82e2027edd6d04832204157e33775edc66f716fa938abba
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:4de02189b785c865257810d009e56f424d29a804cc2645efb7f67b71b785abde

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

EXPOSE        27017

VOLUME        /data

ENV           _SERVICE_NICK="mongo"
ENV           _SERVICE_TYPE="database"

### mDNS broadcasting
# Type to advertise
ENV           MDNS_TYPE="_$_SERVICE_TYPE._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$_SERVICE_NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$_SERVICE_NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

# Log level and port
ENV           LOG_LEVEL=warn
ENV           PORT=27017

ENV           HEALTHCHECK_URL=http://127.0.0.1:27017/

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
