#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# This script runs the OCUDU CU-UP (ocu) binary with the provided configuration file.
# - If PRESERVE_OLD_LOGS=true, log file paths are updated with a timestamp and a
#   'current' symlink is created for easy navigation.
# - The rendered config is snapshotted to ${OCUDU_LOG_DIR}/cu-up-config-rendered.yml.
# - The binary is restarted automatically on clean exit.
# - SIGTERM/SIGINT are forwarded gracefully to the ocu process.
#
# Usage: ./entrypoint.sh /etc/config/cu-up-config.yml

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

    local first_line
    first_line=$(grep -E '^[[:space:]]*[A-Za-z0-9_]*filename:' "$config_file" | head -1)
    if [ -z "$first_line" ]; then
        log_info "No filename entries found in config, skipping log path update" >&2
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

#==============================================================================
# Signal Handling
#==============================================================================

CU_UP_PID=""
terminate() {
    if [ -n "$CU_UP_PID" ]; then
        log_info "Forwarding SIGTERM to ocu (PID $CU_UP_PID)"
        kill -TERM "$CU_UP_PID" 2>/dev/null
        wait "$CU_UP_PID"
    fi
    exit 0
}

#==============================================================================
# Main Execution Functions
#==============================================================================

process_and_run_cu_up() {
    local config_file="$1"
    local updated_config="${OCUDU_LOG_DIR}/cu-up-config.yml"

    cp "$config_file" "$updated_config" || log_fatal "Failed to copy config"

    if [ "$PRESERVE_OLD_LOGS" = "true" ]; then
        update_config_paths "$updated_config" || log_fatal "Log path setup failed"
    fi

    cp "$updated_config" "${OCUDU_LOG_DIR}/cu-up-config-rendered.yml"

    log_info "Starting CU-UP"
    exec stdbuf -oL ocu -c "$updated_config"
}

#==============================================================================
# Main Entry Point
#==============================================================================

main() {
    local config_file="$1"
    [ -z "$config_file" ] && log_fatal "Usage: $0 <config_file>"

    log_info "=== OCUDU CU-UP Entrypoint ==="
    log_info "Config: $config_file"
    log_info "OCUDU_LOG_DIR: ${OCUDU_LOG_DIR}"
    log_info "PRESERVE_OLD_LOGS: ${PRESERVE_OLD_LOGS}"

    trap terminate SIGTERM SIGINT

    while true; do
        validate_config_file "$config_file" || log_fatal "Config validation failed"

        process_and_run_cu_up "$config_file"
        local exit_code=$?

        if [ $exit_code -ne 0 ]; then
            log_error "CU-UP exited with code $exit_code"
            exit $exit_code
        fi

        log_info "CU-UP exited cleanly, restarting..."
    done
}

#==============================================================================
# Script Initialization
#==============================================================================

PRESERVE_OLD_LOGS="${PRESERVE_OLD_LOGS:-false}"
OCUDU_LOG_DIR="${OCUDU_LOG_DIR:-/var/log/ocudu}"

main "$@"
