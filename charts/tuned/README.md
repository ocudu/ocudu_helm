# tuned

![PoC/Demo](https://img.shields.io/badge/status-PoC%2FDemo-yellow)

A Helm chart for deploying tuned system optimization profiles on Kubernetes nodes

> **⚠️ PoC/Demo Chart - Not Production Ready**
>
> This chart is intended for **development, testing, and demonstration purposes only**.
> It has not been hardened or validated for production use.

## Overview

This chart deploys tuned as a DaemonSet to apply system optimization profiles across Kubernetes nodes. Tuned is particularly useful for configuring low-latency and real-time workloads required by 5G RAN applications.

**Capabilities**:
- Kernel parameter tuning (sysctl)
- CPU frequency and power management
- Network stack optimization
- Boot parameter configuration
- Custom startup scripts

## Prerequisites

Before installing, ensure your environment meets these requirements:

1. **Kubernetes**: >= 1.24.0
2. **Helm**: >= 3.15.0
3. **Kernel**: Linux kernel with tuned support
4. **Privileges**: Chart requires `privileged: true` for system tuning operations
5. **Node Selection**: Use `nodeSelector` to target specific nodes for tuning
6. **TuneD installed**: TuneD has to be installed on the nodes for tuning

## Installing the Chart

**From OCI registry**:
```bash
helm install tuned-ocudu oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/tuned --version 1.0.0 \
  -n kube-system --create-namespace
```

**Local installation**:
```bash
cd charts/tuned
helm install tuned-ocudu ./
```

**With custom configuration**:
```bash
helm install tuned-ocudu ./ -f my-values.yaml
```

## Verifying Installation

Check DaemonSet status:
```bash
# Check DaemonSet status
kubectl get daemonset -l app.kubernetes.io/name=tuned

# View pod logs
kubectl logs -l app.kubernetes.io/name=tuned

# Verify profile applied
kubectl exec -it <pod-name> -- tuned-adm active
```

## Uninstalling the Chart

```bash
helm uninstall tuned-ocudu
```

The command removes all Kubernetes components associated with the chart.

## Configuration

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image.repository` | string | `"softwareradiosystems/tuned"` | Container image repository |
| `image.tag` | string | `"v2.21.0_1.0.0"` | Image tag (overrides Chart appVersion) |
| `image.pullPolicy` | string | `"IfNotPresent"` | Image pull policy |
| `profileName` | string | `"ocudu-tuned"` | Name of the tuned profile |
| `profileContent` | string | See values.yaml | Tuned profile configuration |
| `startupScriptContent` | string | See values.yaml | Custom startup script |
| `securityContext.privileged` | bool | `true` | **REQUIRED**: Enable privileged mode for system tuning |
| `hostPathTuned` | string | `"/usr/lib/tuned"` | Host path for tuned directory |
| `nodeSelector` | object | `{}` | Node selector for pod assignment |
| `tolerations` | list | `[]` | Tolerations for pod assignment |
| `affinity` | object | `{}` | Affinity rules for pod assignment |
| `reboot.enabled` | bool | `true` | Enable automatic node reboot when profile changes |
| `reboot.cmd` | string | `"/sbin/shutdown -r +1 ..."` | Command to execute for system reboot |
| `reboot.markerDir` | string | `"/var/lib/tuned-helm"` | Directory for checksum marker files |
| `restartOnConfigChange` | bool | `true` | Restart pods when profile configuration changes |

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml).

### Configuration Change Detection

The chart uses SHA256 checksums to detect profile changes:
- **Pod restart**: When `profileContent` or `startupScriptContent` changes, the checksum annotation triggers pod restart
- **Node reboot**: On new checksum, a marker file is created at `/var/lib/tuned-helm/<checksum>` and reboot is scheduled
- **Idempotency**: Existing marker prevents duplicate reboots for the same configuration

## Common Configuration Examples

### Custom Profile for RAN Workloads

```yaml
# values.yaml
profileName: my-ran-profile

nodeSelector:
  node-role.kubernetes.io/worker: ""

tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "ran"
    effect: "NoSchedule"

reboot:
  enabled: false  # Disable automatic reboot
```

### Resource Limits

```yaml
# values.yaml
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi

restartOnConfigChange: true
```

## Architecture & Design

### How the Chart Works

The tuned chart uses a unique approach to apply system-level tuning:

1. **DaemonSet Deployment**: Runs one pod per node (or on selected nodes)
2. **Profile Creation**: Copies tuned profile configuration to host's `/usr/lib/tuned/<profileName>/`
3. **Host Namespace Access**: Uses `nsenter` to execute commands in the host's namespace:
   - Activates the tuned profile via `tuned-adm profile <profileName>`
   - Enables and restarts the host's tuned.service systemd unit
4. **Checksum Tracking**: Calculates SHA256 hash of profile configuration
5. **Automatic Reboot**: If configuration changes (new checksum):
   - Creates marker file in `/var/lib/tuned-helm/<checksum>`
   - Schedules node reboot with 1-minute delay (`shutdown -r +1`)
   - Prevents duplicate reboots by checking marker file

### Why privileged mode is Required

**`privileged: true`** is mandatory because:
- Access host PID namespace (`hostPID: true`) and use `nsenter` to run commands on the host
- Write tuned profiles to host filesystem at `/usr/lib/tuned/`
- Control host systemd services (tuned.service)
- Schedule host system reboot

The container doesn't directly modify kernel parameters—it delegates to the host's tuned daemon, which applies the profile including bootloader parameters, sysctl settings, CPU governor, and startup scripts.

## Troubleshooting

### DaemonSet pods not starting
```bash
# Check node selector and tolerations
kubectl describe daemonset -l app.kubernetes.io/name=tuned

# Verify nodes match selector
kubectl get nodes --show-labels

# Common issues:
# - Node selector doesn't match any nodes
# - Tolerations don't match node taints
```

### Profile not applying
```bash
# Check pod logs for nsenter commands
kubectl logs -l app.kubernetes.io/name=tuned

# Verify profile was activated on the HOST (not in container)
kubectl exec -it <pod-name> -- nsenter --target 1 --mount --uts --ipc --net --pid -- tuned-adm active

# Check host's tuned service status
kubectl exec -it <pod-name> -- nsenter --target 1 --mount --uts --ipc --net --pid -- systemctl status tuned

# Common issues:
# - Host doesn't have tuned daemon installed
# - Invalid profile syntax in profileContent
# - Missing startup script permissions
# - Profile conflicts with existing system settings
```

### Permission denied errors
```bash
# Verify security context
kubectl describe pod <pod-name> | grep -A5 "Security Context"

# Ensure privileged mode is enabled
# securityContext.privileged: true must be set
```

### Node reboot not occurring
```bash
# Check reboot marker files
kubectl exec -it <pod-name> -- ls -la /var/lib/tuned-helm/

# Check if reboot was already done for current checksum
kubectl logs -l app.kubernetes.io/name=tuned | grep -E "checksum|reboot"

# Verify reboot is enabled
kubectl get daemonset <release-name>-tuned -o yaml | grep -A2 REBOOT_ENABLED

# Common issues:
# - reboot.enabled: false in values.yaml
# - Marker file already exists (reboot already done)
# - Shutdown command incorrect for node OS
# - Insufficient permissions to execute shutdown
```

## Support

- **Documentation**: [Tuned Project](https://tuned-project.org/)
- **Production Alternative**: [OpenShift Node Tuning Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.9/html/scalability_and_performance/using-node-tuning-operator)

## License

BSD 3-Clause Open MPI variant - See LICENSE file for details
