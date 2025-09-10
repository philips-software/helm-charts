# Homelab Overlay

This kustomize overlay configures the k8s-observability-monitoring application for homelab environments.

## Configuration

The overlay adds the following configuration to the Helm chart's `valuesObject`:

```yaml
otlp:
  destinations:
    - name: "otlpGateway"
      url: "https://otlp-gateway.obs-us-east-ct.hsp.philips.com"
      secret:
        name: "otlp-gateway-creds"
```

This configures the observability monitoring to send telemetry data to the homelab OTLP gateway.

## Usage

To deploy this configuration:

```bash
kustomize build /path/to/k8s-monitoring/kustomize/overlays/homelab | kubectl apply -f -
```

Or use with ArgoCD by pointing to this overlay directory.