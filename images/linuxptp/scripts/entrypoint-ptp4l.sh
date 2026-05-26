#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -e

UPPER_LIMIT=${PTP4L_OFFSET_LIMIT:-25}
LOWER_LIMIT=-${UPPER_LIMIT}
POLL_INTERVAL=2
HEALTH_FILE=/tmp/ptp4l-healthy

cleanup() {
  echo "Received SIGTERM, stopping ptp4l..."
  [[ -n "${monitor_pid:-}" ]] && kill -TERM "$monitor_pid" 2>/dev/null || true
  [[ -n "${ptp4l_pid:-}" ]] && kill -TERM "$ptp4l_pid" 2>/dev/null || true
  wait "${monitor_pid:-}" 2>/dev/null || true
  wait "${ptp4l_pid:-}" 2>/dev/null || true
  rm -f "$HEALTH_FILE"
  exit 0
}

trap cleanup SIGTERM SIGINT

monitor() {
  while true; do
    state=$(pmc -u -b 0 'GET PORT_DATA_SET' -f /etc/config/linuxptp.cfg 2>/dev/null \
      | grep -oP 'portState\s+\K\w+' | head -1)

    if [[ "$state" != "SLAVE" ]]; then
      rm -f "$HEALTH_FILE"
      sleep "$POLL_INTERVAL"
      continue
    fi

    offset=$(pmc -u -b 0 'GET CURRENT_DATA_SET' -f /etc/config/linuxptp.cfg 2>/dev/null \
      | grep -oP 'offsetFromMaster\s+\K[-0-9.]+' | head -1)

    if [[ -n "$offset" ]] \
        && (( $(echo "$offset <= $UPPER_LIMIT" | bc -l) )) \
        && (( $(echo "$offset >= $LOWER_LIMIT" | bc -l) )); then
      touch "$HEALTH_FILE"
    else
      rm -f "$HEALTH_FILE"
    fi

    sleep "$POLL_INTERVAL"
  done
}

monitor &
monitor_pid=$!

ptp4l "$@" &
ptp4l_pid=$!

wait "$ptp4l_pid"
