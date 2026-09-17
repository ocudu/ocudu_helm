#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# Build-time assertion. The image tag carries a strongSwan version that comes from the
# distribution archive rather than from a source checkout, so nothing makes it true by
# construction. This makes it true by verification instead: if the archive moves, the build
# fails here rather than publishing a tag that quietly says the wrong thing.

set -euo pipefail

fail() { echo "check-runtime-support: $*" >&2; exit 1; }

for binary in charon-systemd swanctl pki ip; do
    command -v "$binary" >/dev/null || fail "$binary not found"
done

# Neither daemon may be present: either one would race the one that is configured.
for unwanted in /usr/sbin/ipsec /usr/lib/ipsec/starter /usr/lib/ipsec/charon; do
    [ -e "$unwanted" ] && fail "$unwanted is installed; it would run a second daemon in the same namespace"
done

# The version comes from the package database, not from the binaries. None of swanctl,
# pki or charon-systemd will report a version without a running daemon to talk to: they
# exit 2, 1 and 66 respectively. The package database is the only thing here that answers
# the question at build time.
packaged=$(dpkg-query -W -f='${Version}' charon-systemd 2>/dev/null || true)
[ -n "$packaged" ] || fail "charon-systemd is not registered in the package database"

# Strip epoch and distribution revision: 1:6.0.4-1ubuntu3.1 -> 6.0.4
reported=${packaged#*:}
reported=${reported%%-*}

if [ -n "${STRONGSWAN_VERSION:-}" ] && [ "$reported" != "$STRONGSWAN_VERSION" ]; then
    fail "installed strongSwan is $reported ($packaged) but the build declares $STRONGSWAN_VERSION"
fi

# Every plugin the configuration relies on must be present in the image. A missing one
# would otherwise surface as a negotiation failure in a cluster, at the point where the
# tunnel is load-bearing, instead of as a failed build.
plugindir=$(find /usr/lib -maxdepth 3 -type d -name plugins -path '*ipsec*' | head -1)
[ -n "$plugindir" ] || fail "no strongSwan plugin directory found"

for plugin in kernel-netlink socket-default vici openssl x509 pem pkcs1 nonce random pubkey; do
    [ -e "$plugindir/libstrongswan-$plugin.so" ] || fail "plugin $plugin missing from $plugindir"
done

echo "check-runtime-support: strongSwan $reported ($packaged), swanctl and pki present, no second daemon,"
echo "check-runtime-support: $(ls "$plugindir" | wc -l) plugins in $plugindir"
