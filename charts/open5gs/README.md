# Open5GS Helm Chart Example

This is an example values.yaml file for the Open5GS Operator Helm chart from Gradiant. Please refer to their Github repository for more information on the chart. https://github.com/Gradiant/open5gs-operator

## Installing the Chart

This is a quickstart guide to install the Open5GS Operator and deploy Open5GS using the provided YAML files. In case you run into issues or have questions, please refer to the official documentation of the Open5GS Operator Helm chart.

On target node:
```bash
mkdir -p /mnt/data/open5gs-sample-mongodb
chown -R 999:999 /mnt/data/open5gs-sample-mongodb
chmod 770 /mnt/data/open5gs-sample-mongodb
```

Deploy operator:
```bash
helm install open5gs-operator oci://registry-1.docker.io/gradiantcharts/open5gs-operator -f open5gs-operator-values.yaml
```

Deploy Open5gs:
```bash
kubectl apply -f open5gs-deployment.yaml
```
