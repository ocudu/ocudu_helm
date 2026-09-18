#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# Brings up IPsec inside the pod's own network namespace and then runs the IKE daemon in
# the foreground as the container's main process.
#
# This script does not decide anything. The connection configuration arrives as a complete
# swanctl.conf, already rendered, and is used exactly as given. What arrives here instead is
# the part swanctl.conf cannot express: the tunnel interfaces, their addresses and the
# routes onto them. That split is deliberate — swanctl.conf is a typed, documented schema,
# and rebuilding a renderer for it in shell is how a proposal string ends up mis-quoted into
# a weaker cipher than the one that was asked for.
#
# The order below is a security property, not a style choice:
#
#   1. the unreachable-route backstop, before anything else exists
#   2. the tunnel interfaces, addresses and routes
#   3. the credentials
#   4. the daemon
#   5. the configuration
#
# Steps 1 and 2 come first so there is never an instant in which a protected address is
# reachable by a path that does not encrypt. Between process start and step 2 the backstop
# is the only route that matches, and it rejects.

set -euo pipefail

CONFIG_DIR="${IPSEC_CONFIG_DIR:-/etc/ipsec-config}"
LINKS_FILE="${IPSEC_LINKS_FILE:-$CONFIG_DIR/links.conf}"
SWANCTL_CONF="${IPSEC_SWANCTL_CONF:-$CONFIG_DIR/swanctl.conf}"
CREDENTIALS_DIR="${IPSEC_CREDENTIALS_DIR:-/credentials}"
SWANCTL_DIR="${IPSEC_SWANCTL_DIR:-/etc/swanctl}"
PROTECTED_SUPERNET="${IPSEC_PROTECTED_SUPERNET:-100.64.0.0/16}"
UPLINK="${IPSEC_UPLINK:-eth0}"
ENCAP="${IPSEC_ENCAP:-yes}"
TUNNEL_MTU="${IPSEC_TUNNEL_MTU:-}"
VICI_SOCKET="${IPSEC_VICI_SOCKET:-/run/charon.vici}"

log()  { echo "[ipsec] $*"; }
fail() { echo "[ipsec] error: $*" >&2; exit 1; }

# A missing kernel feature is a property of the machine, not of the configuration. Say so,
# because otherwise the next person spends a day editing values files that were never wrong.
fail_prerequisite() {
    echo "[ipsec] error: $1" >&2
    echo "[ipsec] this is a requirement on the machine, not something the configuration" >&2
    echo "[ipsec] can change: the node needs XFRM, XFRM interfaces and ESP available to an" >&2
    echo "[ipsec] unprivileged container holding NET_ADMIN." >&2
    exit 1
}

[ -r "$LINKS_FILE" ]   || fail "$LINKS_FILE is missing or unreadable"
[ -r "$SWANCTL_CONF" ] || fail "$SWANCTL_CONF is missing or unreadable"

# ------------------------------------------------------ 1. the backstop, before anything --
# prohibit, not blackhole. A packet sent to a protected address before its tunnel exists is
# rejected at once with EACCES instead of hanging until something times out, which is the
# difference between a diagnosable failure and a mysterious one. The per-peer routes added
# below are more specific and always win, so this only takes effect in the gap.

ip route replace prohibit "$PROTECTED_SUPERNET" metric 1000 \
    || fail "could not install the backstop route for $PROTECTED_SUPERNET"
log "backstop installed for $PROTECTED_SUPERNET"

# ------------------------------------------------------------------- 2. the tunnel links --
# The MTU is derived from the pod's own uplink, never assumed. A fixed value is wrong on any
# overlay: subtracting this overhead from a 1420-byte pod MTU gives 1355, not 1400. The
# overhead is the worst case for tunnel-mode ESP with AES-GCM — 57 bytes, plus 8 more when
# the ESP is carried inside UDP.

if [ -z "$TUNNEL_MTU" ]; then
    [ -r "/sys/class/net/$UPLINK/mtu" ] || fail "no uplink interface $UPLINK to derive the MTU from"
    pod_mtu=$(cat "/sys/class/net/$UPLINK/mtu")
    if [ "$ENCAP" = "yes" ]; then
        TUNNEL_MTU=$((pod_mtu - 65))
    else
        TUNNEL_MTU=$((pod_mtu - 57))
    fi
    log "uplink $UPLINK MTU $pod_mtu, derived tunnel MTU $TUNNEL_MTU (encap=$ENCAP)"
else
    log "tunnel MTU $TUNNEL_MTU, set explicitly"
fi

# A pod's network namespace outlives its containers, so a restarted sidecar finds its own
# interfaces already there. It has to converge on the configuration it was given rather than
# fail, and rather than trust what it finds: an interface left over from an earlier
# configuration can carry the wrong interface id, and an interface id is what decides which
# traffic gets encrypted.
setup_link() { # ifname if_id local peers
    local ifname=$1 if_id=$2 local_addr=$3 peers=$4
    local existing

    if existing=$(ip -details link show dev "$ifname" 2>/dev/null); then
        # Only ever reshape an interface of our own kind. Something else answering to this
        # name is a naming collision, and quietly deleting it would be a far worse outcome
        # than refusing to start.
        case "$existing" in
            *" xfrm "*) : ;;
            *) fail "$ifname already exists and is not an XFRM interface; refusing to touch it" ;;
        esac

        local found
        found=$(echo "$existing" | sed -n 's/.*if_id \([^ ]*\).*/\1/p' | head -1)
        if [ "$((found))" != "$((if_id))" ]; then
            log "$ifname exists with interface id ${found:-none}, replacing it with $if_id"
            ip link del "$ifname" || fail "could not remove the stale interface $ifname"
            ip link add "$ifname" type xfrm if_id "$if_id" \
                || fail_prerequisite "the kernel refused an XFRM interface for $ifname"
        fi
    else
        ip link add "$ifname" type xfrm if_id "$if_id" \
            || fail_prerequisite "the kernel refused an XFRM interface for $ifname"
    fi

    ip link set dev "$ifname" mtu "$TUNNEL_MTU" || fail "could not set the MTU on $ifname"
    ip addr replace "$local_addr" dev "$ifname" || fail "could not address $ifname"
    ip link set dev "$ifname" up                || fail "could not bring up $ifname"

    local src="${local_addr%%/*}" peer
    local IFS=,
    for peer in $peers; do
        ip route replace "$peer" dev "$ifname" src "$src" \
            || fail "could not route $peer onto $ifname"
    done
}

children=""
while read -r child ifname if_id local_addr peers rest; do
    case "${child:-}" in ''|'#'*) continue ;; esac
    [ -n "${peers:-}" ] || fail "$LINKS_FILE: '$child' needs five columns: child ifname if_id local peer"
    [ -z "${rest:-}" ]  || fail "$LINKS_FILE: '$child' has more than five columns"

    # An interface name over 15 characters is silently truncated by the kernel, and two
    # entries that differ only past that point would then collide.
    [ "${#ifname}" -le 15 ] || fail "$LINKS_FILE: interface name '$ifname' is longer than 15 characters"

    # Checked as text before it is ever used as a number: an arithmetic expansion of
    # something that is not one aborts the shell with its own message instead of this one.
    [[ "$if_id" =~ ^(0[xX][0-9a-fA-F]+|[0-9]+)$ ]] \
        || fail "$LINKS_FILE: '$child' has interface id '$if_id', which is not a number"

    # Interface id 0 means "no interface id" to the kernel, which matches the policies that
    # belong to no interface at all. It is not a usable value here, and it fails openly.
    [ "$((if_id))" -ne 0 ] || fail "$LINKS_FILE: '$child' has interface id 0, which selects no tunnel"

    case " $children " in *" $child "*) fail "$LINKS_FILE: '$child' appears twice" ;; esac

    setup_link "$ifname" "$if_id" "$local_addr" "$peers"
    log "$child on $ifname, interface id $if_id, $local_addr -> $peers"
    children="$children $child"
done < "$LINKS_FILE"

[ -n "$children" ] || fail "$LINKS_FILE defines no interfaces, so nothing would be protected"

# --------------------------------------------------------------------- 3. the credentials --
# Remapped out of the mounted secret into the layout the daemon expects. The mount stays
# read-only and the private key is never copied anywhere the application container can
# reach. No key is ever generated here.

install -d -m 0755 "$SWANCTL_DIR/x509" "$SWANCTL_DIR/x509ca" "$SWANCTL_DIR/private" \
    || fail "could not prepare $SWANCTL_DIR — it has to be writable, see the image README"
install -m 0644 "$CREDENTIALS_DIR/ca.crt"  "$SWANCTL_DIR/x509ca/ca.crt"  || fail "no readable ca.crt in $CREDENTIALS_DIR"
install -m 0644 "$CREDENTIALS_DIR/tls.crt" "$SWANCTL_DIR/x509/cert.crt"  || fail "no readable tls.crt in $CREDENTIALS_DIR"
install -m 0600 "$CREDENTIALS_DIR/tls.key" "$SWANCTL_DIR/private/key.pem" || fail "no readable tls.key in $CREDENTIALS_DIR"
install -m 0644 "$SWANCTL_CONF" "$SWANCTL_DIR/swanctl.conf" || fail "could not place swanctl.conf"
log "credentials and connection configuration in place"

# ------------------------------------------------------------------------- 4. the daemon --

charon-systemd &
charon_pid=$!

terminate() {
    log "stopping the daemon"
    kill -TERM "$charon_pid" 2>/dev/null || true
}
trap terminate TERM INT

# The socket appearing is the only reliable signal that the daemon is ready to be
# configured. A fixed sleep either wastes time or races.
for _ in $(seq 1 50); do
    [ -S "$VICI_SOCKET" ] && break
    sleep 0.2
done
[ -S "$VICI_SOCKET" ] || fail "the daemon never opened $VICI_SOCKET"

# ------------------------------------------------------------------ 5. the configuration --

swanctl --load-all || fail "the daemon rejected the connection configuration"
log "configuration loaded:$children"

# No internal restart loop. If the daemon exits, so does this script, and the container
# restarts with every assertion above re-run from the top. A loop here would turn a repeated
# failure into a quiet one.
#
# wait returns as soon as a trapped signal arrives, so it is called a second time to collect
# the daemon's real exit status.
rc=0
wait "$charon_pid" || rc=$?
if [ "$rc" -gt 128 ]; then
    rc=0
    wait "$charon_pid" || rc=$?
fi
exit "$rc"
