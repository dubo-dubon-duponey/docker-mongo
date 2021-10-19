#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

helpers::dir::writable /data

# mDNS blast if asked to
[ ! "$MDNS_HOST" ] || {
  [ ! "${MDNS_STATION:-}" ] || mdns::add "_workstation._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "$PORT"
  mdns::add "${MDNS_TYPE:-_http._tcp}" "$MDNS_HOST" "${MDNS_NAME:-}" "$PORT"
  mdns::start &
}

#if [ "${USERNAME:-}" ]; then
#  export REGISTRY_AUTH=htpasswd
#  export REGISTRY_AUTH_HTPASSWD_REALM="$REALM"
#  export REGISTRY_AUTH_HTPASSWD_PATH=/data/htpasswd
#  printf "%s:%s\n" "$USERNAME" "$(printf "%s" "$PASSWORD" | base64 -d)" > /data/htpasswd
#fi

# args=()

# Run once configured
exec mongod --config /config/mongod.conf --port "$PORT" --pidfilepath /data/mongo.pid --nounixsocket --bind_ip_all --auth
