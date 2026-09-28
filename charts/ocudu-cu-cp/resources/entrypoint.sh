#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# This script runs the OCUDU CU-CP (ocucp) binary with the provided configuration file.
# - If PRESERVE_OLD_LOGS=true, log file paths are updated with a timestamp and a
#   'current' symlink is created for easy navigation.
# - The runtime config is written to ${OCUDU_WORK_DIR} (falling back to ${OCUDU_LOG_DIR}),
#   keeping the log volume free of mutable runtime state.
# - The rendered config is snapshotted to ${OCUDU_LOG_DIR}/cu-cp-config-rendered.yml.
# - The binary is restarted automatically on clean exit.
# - SIGTERM/SIGINT are forwarded gracefully to the ocucp process.
#
# Usage: ./entrypoint.sh /etc/config/cu-cp-config.yml

#==============================================================================
# Logging Functions
#==============================================================================

readonly LOG_INFO="INFO"
readonly LOG_WARN="WARN"
readonly LOG_ERROR="ERROR"
readonly LOG_FATAL="FATAL"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${LOG_INFO}] $*"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${LOG_WARN}] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${LOG_ERROR}] $*" >&2
}

log_fatal() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${LOG_FATAL}] $*" >&2
    exit 1
}

#==============================================================================
# Validation Functions
#==============================================================================

validate_config_file() {
    local config_file="$1"

    if [ -z "$config_file" ]; then
        log_error "Config file path not provided"
        return 1
    fi

    if [ ! -f "$config_file" ]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    if [ ! -r "$config_file" ]; then
        log_error "Config file not readable: $config_file"
        return 1
    fi

    log_info "Config file validated: $config_file"
    return 0
}

#==============================================================================
# Configuration Manipulation Functions
#==============================================================================

# Update log file paths with timestamps
update_config_paths() {
    local config_file="$1"

    if [ -z "$config_file" ]; then
        log_error "update_config_paths: Config file not provided"
        return 1
    fi

    if [ ! -f "$config_file" ]; then
        log_error "update_config_paths: Config file not found: $config_file"
        return 1
    fi

    local timestamp
    timestamp=$(date +'%Y%m%d-%H%M%S')

    # Only a value with a directory part names a log directory: "stdout",
    # "stderr" or a bare file name would make dirname return "." and the
    # timestamped directory would be created in the working directory.
    local first_line
    first_line=$(grep -E '^[[:space:]]*[A-Za-z0-9_]*filename:[[:space:]]*[^[:space:]]*/' "$config_file" | head -1)
    if [ -z "$first_line" ]; then
        log_info "No filename entry with a directory in config, skipping log path update" >&2
        return 0
    fi

    local original_path
    original_path=$(echo "$first_line" | sed -E 's/^[[:space:]]*[A-Za-z0-9_]*filename:[[:space:]]*(.*)$/\1/')

    local current_dir
    current_dir=$(dirname "$original_path")

    local ts_candidate base_dir
    ts_candidate=$(basename "$current_dir")
    if [[ "$ts_candidate" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        base_dir=$(dirname "$current_dir")
    else
        base_dir="$current_dir"
    fi

    local new_folder="${base_dir}/${timestamp}"

    if ! mkdir -p "$new_folder"; then
        log_error "Failed to create log directory: $new_folder"
        return 1
    fi

    log_info "Created log directory: $new_folder" >&2

    if ! sed -i -E "s#([[:space:]]*(filename|[A-Za-z0-9_]+_filename):[[:space:]])${base_dir}(/[0-9]{8}-[0-9]{6})?/#\1${base_dir}/${timestamp}/#g" "$config_file"; then
        log_error "Failed to update log paths in config"
        return 1
    fi

    local symlink_path="${base_dir}/current"
    if [ -L "$symlink_path" ]; then
        rm -f "$symlink_path"
    fi

    if ! ln -sf "./${timestamp}" "${symlink_path}"; then
        log_warn "Failed to create symlink: $symlink_path"
    fi

    echo "$new_folder"
    return 0
}

# Inject POD_IP into cu_cp.amf.bind_addr when HOSTNETWORK=false.
inject_ip_overrides() {
    local config_file="$1"

    if [ "${HOSTNETWORK}" = "true" ]; then
        log_info "HOSTNETWORK=true, skipping IP override injection"
        return 0
    fi

    if [ -z "$POD_IP" ]; then
        log_error "POD_IP not set, cannot inject IP overrides"
        return 1
    fi

    log_info "Injecting IP overrides (POD_IP=${POD_IP})"

    local tmpfile
    tmpfile=$(mktemp) || {
        log_error "Failed to create temporary file for IP injection"
        return 1
    }

    {
        echo "cu_cp:"
        echo "  amf:"
        echo "    bind_addr: ${POD_IP}"
    } > "$tmpfile"

    cat "$config_file" >> "$tmpfile"

    if ! mv "$tmpfile" "$config_file"; then
        log_error "Failed to inject IP overrides into config"
        rm -f "$tmpfile"
        return 1
    fi

    log_info "Successfully injected IP overrides"
    return 0
}

#==============================================================================
# Signal Handling
#==============================================================================

CU_CP_PID=""
terminate() {
    if [ -n "$CU_CP_PID" ]; then
        log_info "Forwarding SIGTERM to ocucp (PID $CU_CP_PID)"
        kill -TERM "$CU_CP_PID" 2>/dev/null
        wait "$CU_CP_PID"
    fi
    exit 0
}

#==============================================================================
# Main Execution Functions
#==============================================================================

# Tell the O1 adapter that the CU-CP has started, clearing a pending restart
# request so that its health endpoint reports healthy again
notify_o1_restarted() {
    if ! curl -sf -o /dev/null --retry 5 --retry-connrefused --retry-delay 1 \
        -X POST "http://localhost:${O1_HEALTHCHECK_PORT}/restarted"; then
        log_warn "Could not notify the O1 adapter that the CU-CP has started"
    fi
}

process_and_run_cu_cp() {
    local config_file="$1"
    local updated_config="${OCUDU_WORK_DIR:-${OCUDU_LOG_DIR}}/cu-cp-config.yml"

    cp "$config_file" "$updated_config" || log_fatal "Failed to copy config"

    inject_ip_overrides "$updated_config" || log_fatal "IP override injection failed"

    if [ "$PRESERVE_OLD_LOGS" = "true" ]; then
        update_config_paths "$updated_config" || log_fatal "Log path setup failed"
    fi

    cp "$updated_config" "${OCUDU_LOG_DIR}/cu-cp-config-rendered.yml"

    log_info "Starting CU-CP"
    if [ "$ENABLE_OCUDU_O1" != "true" ]; then
        exec stdbuf -oL ocucp -c "$updated_config"
    fi

    # The O1 adapter stops the CU-CP to apply a configuration change, so with O1 the
    # CU-CP runs as a child and main starts it again. setsid keeps signals sent to
    # the process group away from it, terminate forwards them once, and stdin
    # stays attached instead of being redirected from /dev/null.
    setsid stdbuf -oL ocucp -c "$updated_config" 0<&0 &
    CU_CP_PID=$!
    log_info "CU-CP started (PID: $CU_CP_PID)"
    notify_o1_restarted
    wait "$CU_CP_PID"
}

#==============================================================================
# Main Entry Point
#==============================================================================

main() {
    local config_file="$1"
    [ -z "$config_file" ] && log_fatal "Usage: $0 <config_file>"

    log_info "=== OCUDU CU-CP Entrypoint ==="
    log_info "Config: $config_file"
    log_info "ENABLE_OCUDU_O1: ${ENABLE_OCUDU_O1}"
    log_info "HOSTNETWORK: ${HOSTNETWORK}"
    log_info "OCUDU_LOG_DIR: ${OCUDU_LOG_DIR}"
    log_info "PRESERVE_OLD_LOGS: ${PRESERVE_OLD_LOGS}"

    trap terminate SIGTERM SIGINT

    local config_checksum=""
    while true; do
        # Wait for O1 config if enabled
        if [ "$ENABLE_OCUDU_O1" = "true" ]; then
            log_info "O1 enabled, waiting for config file creation"
            local elapsed=0
            local timeout="${CONFIG_CREATE_TIMEOUT}"

            # After a restart, wait for the configuration the restart was requested for
            while { [ ! -s "$config_file" ] || [ "$(cksum < "$config_file")" = "$config_checksum" ]; } && \
                [ $elapsed -lt "$timeout" ]; do
                log_info "Waiting for O1 to create config... (${elapsed}/${timeout}s)"
                sleep 1
                elapsed=$((elapsed + 1))
            done

            if [ ! -s "$config_file" ]; then
                log_fatal "Timeout after ${timeout}s waiting for config: $config_file"
            fi

            if [ "$(cksum < "$config_file")" = "$config_checksum" ]; then
                log_warn "No new config from O1 after ${timeout}s, restarting with the current one"
            else
                log_info "Config file created by O1"
            fi
            config_checksum=$(cksum < "$config_file")
        fi

        validate_config_file "$config_file" || log_fatal "Config validation failed"

        process_and_run_cu_cp "$config_file"
        local exit_code=$?

        if [ $exit_code -ne 0 ]; then
            log_error "CU-CP exited with code $exit_code"
            exit $exit_code
        fi

        log_info "CU-CP exited cleanly, restarting..."
    done
}

#==============================================================================
# Script Initialization
#==============================================================================

PRESERVE_OLD_LOGS="${PRESERVE_OLD_LOGS:-false}"
CONFIG_CREATE_TIMEOUT="${CONFIG_CREATE_TIMEOUT:-120}"
ENABLE_OCUDU_O1="${ENABLE_OCUDU_O1:-false}"
O1_HEALTHCHECK_PORT="${O1_HEALTHCHECK_PORT:-5000}"
HOSTNETWORK="${HOSTNETWORK:-false}"
OCUDU_LOG_DIR="${OCUDU_LOG_DIR:-/var/log/ocudu}"

main "$@"
