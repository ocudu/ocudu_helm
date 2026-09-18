#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# Ready means every protected interface that was configured has a child association the
# kernel has actually installed. Anything short of that is not ready.
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

# The child lines are indented under their connection and carry the state as a bare token:
#   f1c: #1, reqid 1, INSTALLED, TUNNEL-in-UDP, ESP:AES_GCM_16-256
missing=""
for child in $expected; do
    grep -qE "^[[:space:]]+${child}:[[:space:]]*#.*[[:space:]]INSTALLED," <<<"$sas" \
        || missing="$missing $child"
done

[ -z "$missing" ] || not_ready "no installed association for:$missing"

echo "ready:$expected"
