# rt-tests

![PoC/Demo](https://img.shields.io/badge/status-PoC%2FDemo-yellow)

A Helm chart for deploying real-time performance testing tools (cyclictest, stress-ng)

> **⚠️ PoC/Demo Chart - Not Production Ready**
>
> This chart is intended for **development, testing, and demonstration purposes only**.
> It has not been hardened for production use. Use in production environments at your own risk.

## Overview

This chart deploys real-time latency testing tools as a Kubernetes Job to measure system real-time performance and latency characteristics critical for 5G RAN workloads.

**Tools Included**:
- **cyclictest**: Measures real-time kernel latency
- **stress-ng**: Applies system load during testing

## Prerequisites

Before installing, ensure your environment meets these requirements:

1. **Kubernetes**: >= 1.24.0
2. **Privileges**: Chart requires `privileged: true` for real-time scheduling and memory locking
3. **Resources**: Dedicated CPU cores recommended for accurate measurements

## Installing the Chart

**Basic installation**:
```bash
cd charts/rt-tests
helm install rt-tests-srs ./
```

**With custom configuration**:
```bash
helm install rt-tests-srs ./ -f my-values.yaml
```

## Verifying Installation

Check job status and results:
```bash
# Check job status
kubectl get jobs

# View test output
kubectl logs job/rt-tests-chart-job

# Wait for completion
kubectl wait --for=condition=complete --timeout=300s job/rt-tests-chart-job
```

## Uninstalling the Chart

```bash
helm uninstall rt-tests-srs
```

The command removes all Kubernetes components associated with the chart.

## Configuration

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image.repository` | string | `"softwareradiosystems/rt-tests"` | Container image repository |
| `image.tag` | string | Chart appVersion | Image tag |
| `image.pullPolicy` | string | `"IfNotPresent"` | Image pull policy |
| `securityContext.privileged` | bool | `true` | **REQUIRED**: Enable privileged mode for RT scheduling |
| `hostOutputFolder` | string | `"/var/lib/rt-tests"` | Host path to store test results |
| `config.rt_tests.yml` | string | See values.yaml | Test configuration (tools and arguments) |
| `resources` | object | `{}` | CPU/memory limits and requests |
| `nodeSelector` | object | `{}` | Node selector for pod assignment |
| `tolerations` | list | `[]` | Tolerations for pod assignment |
| `affinity` | object | `{}` | Affinity rules for pod assignment |

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml).

## Common Configuration Examples

### Short Test Run (30 seconds)

```yaml
config:
  rt_tests.yml: |-
    stress-ng: "--cpu 4 --timeout 30s"
    cyclictest: "--mlockall --priority 95 --distance 0 --threads 4 --histogram 25 --quiet --duration 30s"

resources:
  limits:
    cpu: 4
    memory: 500Mi
  requests:
    cpu: 4
    memory: 500Mi
```

### Long Duration Test (12 hours)

```yaml
config:
  rt_tests.yml: |-
    stress-ng: "--matrix 0 -t 12h"
    cyclictest: "-m -p95 -d0 -a 1-15 -t 16 -h400 -D 12h"

nodeSelector:
  kubernetes.io/hostname: worker-node-1
```

## Architecture & Design

### Why privileged mode is Required

**`privileged: true`** is mandatory because:
- Access to real-time scheduling policies (SCHED_FIFO)
- Memory locking (mlockall) to prevent page faults
- Accurate latency measurements without kernel interference

### Deployment Model

- **Job**: Runs once to completion
- **Parallel execution**: stress-ng and cyclictest run simultaneously
- **Results**: Stored in `hostOutputFolder` and pod logs

## Troubleshooting

### Job fails with permission errors
```bash
# Check security context
kubectl describe job rt-tests-chart-job | grep -A5 "Security Context"

# Ensure privileged mode is enabled
# securityContext.privileged: true must be set
```

### High latency results
```bash
# Verify CPU isolation
kubectl describe node <node-name> | grep -A10 "Allocated resources"

# Common causes:
# - No dedicated CPU cores (enable Static CPU Manager config in Kubernetes)
# - System under heavy load
# - No RT Kernel or no CPU isolation
# - Incorrect resource requests/limits
```

### Job doesn't complete
```bash
# Check pod status
kubectl get pods -l job-name=rt-tests-chart-job

# View logs
kubectl logs job/rt-tests-chart-job

# Common issues:
# - Insufficient resources
# - Node scheduling issues
```

## Support

- **Documentation**: [srsRAN Project Docs](https://docs.srsran.com)
- **rt-tests**: [rt-tests Wiki](https://wiki.linuxfoundation.org/realtime/documentation/howto/tools/rt-tests)

## License

AGPL-3.0 - See LICENSE file for details
