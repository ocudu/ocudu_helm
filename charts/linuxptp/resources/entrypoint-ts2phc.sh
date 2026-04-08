#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

INTERFACE=$1

# Function to clean up on SIGTERM
cleanup() {
  echo "Received SIGTERM, stopping ts2phc..."
  if [ -n "$ts2phc_pid" ] && kill -0 "$ts2phc_pid" 2>/dev/null; then
    kill -TERM "$ts2phc_pid"
    kill -TERM "$liveness_pid"
    wait "$ts2phc_pid"
    wait "$liveness_pid"
  fi
  exit 0
}

trap cleanup SIGTERM SIGINT

ts2phc -c "${INTERFACE}" -s nmea -m -f /etc/config/ts2phc.cfg &
ts2phc_pid=$!

cat "/proc/${ts2phc_pid}/fd/1" > /tmp/ts2phc.stdout &

liveness-ts2phc.sh /tmp/ts2phc.stdout &
liveness_pid=$!
wait "$liveness_pid"
