#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -e

INTERFACE=$1
LOGFILE=/tmp/ts2phc.stdout
PIPE=/tmp/ts2phc.pipe
HEALTH_FILE=/tmp/ts2phc-healthy

stop_process() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  local rc="${1:-0}"
  trap - SIGTERM SIGINT
  stop_process "${ts2phc_pid:-}"
  stop_process "${liveness_pid:-}"
  stop_process "${tee_pid:-}"
  rm -f "$PIPE" "$HEALTH_FILE"
  exit "$rc"
}

trap 'echo "Received SIGTERM, stopping ts2phc..."; cleanup 0' SIGTERM SIGINT

rm -f "$PIPE" && mkfifo "$PIPE"

stdbuf -oL -eL ts2phc -c "${INTERFACE}" -s nmea -m -f /etc/config/ts2phc.cfg \
  >"$PIPE" 2>&1 &
ts2phc_pid=$!

# tee from the fifo to a file (and to container stdout)
tee -a "$LOGFILE" <"$PIPE" &
tee_pid=$!

liveness-ts2phc.sh "$LOGFILE" &
liveness_pid=$!

# the container exits with ts2phc; tee prints its last lines first
set +e
wait "$ts2phc_pid"
ts2phc_rc=$?
wait "$tee_pid"
set -e

cleanup "$ts2phc_rc"
