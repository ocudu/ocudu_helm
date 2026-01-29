# RU Emulator

A Helm chart for deploying the srsRAN Radio Unit (O-RU) emulator

This Helm chart deploys an RU emulator that receives data from any DU via OpenFronthaul and responds like a real Radio Unit.

## Installing the Chart

To install the chart with the release name `ru-emulator`:

```console
cd charts/ru_emulator
helm install ru-emulator ./
```

## Uninstalling the Chart

To uninstall/delete the ru-emulator deployment:

```console
helm delete ru-emulator
```

The command removes all the Kubernetes components associated with the chart and deletes the release.


## Configuration

### Chart Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `affinity` | object | `{}` | Pod affinity configuration |
| annotations | object | `{}` | Annotations for the Deployment |
| securityContext | object | `{}` | Container security context (allowPrivilegeEscalation, etc.) |
| fullnameOverride | string | `""` | Overrides the chart's computed fullname |
| interfaceName | string | `{}` | Name of the interface to be used for ptp4l |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.pullSecrets | list | `[]` | Image pull secrets |
| image.repository | string | `"srsran/ru-emulator"` | Image repository |
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
| config | section | `[]` | Configuration for the ru-emulator |

## Production Use

This chart is intended for **development, testing, and demonstration purposes only**.
It has not been hardened for production use. Use in production environments at your own risk.
