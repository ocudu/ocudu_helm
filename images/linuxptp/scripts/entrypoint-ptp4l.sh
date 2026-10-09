#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -e

UPPER_LIMIT=${PTP4L_OFFSET_LIMIT:-25}
LOWER_LIMIT=-${UPPER_LIMIT}
DELAY_LIMIT=${PTP4L_MEAN_PATH_DELAY_LIMIT:-0}
POLL_INTERVAL=2
STATUS_INTERVAL=60
HEALTH_FILE=/tmp/ptp4l-healthy
ALIVE_FILE=/tmp/ptp4l-alive
ALIVE_MAX_MISSES=3

stop_process() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  local rc="${1:-0}"
  trap - SIGTERM SIGINT
  stop_process "${ptp4l_pid:-}"
  stop_process "${monitor_pid:-}"
  rm -f "$HEALTH_FILE" "$ALIVE_FILE"
  exit "$rc"
}

trap 'echo "Received SIGTERM, stopping ptp4l..."; cleanup 0' SIGTERM SIGINT

log() {
  echo "ptp4l monitor: $*"
}

# field <pmc reply> <name>: first value of a field, i.e. the first port
field() {
  grep -oP "^\s+$2\s+\K\S+" <<< "$1" | head -1
}

# compare <value> <operator> <limit>: decimal comparison
compare() {
  [[ -n "$1" ]] && (( $(echo "$1 $2 $3" | bc -l) ))
}

# log_change <name> <previous> <current>
log_change() {
  [[ -n "$2" && -n "$3" && "$2" != "$3" ]] || return 0
  log "$1 $2 -> $3"
}

# log_increase <name> <previous> <current>
log_increase() {
  [[ "$2" =~ ^[0-9]+$ && "$3" =~ ^[0-9]+$ ]] && (( $3 > $2 )) || return 0
  log "$1 +$(($3 - $2)) (total $3)"
}

# ALIVE_FILE: ptp4l answers management requests (liveness).
# HEALTH_FILE: ptp4l is synchronized within the offset and path delay limits
# (startup and readiness).
# Port state, parent, grandmaster, receipt timeouts and health changes are
# logged when they happen, with a status line every STATUS_INTERVAL seconds.
# With several interfaces the first port is reported.
monitor() {
  local misses=0 healthy=0 next_status=0
  local reply state offset delay parent gm class announce sync reason
  local prev_state="" prev_parent="" prev_gm="" prev_class=""
  local prev_announce="" prev_sync=""
  while true; do
    reply=$(pmc -u -b 0 -f /etc/config/linuxptp.cfg 'GET PORT_DATA_SET' \
      'GET CURRENT_DATA_SET' 'GET PARENT_DATA_SET' 'GET PORT_SERVICE_STATS_NP' \
      2>/dev/null) || true
    state=$(field "$reply" portState)
    offset=$(field "$reply" offsetFromMaster)
    delay=$(field "$reply" meanPathDelay)
    parent=$(field "$reply" parentPortIdentity)
    gm=$(field "$reply" grandmasterIdentity)
    class=$(field "$reply" 'gm\.ClockClass')
    announce=$(field "$reply" announce_timeout)
    sync=$(field "$reply" sync_timeout)

    if [[ -n "$state" ]]; then
      (( misses < ALIVE_MAX_MISSES )) || log "ptp4l answers management requests again"
      misses=0
      touch "$ALIVE_FILE"
    else
      misses=$((misses + 1))
      if (( misses == ALIVE_MAX_MISSES )); then
        log "no management reply from ptp4l in $misses polls"
      fi
      (( misses < ALIVE_MAX_MISSES )) || rm -f "$ALIVE_FILE"
    fi

    # The announce timer also expires while no master is known, so only
    # timeouts of a synchronizing port are events.
    if [[ "$prev_state" == SLAVE || "$prev_state" == UNCALIBRATED ]]; then
      log_increase "announce timeouts" "$prev_announce" "$announce"
      log_increase "sync timeouts" "$prev_sync" "$sync"
    fi
    log_change "port state" "$prev_state" "$state"
    log_change "parent" "$prev_parent" "$parent"
    log_change "grandmaster" "$prev_gm" "$gm"
    log_change "grandmaster clock class" "$prev_class" "$class"

    if [[ -z "$state" ]]; then
      reason="no management reply"
    elif [[ "$state" != SLAVE ]]; then
      reason="port state $state"
    elif [[ -z "$offset" ]]; then
      reason="no offset"
    elif ! compare "$offset" '<=' "$UPPER_LIMIT" || ! compare "$offset" '>=' "$LOWER_LIMIT"; then
      reason="offset $offset ns outside +/-$UPPER_LIMIT ns"
    elif compare "$DELAY_LIMIT" '>' 0 && ! compare "$delay" '<=' "$DELAY_LIMIT"; then
      reason="path delay $delay ns above $DELAY_LIMIT ns"
    else
      reason=""
    fi

    if [[ -z "$reason" ]]; then
      (( healthy )) || log "healthy: offset $offset ns"
      healthy=1
      touch "$HEALTH_FILE"
    else
      (( ! healthy )) || log "unhealthy: $reason"
      healthy=0
      rm -f "$HEALTH_FILE"
    fi

    prev_state=${state:-$prev_state}
    prev_parent=${parent:-$prev_parent}
    prev_gm=${gm:-$prev_gm}
    prev_class=${class:-$prev_class}
    prev_announce=${announce:-$prev_announce}
    prev_sync=${sync:-$prev_sync}

    if [[ -n "$prev_state" ]] && (( SECONDS >= next_status )); then
      if [[ -n "$state" ]]; then
        log "status $state offset ${offset:--} ns path delay ${delay:--} ns" \
          "parent ${parent:--} grandmaster ${gm:--} class ${class:--}" \
          "announce timeouts ${announce:--} sync timeouts ${sync:--}"
      else
        log "status no management reply"
      fi
      next_status=$((SECONDS + STATUS_INTERVAL))
    fi

    sleep "$POLL_INTERVAL"
  done
}

monitor &
monitor_pid=$!

ptp4l "$@" &
ptp4l_pid=$!

set +e
wait "$ptp4l_pid"
ptp4l_rc=$?
set -e

cleanup "$ptp4l_rc"
