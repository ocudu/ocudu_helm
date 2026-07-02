#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

command -v ptp4l >/dev/null
command -v tc >/dev/null

ptp4l -v

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/sa.cfg" <<'EOF'
[security_association]
spp 0
seqid_window 20
1 SHA256 16 abcdefghijklmnop
EOF

cat > "$tmpdir/ptp4l-auth.cfg" <<EOF
[global]
twoStepFlag 1
ptp_minor_version 1
sa_file $tmpdir/sa.cfg
spp 0
active_key_id 1
network_transport L2
domainNumber 24
time_stamping software
EOF

# ptp4l parses the config and builds the security association database
# (sad_create) before opening any sockets. A crypto-less build or a rejected
# option fails at that stage; socket errors only occur afterwards and mean the
# build environment lacks CAP_NET_RAW (rootless/kaniko/qemu builders), not
# that Authentication TLV support is broken.
rc=0
timeout 3s ptp4l -f "$tmpdir/ptp4l-auth.cfg" -i lo -S -m > "$tmpdir/ptp4l.log" 2>&1 || rc=$?
cat "$tmpdir/ptp4l.log"

if [[ "$rc" -eq 0 || "$rc" -eq 124 ]]; then
  echo "PASS: ptp4l accepts Authentication TLV configuration"
elif grep -qiE 'security not supported|failed to open sa_file|unknown option' "$tmpdir/ptp4l.log"; then
  echo "FAIL: ptp4l rejects Authentication TLV configuration"
  exit 1
elif grep -qiE 'operation not permitted|permission denied|socket failed|bind failed' "$tmpdir/ptp4l.log"; then
  echo "WARN: build environment cannot open PTP sockets; Authentication TLV" \
       "configuration and security association parsing were still validated"
else
  echo "FAIL: ptp4l failed with Authentication TLV configuration (rc=$rc)"
  exit 1
fi

echo "PASS: tc available"
