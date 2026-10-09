#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -e

INTERFACE=$1
NTP_SERVER=${2}
LOGFILE=/tmp/phc2sys.stdout
PIPE=/tmp/phc2sys.pipe
HEALTH_FILE=/tmp/phc2sys-healthy

stop_process() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  local rc="${1:-0}"
  trap - SIGTERM SIGINT
  stop_process "${phc2sys_pid:-}"
  stop_process "${liveness_pid:-}"
  stop_process "${tee_pid:-}"
  rm -f "$PIPE" "$HEALTH_FILE"
  exit "$rc"
}

trap 'echo "Received SIGTERM, stopping phc2sys..."; cleanup 0' SIGTERM SIGINT

if [ -n "${NTP_SERVER}" ]; then
  ntpdate "${NTP_SERVER}"
  phc_ctl "${INTERFACE}" set
fi

# make sure we always get lines promptly
rm -f "$PIPE" && mkfifo "$PIPE"

# start phc2sys, write to the fifo (add -u 1 for periodic lines)
stdbuf -oL -eL phc2sys -s "${INTERFACE}" -c CLOCK_REALTIME -w -m -u 1 -f /etc/config/linuxptp.cfg \
  >"$PIPE" 2>&1 &
phc2sys_pid=$!

# tee from the fifo to a file (and to container stdout)
tee -a "$LOGFILE" <"$PIPE" &
tee_pid=$!

liveness-phc2sys.sh "$LOGFILE" &
liveness_pid=$!

# the container exits with phc2sys; tee prints its last lines first
set +e
wait "$phc2sys_pid"
phc2sys_rc=$?
wait "$tee_pid"
set -e

cleanup "$phc2sys_rc"
