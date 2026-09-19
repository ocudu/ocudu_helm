#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# Ready means every protected interface that was configured is actually protected by the
# kernel. Anything short of that is not ready.
#
# "Protected" is deliberately wider than "has a live association". A child is negotiated
# when traffic first matches it, so an interface that has never carried a packet has a
# policy in the kernel and no association — and it is protected: a packet to its address is
# encrypted or dropped, never sent in clear. Requiring an association here would hold the
# pod unready for ever on any interface that has no traffic yet, which is the normal state
# of F1-U with no user attached.
#
# The list of what must be up is read from the same file that created the interfaces, not
# from the daemon. Asking the daemon what it loaded and then checking those are up is a
# check that cannot fail for the reason it exists: a configuration that never loaded reports
# no children at all, and every one of them is fine. The same logic applies to this script
# not being able to reach the daemon, or not finding its configuration — none of those mean
# ready, they mean nothing was measured.

set -uo pipefail

LINKS_FILE="${IPSEC_LINKS_FILE:-${IPSEC_CONFIG_DIR:-/etc/ipsec-config}/links.conf}"

not_ready() { echo "not ready: $*"; exit 1; }

[ -r "$LINKS_FILE" ] || not_ready "$LINKS_FILE is missing or unreadable, so nothing is known about what should be up"

expected=""
while read -r child _rest; do
    case "${child:-}" in ''|'#'*) continue ;; esac
    expected="$expected $child"
done < "$LINKS_FILE"

[ -n "$expected" ] || not_ready "$LINKS_FILE lists no protected interfaces"

sas=$(swanctl --list-sas 2>&1) || not_ready "cannot reach the daemon: $(echo "$sas" | head -1)"
pols=$(swanctl --list-pols 2>&1) || not_ready "cannot reach the daemon: $(echo "$pols" | head -1)"

# An association. The child lines are indented under their connection and carry the state
# as a bare token:
#   f1c: #1, reqid 1, INSTALLED, TUNNEL-in-UDP, ESP:AES_GCM_16-256
has_sa() { grep -qE "^[[:space:]]+${1}:[[:space:]]*#.*[[:space:]]INSTALLED," <<<"$sas"; }

# Or a policy, which is what protects an interface that has not carried traffic yet:
#   f1/f1u, reqid 2, TUNNEL
has_policy() { grep -qE "^[^[:space:]]*/${1},[[:space:]]+reqid[[:space:]]" <<<"$pols"; }

# A policy on its own is not enough to call this ready. The policies are installed when the
# configuration loads, so they are there whether or not the peer was ever reached — an
# interface whose tunnel has never come up would otherwise report ready for ever. It is
# still protected, which is why nothing here enforces anything, but it is not working.
grep -qE '^[^[:space:]]+: #[0-9]+, ESTABLISHED,' <<<"$sas" \
    || not_ready "no established IKE association, so no tunnel has come up yet"

missing=""
trapped=""
for child in $expected; do
    if has_sa "$child"; then
        continue
    elif has_policy "$child"; then
        trapped="$trapped $child"
    else
        missing="$missing $child"
    fi
done

[ -z "$missing" ] || not_ready "neither an association nor a policy for:$missing"

if [ -n "$trapped" ]; then
    echo "ready:$expected (policy only, no traffic yet:$trapped)"
else
    echo "ready:$expected"
fi
