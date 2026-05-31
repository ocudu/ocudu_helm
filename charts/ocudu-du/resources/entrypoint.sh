#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# This script runs the OCUDU DU (odu) binary with the provided configuration file.
# - If a hal section exists with eal_args, replaces the CPU core list inside @(...)
#   with the CPUs available to the container as read from cgroups (v1/v2).
# - When HOSTNETWORK=false and an SR-IOV VF is allocated (RESOURCE_EXTENDED):
#     ru_ofh + hal present  -> DPDK: replaces network_interface with BDF and du_mac_addr
#     ru_ofh + no hal       -> fatal error (SR-IOV without DPDK config)
#     no ru_ofh             -> SR-IOV replacement skipped silently
#   When HOSTNETWORK=true, network_interface is set by the user in the config directly.
# - If PRESERVE_OLD_LOGS=true, log file paths are updated with a timestamp and a
#   'current' symlink is created for easy navigation.
# - The rendered config is snapshotted to ${SRS_LOG_DIR}/du-config-rendered.yml.
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
# SR-IOV Detection Functions
#==============================================================================

has_hal_section() {
    grep -q "^[[:space:]]*hal:" "$1"
}

has_hal_eal_args() {
    grep -q "^[[:space:]]*eal_args:" "$1"
}

has_ru_ofh_section() {
    grep -q "^[[:space:]]*ru_ofh:" "$1"
}

#==============================================================================
# Network Configuration Functions
#==============================================================================

# Get MAC address for a PCI BDF without requiring CAP_SYSLOG.
# Try order:
#   1. Direct sysfs net address  (VF still bound to kernel driver)
#   2. PF ip-link VF entry       (VF bound to vfio-pci / DPDK)
#   3. dmesg fallback            (last resort; may fail without CAP_SYSLOG)
get_mac_for_bdf() {
    local bdf="$1"
    local mac=""

    # 1. Direct sysfs — works when VF is bound to a kernel net driver
    local sysfs_net="/sys/bus/pci/devices/${bdf}/net"
    if [ -d "$sysfs_net" ]; then
        mac=$(cat "${sysfs_net}"/*/address 2>/dev/null | head -1)
    fi

    # 2. Via Physical Function — works for DPDK/vfio-pci bound VFs
    if [ -z "$mac" ]; then
        local physfn_link="/sys/bus/pci/devices/${bdf}/physfn"
        if [ -L "$physfn_link" ]; then
            local pf_bdf
            pf_bdf=$(basename "$(readlink -f "$physfn_link")")
            local pf_net="/sys/bus/pci/devices/${pf_bdf}/net"
            if [ -d "$pf_net" ]; then
                local pf_iface
                pf_iface=$(ls "$pf_net" 2>/dev/null | head -1)
                if [ -n "$pf_iface" ]; then
                    local vf_idx=0
                    while [ -L "/sys/bus/pci/devices/${pf_bdf}/virtfn${vf_idx}" ]; do
                        local vf_bdf
                        vf_bdf=$(basename "$(readlink -f "/sys/bus/pci/devices/${pf_bdf}/virtfn${vf_idx}")")
                        if [ "$vf_bdf" = "$bdf" ]; then
                            mac=$(ip link show "$pf_iface" 2>/dev/null \
                                | grep "vf ${vf_idx} " \
                                | sed -n 's/.*link\/ether \([0-9a-fA-F:]\+\).*/\1/p')
                            break
                        fi
                        vf_idx=$((vf_idx + 1))
                    done
                fi
            fi
        fi
    fi

    # 3. dmesg fallback (requires CAP_SYSLOG on kernels >= 5.8; may fail in restricted containers)
    if [ -z "$mac" ]; then
        mac=$(dmesg 2>/dev/null | grep "$bdf" | grep "MAC address:" | tail -n 1 \
            | sed -n 's/.*MAC address: \([0-9a-fA-F:]\+\).*/\1/p')
    fi

    echo "$mac"
}

# Replace network_interface with BDF and update du_mac_addr for a single VF (DPDK mode)
update_single_network_interface_and_mac() {
    local config_file="$1"
    local bdf="$2"

    log_info "Updating network_interface to BDF: $bdf"

    local tmpfile
    tmpfile=$(mktemp) || {
        log_error "Failed to create temporary file for network update"
        return 1
    }

    local mac
    mac=$(get_mac_for_bdf "$bdf")

    local replaced=0
    while IFS= read -r line || [ -n "$line" ]; do
        if echo "$line" | grep -qE "^[[:space:]]*network_interface:" && [ "$replaced" -eq 0 ]; then
            local indent
            indent=$(echo "$line" | sed -n 's/^\([[:space:]]*\).*/\1/p')
            echo "${indent}network_interface: $bdf" >> "$tmpfile"
            log_info "Set network_interface to: $bdf"
            replaced=1
        elif echo "$line" | grep -qE "^[[:space:]]*du_mac_addr:" && [ "$replaced" -eq 1 ]; then
            local indent
            indent=$(echo "$line" | sed -n 's/^\([[:space:]]*\).*/\1/p')
            if [ -n "$mac" ]; then
                echo "${indent}du_mac_addr: $mac" >> "$tmpfile"
                log_info "Set du_mac_addr to: $mac"
            else
                log_warn "Could not determine MAC for BDF $bdf, keeping original"
                echo "$line" >> "$tmpfile"
            fi
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$config_file"

    if ! mv "$tmpfile" "$config_file"; then
        log_error "Failed to update config file with network interface"
        rm -f "$tmpfile"
        return 1
    fi

    return 0
}

#==============================================================================
# Signal Handling
#==============================================================================

DU_PID=""
terminate() {
    if [ -n "$DU_PID" ]; then
        log_info "Forwarding SIGTERM to odu (PID $DU_PID)"
        kill -TERM "$DU_PID" 2>/dev/null
        wait "$DU_PID"
    fi
    exit 0
}

#==============================================================================
# Main Execution Functions
#==============================================================================

process_and_run_du() {
    local config_file="$1"
    local updated_config="${SRS_LOG_DIR}/du-config.yml"

    cp "$config_file" "$updated_config" || log_fatal "Failed to copy config"

    update_hal_eal_args "$updated_config" || log_fatal "HAL EAL args update failed"

    if [ -n "${DEVICE_BDF}" ] && [ "${HOSTNETWORK}" = "false" ]; then
        if has_ru_ofh_section "$updated_config"; then
            if has_hal_section "$updated_config"; then
                update_single_network_interface_and_mac "$updated_config" "${DEVICE_BDF}" || \
                    log_fatal "DPDK network interface update failed"
            else
                log_fatal "SR-IOV device present with ru_ofh but no hal section — DPDK config required"
            fi
        else
            log_info "No ru_ofh section found, skipping SR-IOV network_interface replacement"
        fi
    fi

    if [ "$PRESERVE_OLD_LOGS" = "true" ]; then
        update_config_paths "$updated_config" || log_fatal "Log path setup failed"
    fi

    cp "$updated_config" "${SRS_LOG_DIR}/du-config-rendered.yml"

    log_info "Starting DU"
    exec stdbuf -oL odu -c "$updated_config"
}

#==============================================================================
# Main Entry Point
#==============================================================================

main() {
    local config_file="$1"
    [ -z "$config_file" ] && log_fatal "Usage: $0 <config_file>"

    log_info "=== OCUDU DU Entrypoint ==="
    log_info "Config: $config_file"
    log_info "HOSTNETWORK: ${HOSTNETWORK}"
    log_info "SRS_LOG_DIR: ${SRS_LOG_DIR}"
    log_info "PRESERVE_OLD_LOGS: ${PRESERVE_OLD_LOGS}"

    trap terminate SIGTERM SIGINT

    while true; do
        validate_config_file "$config_file" || log_fatal "Config validation failed"

        # Validate SR-IOV consistency up front
        if [ -n "${DEVICE_BDF}" ] && [ "${HOSTNETWORK}" = "false" ]; then
            if has_ru_ofh_section "$config_file" && has_hal_section "$config_file"; then
                if ! has_hal_eal_args "$config_file"; then
                    log_fatal "SR-IOV DPDK mode: hal section found but eal_args missing"
                fi
            fi
        fi

        process_and_run_du "$config_file"
        local exit_code=$?

        if [ $exit_code -ne 0 ]; then
            log_error "DU exited with code $exit_code"
            exit $exit_code
        fi

        log_info "DU exited cleanly, restarting..."
    done
}

#==============================================================================
# Script Initialization
#==============================================================================

PRESERVE_OLD_LOGS="${PRESERVE_OLD_LOGS:-false}"
SRS_LOG_DIR="${SRS_LOG_DIR:-/var/log/srs}"
HOSTNETWORK="${HOSTNETWORK:-false}"
RESOURCE_EXTENDED="${RESOURCE_EXTENDED:-intel.com/intel_sriov_dpdk}"

# Convert resource name to env var format: foo.bar/baz -> PCIDEVICE_FOO_BAR_BAZ
if [ -n "${RESOURCE_EXTENDED}" ]; then
    env_var_name="PCIDEVICE_$(echo "${RESOURCE_EXTENDED}" | tr '/.a-z' '___A-Z')"
    DEVICE_BDF="${!env_var_name:-}"
fi

main "$@"
