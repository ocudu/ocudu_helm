#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# Started means the sidecar is set up and the daemon accepted everything it was given.
# It deliberately does not mean a tunnel is up — `readiness-ipsec.sh` answers that.
#
# The distinction matters because this check gates the application container. A failing
# startup probe restarts the container, so a check that cannot become true on one side
# turns a slow peer into a crash loop. Two obvious checks have that problem here:
#
#   - an established association is never true on a side that waits to be dialled, and
#   - a policy is not either, because a waiting side installs none until the peer connects.
#
# So this asserts only what is true on both sides within seconds of the daemon starting,
# and what covers the failures that actually happen: a configuration the daemon rejected,
# a daemon that died, an interface that was never created. A rejected configuration is the
# one worth naming — the daemon discards the whole connection, so a single bad value can
# leave it running with nothing loaded at all.

set -uo pipefail

LINKS_FILE="${IPSEC_LINKS_FILE:-${IPSEC_CONFIG_DIR:-/etc/ipsec-config}/links.conf}"

not_started() { echo "not started: $*"; exit 1; }

[ -r "$LINKS_FILE" ] || not_started "$LINKS_FILE is missing or unreadable, so nothing is known about what should exist"

expected=""
ifnames=""
while read -r child ifname _if_id local _rest; do
    case "${child:-}" in ''|'#'*) continue ;; esac
    expected="$expected $child"
    ifnames="$ifnames $ifname:$local"
done < "$LINKS_FILE"

[ -n "$expected" ] || not_started "$LINKS_FILE lists no protected interfaces"

conns=$(swanctl --list-conns 2>&1) || not_started "cannot reach the daemon: $(echo "$conns" | head -1)"

# Every child the chart asked for has to appear in what the daemon loaded. A child section
# the daemon refused takes its whole connection with it, so this is the check that catches
# a bad proposal, a malformed traffic selector or an unparseable address.
missing=""
for child in $expected; do
    grep -qE "^[[:space:]]+${child}:[[:space:]]" <<<"$conns" || missing="$missing $child"
done
[ -z "$missing" ] || not_started "the daemon did not load:$missing — check its log for a rejected value"

# And the plumbing the daemon knows nothing about: the interface exists, is an XFRM
# interface, and carries the address its traffic is supposed to leave from.
for entry in $ifnames; do
    ifname="${entry%%:*}"
    addr="${entry#*:}"
    ip link show dev "$ifname" type xfrm >/dev/null 2>&1 \
        || not_started "$ifname is missing or is not an xfrm interface"
    ip -o addr show dev "$ifname" | grep -qF " ${addr} " \
        || not_started "$ifname does not carry $addr"
done

echo "started:$expected"
