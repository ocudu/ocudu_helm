#!/bin/bash
#
# Copyright 2021-2026 Software Radio Systems Limited
#
# By using this file, you agree to the terms and conditions set
# forth in the LICENSE file which can be found at the top level of
# the distribution.
#

set -euo pipefail

#==============================================================================
# Logging Functions
#==============================================================================

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_fatal() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [FATAL] $*" >&2
    exit 1
}

#==============================================================================
# Signal Handling
#==============================================================================

ru_pid=""

cleanup() {
    log_info "Received termination signal, stopping ru_emulator..."
    if [ -n "$ru_pid" ] && kill -0 "$ru_pid" 2>/dev/null; then
        kill -TERM "$ru_pid"
        wait "$ru_pid"
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT

#==============================================================================
# Utility Functions
#==============================================================================

# Convert extended resource name to environment variable name
# Example: "intel.com/intel_sriov_netdevice" -> "PCIDEVICE_INTEL_COM_INTEL_SRIOV_NETDEVICE"
convert_resource_name() {
    local resource_full="$1"
    local varname
    varname=$(echo "$resource_full" | tr '[:lower:]' '[:upper:]' | sed -E 's/[./]/_/g')
    echo "PCIDEVICE_${varname}"
    return 0
}

#==============================================================================
# Network Configuration Functions
#==============================================================================

# Update network_interface and du_mac_addr for single cell using SR-IOV BDF
update_network_interface_and_mac() {
    local config_file="$1"
    local bdf="$2"

    if [ -z "$bdf" ]; then
        log_info "No SR-IOV device provided, skipping network interface update"
        return 0
    fi

    log_info "Updating network interface for SR-IOV device: $bdf"

    # Extract MAC address from dmesg
    local mac
    mac=$(dmesg | grep "$bdf" | grep "MAC address:" | tail -n 1 | sed -n 's/.*MAC address: \([0-9a-fA-F:]\+\).*/\1/p')

    if [ -z "$mac" ]; then
        log_warn "Could not determine MAC address for BDF $bdf from dmesg"
        log_warn "Continuing with BDF replacement only"
    else
        log_info "Detected MAC address: $mac for BDF: $bdf"
    fi

    # Create temporary file
    local tmpfile
    tmpfile=$(mktemp) || log_fatal "Failed to create temporary file"

    local in_cell=false
    local network_replaced=false
    local mac_replaced=false

    # Process config file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Detect when we enter cells section
        if echo "$line" | grep -qE "^[[:space:]]*cells:[[:space:]]*$"; then
            echo "$line" >> "$tmpfile"
            in_cell=true
        # Detect list item marker (dash)
        elif echo "$line" | grep -qE "^[[:space:]]*-[[:space:]]*$" && [ "$in_cell" = true ]; then
            echo "$line" >> "$tmpfile"
        # Update network_interface when in cell
        elif echo "$line" | grep -qE "^[[:space:]]*network_interface:" && [ "$in_cell" = true ] && [ "$network_replaced" = false ]; then
            local indent
            indent=$(echo "$line" | sed -n 's/^\([[:space:]]*\).*/\1/p')
            echo "${indent}network_interface: $bdf" >> "$tmpfile"
            log_info "Replaced network_interface with BDF: $bdf"
            network_replaced=true
        # Update du_mac_addr when in cell (if MAC was found)
        elif echo "$line" | grep -qE "^[[:space:]]*du_mac_addr:" && [ "$in_cell" = true ] && [ "$mac_replaced" = false ]; then
            local indent
            indent=$(echo "$line" | sed -n 's/^\([[:space:]]*\).*/\1/p')
            if [ -n "$mac" ]; then
                echo "${indent}du_mac_addr: $mac" >> "$tmpfile"
                log_info "Replaced du_mac_addr with MAC: $mac"
            else
                echo "$line" >> "$tmpfile"
            fi
            mac_replaced=true
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$config_file"

    # Replace original file
    if ! mv "$tmpfile" "$config_file"; then
        log_error "Failed to update config file"
        rm -f "$tmpfile"
        return 1
    fi

    log_info "Successfully updated network configuration"
    return 0
}

#==============================================================================
# Main Execution
#==============================================================================

main() {
    log_info "=== RU Emulator Entrypoint Script ==="
    
    # Validate arguments
    if [ $# -lt 1 ]; then
        log_fatal "Usage: $0 <config_file>"
    fi

    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_fatal "Config file not found: $config_file"
    fi

    log_info "Using config file: $config_file"

    # Create working copy of config
    local updated_config="/tmp/ru_emulator_config.yml"
    cp "$config_file" "$updated_config" || log_fatal "Failed to copy config file"

    # Process SR-IOV configuration if enabled
    if [ -n "${RESOURCE_EXTENDED:-}" ]; then
        log_info "SR-IOV mode detected (RESOURCE_EXTENDED=$RESOURCE_EXTENDED)"
        
        # Convert resource name to environment variable name
        local resource_var
        resource_var=$(convert_resource_name "$RESOURCE_EXTENDED")
        log_info "Looking for SR-IOV devices in: $resource_var"
        
        # Get device list from environment
        local device_list="${!resource_var:-}"
        
        if [ -n "$device_list" ]; then
            log_info "Found SR-IOV device(s): $device_list"
            
            # Use first device (single cell only)
            local bdf="${device_list%%,*}"
            log_info "Using BDF: $bdf (single cell configuration)"
            
            # Update network interface and MAC in config
            update_network_interface_and_mac "$updated_config" "$bdf" || \
                log_fatal "Failed to update network configuration"
        else
            log_warn "SR-IOV enabled but no devices found in $resource_var"
            log_warn "Proceeding with original configuration"
        fi
    else
        log_info "hostNetwork mode (no SR-IOV)"
    fi

    # Display final configuration - show cells section specifically
    log_info "Final configuration - cells section:"
    grep -A 15 "cells:" "$updated_config" | sed 's/^/  /' || log_warn "Could not extract cells section"

    # Launch RU emulator
    log_info "Launching ru_emulator..."
    /usr/local/bin/ru_emulator -c "$updated_config" &
    ru_pid=$!
    
    log_info "RU emulator started with PID: $ru_pid"
    
    # Wait for process
    wait "$ru_pid"
    local exit_code=$?
    
    log_info "RU emulator exited with code: $exit_code"
    exit $exit_code
}

# Execute main function
main "$@"
