# tuned

A Helm chart for deploying tuned system optimization profiles on Kubernetes nodes

## Description

This chart deploys tuned as a DaemonSet to apply system optimization profiles across Kubernetes nodes. It is particularly useful for configuring low-latency and real-time workloads required by 5G RAN applications.

Tuned is a system tuning service that monitors connected devices and statically or dynamically tunes system settings according to selected profiles.

## Prerequisites

- Kubernetes >= 1.24.0
- Helm >= 3.15.0
- Nodes with tuned-compatible Linux kernels
- Appropriate node permissions for system tuning

## Installing the Chart

To install the chart with the release name `my-tuned`:

```bash
helm install my-tuned oci://ghcr.io/srsran/charts/tuned \
  --namespace kube-system \
  --create-namespace
```

Or from local directory:

```bash
cd charts/tuned
helm install my-tuned ./
```

## Uninstalling the Chart

To uninstall/delete the `my-tuned` deployment:

```bash
helm uninstall my-tuned --namespace kube-system
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

### Chart Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `softwareradiosystems/tuned` |
| `image.tag` | Image tag (overrides Chart appVersion) | `v2.21.0_1.0.0` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `profileName` | Name of the tuned profile | `srs-tuned` |
| `profileContent` | Content of the tuned profile configuration | See values.yaml |
| `startupScriptContent` | Startup script content for the profile | See values.yaml |
| `affinity` | Pod affinity configuration | `{}` |
| `tolerations` | Tolerations for pod assignment | `[]` |
| `hostPathTuned` | Host path for tuned directory | `/usr/lib/tuned` |
| `nodeSelector` | Node labels for pod assignment | `{}` |
| `securityContext.privileged` | Run as privileged container | `true` |
| `resources` | CPU/Memory resource requests/limits | `{}` |
| `annotations` | Pod annotations | `{}` |
| `restartOnConfigChange` | Restart pods on config change | `true` |
| `reboot.enabled` | Enable automatic reboot after profile application | `true` |

### Common Configuration Examples

#### Example 1: Custom Profile for RAN Workloads

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

#### Example 2: Resource Limits

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

## Upgrading

To upgrade the chart:

```bash
helm upgrade my-tuned oci://ghcr.io/srsran/charts/tuned \
  -f values.yaml \
  --namespace kube-system
```

## Troubleshooting

### Common Issues

**Issue**: DaemonSet pods not starting
**Solution**: Check node selector and tolerations match your node labels

**Issue**: Profile not applying
**Solution**: Verify tuned daemon is installed and running on the host 

**Issue**: Permission denied errors
**Solution**: Ensure the pod has appropriate privileges (DaemonSet runs as privileged by default)

## Production Readiness Considerations

For production use, consider using an operator like Openshift Node Tuning Operator.
## License

AGPL-3.0

## Links

- [Tuned Project](https://tuned-project.org/)
- [Openshift Node Tuning Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.9/html/scalability_and_performance/using-node-tuning-operator)
- [GitHub Repository](https://github.com/srsran/srsRAN_Project_helm)
- [Documentation](https://docs.srsran.com/)

## Production Use

This chart is intended for **development, testing, and demonstration purposes only**.
It has not been hardened for production use. Use in production environments at your own risk.
