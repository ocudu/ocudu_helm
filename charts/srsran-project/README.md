# srsRAN Project CU/DU

A Helm chart for deploying the srsRAN Project 5G CU/DU (gNB)

## Node Requirements

Before deploying the srsRAN Project CU/DU on a node, ensure the following requirements are met:

1. **PTP4l and PHC2SYS**: These services must be running, and the local hardware clock must be synchronized. This ensures accurate communcation between CU/DU and RU.

2. **Interface Binding**: The interface connected to the Radio Unit (RU) must be bound to a DPDK-compatible driver such as `igb_uio` or `vfio-pci`. For detailed instructions on interface binding, please refer to the DPDK documentation at [DPDK Interface Binding Guide](https://doc.dpdk.org/guides/tools/devbind.html).

3. **Hugepages** (Optional): For using DPDK, it's required to configure hugepages on the node. The chart supports both 1Gi and 2Mi hugepages, but they are disabled by default. See the [Hugepages Configuration](#hugepages-configuration) section below for details.

## Configuration of the srsRAN Project CU/DU

The configuration file for the srsran Project CU/DU is located in the root directory of this Helm chart, its named `gnb-config.yml`. To configure the application, refer to the documentation provided at [srsRAN Project User Manual](https://docs.srsran.com/projects/project/en/latest/user_manuals/source/running.html). The config file will be mounted as a ConfigMap into the container on runtime.

## Hugepages Configuration

Hugepages are **optional** but recommended for DPDK-based deployments to achieve optimal performance. The chart automatically detects and configures hugepage volumes when you define `hugepages-1Gi` or `hugepages-2Mi` in your resource limits or requests.

### Checking Cluster Support

Before using hugepages, verify your cluster has them configured:

```bash
# Check if hugepages are available on cluster nodes
kubectl get nodes -o json | jq '.items[].status.capacity | select(.["hugepages-1Gi"] or .["hugepages-2Mi"])'

# Alternative: Check on the node directly
cat /proc/meminfo | grep HugePages
```

### Using Hugepages

Simply define hugepages in your resource configuration. The chart will automatically create the necessary volumes and mounts:

**With 1Gi hugepages (recommended for DPDK):**
```yaml
resources:
  limits:
    cpu: 12
    memory: 16Gi
    hugepages-1Gi: 2Gi
  requests:
    cpu: 12
    memory: 16Gi
    hugepages-1Gi: 2Gi
```

**With 2Mi hugepages (alternative):**
```yaml
resources:
  limits:
    cpu: 12
    memory: 16Gi
    hugepages-2Mi: 1Gi
  requests:
    cpu: 12
    memory: 16Gi
    hugepages-2Mi: 1Gi
```

### Deploying Without Hugepages

Simply omit hugepages from your resource configuration:

```yaml
resources:
  limits:
    cpu: 12
    memory: 16Gi
  requests:
    cpu: 12
    memory: 16Gi
```

**Note**: If you define hugepages in resources but your cluster doesn't have them configured, the deployment will fail with a scheduling error. Always verify cluster support first.

## Choosing a Container Image

Select the appropriate container image based on your CPU flags and architecture. We provide images with the following combinations:

- CPU Architectures: arm64 and amd64
- Operating System: Ubuntu 22.04
- CPU Flags: AVX512, AVX2, NEON

All images can be found in our [Docker Hub Repo](https://hub.docker.com/u/softwareradiosystems).

We encourage every user to build their own container images to not be limited to the above listed images. Therefore, we provide the Dockerfiles we use as well in this repository.

## Installing the Chart

To install the chart with the release name `srsran-project`:

```console
cd charts/srsran-project
helm install srsran-project ./
```

## Uninstalling the Chart

To uninstall/delete the srsran-project deployment:

```console
helm delete srsran-project
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

### Chart Parameters

| Parameter | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Pod affinity configuration |
| annotations | object | `{}` | Annotations for the Deployment |
| securityContext | object | `{}` | Container security context (allowPrivilegeEscalation, etc.) |
| fullnameOverride | string | `""` | Overrides the chart's computed fullname |
| interfaceName | string | `{}` | Name of the interface to be used for ptp4l |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.pullSecrets | list | `[]` | Image pull secrets |
| image.repository | string | `"srsran/linuxptp-agent"` | Image repository |
| image.tag | string | `""` | Image tag |
| nameOverride | string | `""` | Overrides the chart's name |
| nodeSelector | object | `{}` | nodeSelector configuration |
| podAnnotations | object | `{}` | Annotations for the Deployment Pods |
| podSecurityContext | object | `{}` | Pod security context (runAsUser, etc.) |
| resources | object | `{}` | Resource limits and requests config |
| serviceAccount.annotations | object | `{}` | Annotations for service account |
| serviceAccount.create | bool | `true` | Toggle to create ServiceAccount |
| serviceAccount.name | string | `nil` | Service account name |
| tolerations | list | `[]` | Tolerations applied to Pods |
| network | object | `[]` | Container to configure hostNetwork  |
| o1 | object | `[]` | Container to configure O1 |
| o1_config | object | `[]` | Container to the O1 config file |
| debugging | object | `[]` | Container to configure debugging options |
| service | object | `[]` | Container to configure debugging LoadBalancer options |
| config | object | `[]` | Container to configure srsRAN CU/DU application |

For more information about the values of the config sectoin please refer to the [srsRAN Project Configuration Reference](https://docs.srsran.com/projects/project/en/latest/user_manuals/source/config_ref.html).
