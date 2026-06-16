#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -e

UPPER_LIMIT=${PTP4L_OFFSET_LIMIT:-25}
LOWER_LIMIT=-${UPPER_LIMIT}
POLL_INTERVAL=2
HEALTH_FILE=/tmp/ptp4l-healthy
GM_ALLOWLIST_PREF_START=38000
GM_ALLOWLIST_DROP_PREF=38099

gm_allowlist_enabled() {
  [[ "${PTP4L_GM_ALLOWLIST_ENABLED:-false}" == "true" ]]
}

cleanup_gm_allowlist() {
  gm_allowlist_enabled || return 0

  local iface="${PTP4L_GM_ALLOWLIST_INTERFACE:-}"
  [[ -n "$iface" ]] || return 0

  local pref
  for ((pref = GM_ALLOWLIST_PREF_START; pref <= GM_ALLOWLIST_DROP_PREF; pref++)); do
    tc filter del dev "$iface" ingress pref "$pref" 2>/dev/null || true
  done
}

apply_gm_allowlist() {
  gm_allowlist_enabled || return 0

  local mode="${PTP4L_GM_ALLOWLIST_MODE:-tc}"
  local iface="${PTP4L_GM_ALLOWLIST_INTERFACE:-}"
  local ethertype="${PTP4L_GM_ALLOWLIST_PTP_ETHERTYPE:-0x88f7}"
  local allowed_macs="${PTP4L_GM_ALLOWLIST_ALLOWED_SOURCE_MACS:-}"

  if [[ "$mode" != "tc" ]]; then
    echo "Unsupported PTP GM allow-list mode: $mode" >&2
    exit 1
  fi

  if [[ -z "$iface" || -z "$allowed_macs" ]]; then
    echo "PTP GM allow-list requires interface and allowed source MACs" >&2
    exit 1
  fi

  if ! command -v tc >/dev/null 2>&1; then
    echo "PTP GM allow-list requires tc, but tc was not found" >&2
    exit 1
  fi

  tc qdisc add dev "$iface" clsact 2>/dev/null || true
  cleanup_gm_allowlist

  local -a macs
  IFS=',' read -r -a macs <<< "$allowed_macs"

  local index=0
  local mac
  for mac in "${macs[@]}"; do
    [[ -n "$mac" ]] || continue
    tc filter add dev "$iface" ingress pref "$((GM_ALLOWLIST_PREF_START + index))" \
      protocol "$ethertype" flower src_mac "$mac" action pass
    index=$((index + 1))
  done

  tc filter add dev "$iface" ingress pref "$GM_ALLOWLIST_DROP_PREF" \
    protocol "$ethertype" flower action drop
}

cleanup() {
  echo "Received SIGTERM, stopping ptp4l..."
  [[ -n "${monitor_pid:-}" ]] && kill -TERM "$monitor_pid" 2>/dev/null || true
  [[ -n "${ptp4l_pid:-}" ]] && kill -TERM "$ptp4l_pid" 2>/dev/null || true
  wait "${monitor_pid:-}" 2>/dev/null || true
  wait "${ptp4l_pid:-}" 2>/dev/null || true
  rm -f "$HEALTH_FILE"
  cleanup_gm_allowlist
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

apply_gm_allowlist

monitor &
monitor_pid=$!

ptp4l "$@" &
ptp4l_pid=$!

set +e
wait "$ptp4l_pid"
ptp4l_rc=$?
set -e

cleanup_gm_allowlist
exit "$ptp4l_rc"
