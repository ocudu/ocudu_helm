#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# This script runs the OCUDU DU (odu) binary with the provided configuration file.
# - If PRESERVE_OLD_LOGS=true, log file paths are updated with a timestamp and a
#   'current' symlink is created for easy navigation.
# - The binary is restarted automatically on clean exit.
# - SIGTERM/SIGINT are forwarded gracefully to the odu process.
#
# Usage: ./entrypoint.sh /etc/config/du-config.yml

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
# Hardware Detection Functions
#==============================================================================

# Detect container-available CPUs from cgroups (v1/v2, privileged/non-privileged)
get_container_cpus() {
    local cpuset=""
    local cgroup_path=""

    if [ -f /proc/self/cgroup ]; then
        cgroup_path=$(grep -E "cpuset|0::" /proc/self/cgroup | head -1 | cut -d: -f3)
    fi

    if [ -n "$cgroup_path" ] && [ "$cgroup_path" != "/" ]; then
        if [ -f "/sys/fs/cgroup/cpuset${cgroup_path}/cpuset.cpus" ]; then
            cpuset=$(cat "/sys/fs/cgroup/cpuset${cgroup_path}/cpuset.cpus")
        elif [ -f "/sys/fs/cgroup${cgroup_path}/cpuset.cpus" ]; then
            cpuset=$(cat "/sys/fs/cgroup${cgroup_path}/cpuset.cpus")
        fi
    fi

    if [ -z "$cpuset" ]; then
        if [ -f /sys/fs/cgroup/cpuset/cpuset.cpus ]; then
            cpuset=$(cat /sys/fs/cgroup/cpuset/cpuset.cpus)
        elif [ -f /sys/fs/cgroup/cpuset.cpus ]; then
            cpuset=$(cat /sys/fs/cgroup/cpuset.cpus)
        fi
    fi

    if [ -z "$cpuset" ]; then
        log_warn "Could not determine CPU set from cgroup, using fallback"
        if command -v nproc >/dev/null 2>&1; then
            local n
            n=$(nproc)
            if [ "$n" -gt 0 ]; then
                cpuset="0-$((n-1))"
            else
                cpuset="0-1"
            fi
        else
            cpuset="0-1"
        fi
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Detected CPU set from cgroup: $cpuset" >&2
    fi

    echo "$cpuset" | xargs
    return 0
}

# Update hal.eal_args cores (inside @(...)) only if hal section exists
update_hal_eal_args() {
    local config_file="$1"

    if [ -z "$config_file" ]; then
        log_error "update_hal_eal_args: Config file not provided"
        return 1
    fi

    if ! grep -q "^[[:space:]]*hal:" "$config_file"; then
        log_info "No hal section found, skipping eal_args update"
        return 0
    fi

    if ! grep -q "^[[:space:]]*eal_args:" "$config_file"; then
        log_info "No eal_args found, skipping update"
        return 0
    fi

    local cpus
    cpus=$(get_container_cpus)
    if [ -z "$cpus" ]; then
        log_warn "No CPUs detected, skipping hal.eal_args update"
        return 0
    fi

    # Replace only the CPU list after @(...), preserving the lcore mapping before it.
    # Supports both formats: @(cpus) and (lcores)@(cpus)
    if ! sed -i -E "s/(\\([-0-9,]+\\))?@\\([-0-9,]+\\)/\\1@(${cpus})/" "$config_file"; then
        log_error "Failed to update hal.eal_args"
        return 1
    fi

    log_info "Updated hal.eal_args CPU list to: ${cpus}"
    return 0
}

#==============================================================================
# Signal Handling
#==============================================================================

terminate() {
    log_info "Received termination signal, forwarding to DU process"

    local du_pid
    du_pid=$(pgrep odu)

    if [ -z "$du_pid" ]; then
        log_warn "No DU process found"
        exit 0
    fi

    if ! kill -0 "$du_pid" 2>/dev/null; then
        log_warn "DU process no longer running"
        exit 0
    fi

    log_info "Sending SIGTERM to DU (PID: $du_pid)"
    if kill -TERM "$du_pid"; then
        wait "$pipe_pid"
        local exit_code=$?
        log_info "DU terminated with exit code $exit_code"
        exit "$exit_code"
    else
        log_error "Failed to send SIGTERM to DU"
        exit 1
    fi
}

#==============================================================================
# Main Execution Functions
#==============================================================================

process_and_run_du() {
    local config_file="$1"
    local updated_config="/tmp/du-config.yml"

    if ! cp "$config_file" "$updated_config"; then
        log_fatal "Failed to copy config file to $updated_config"
    fi

    update_hal_eal_args "$updated_config" || log_fatal "HAL EAL args update failed"

    if [ "$PRESERVE_OLD_LOGS" = "true" ]; then
        local log_path
        log_path=$(update_config_paths "$updated_config") || log_fatal "Log path setup failed"

        log_info "Starting DU with log preservation in: $log_path"
        {
            stdbuf -oL odu -c "$updated_config" 2>&1 | tee -a "${log_path}/du.stdout"
            exit ${PIPESTATUS[0]}
        } &
    else
        log_info "Starting DU (logs not preserved)"
        odu -c "$updated_config" &
    fi

    pipe_pid=$!
    wait "$pipe_pid"
    local exit_code=$?

    log_info "DU exited with code $exit_code"
    return $exit_code
}

#==============================================================================
# Main Entry Point
#==============================================================================

main() {
    local config_file="$1"

    if [ -z "$config_file" ]; then
        log_fatal "Usage: $0 <config_file>"
    fi

    log_info "=== OCUDU DU Entrypoint Script ==="
    log_info "Config file: $config_file"
    log_info "PRESERVE_OLD_LOGS: ${PRESERVE_OLD_LOGS}"

    trap terminate SIGTERM SIGINT

    validate_config_file "$config_file" || log_fatal "Config validation failed"

    while true; do
        process_and_run_du "$config_file"
        local exit_code=$?

        if [ $exit_code -ne 0 ]; then
            log_error "DU failed with exit code $exit_code"
            exit $exit_code
        fi

        log_info "DU exited cleanly, restarting..."
    done
}

#==============================================================================
# Script Initialization
#==============================================================================

# set -euo pipefail

PRESERVE_OLD_LOGS="${PRESERVE_OLD_LOGS:-false}"

main "$@"
