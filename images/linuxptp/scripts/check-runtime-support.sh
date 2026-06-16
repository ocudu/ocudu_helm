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

rc=0
timeout 3s ptp4l -f "$tmpdir/ptp4l-auth.cfg" -i lo -S -m || rc=$?

case "$rc" in
  0|124)
    echo "PASS: ptp4l accepts Authentication TLV configuration"
    ;;
  *)
    echo "FAIL: ptp4l failed with Authentication TLV configuration"
    exit 1
    ;;
esac

echo "PASS: tc available"
