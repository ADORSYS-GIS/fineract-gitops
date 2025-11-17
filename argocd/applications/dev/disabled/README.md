# Disabled ArgoCD Applications

This directory contains ArgoCD application manifests that are intentionally disabled for the development environment.

## Currently Disabled Applications

### logging.yaml
**Status**: Disabled
**Reason**: Logging infrastructure (Loki, Promtail) not needed for development environment
**Components**: Loki, Promtail, log aggregation
**To Enable**: Move to parent directory (`argocd/applications/dev/`)

### monitoring.yaml
**Status**: Disabled
**Reason**: Full monitoring stack (Prometheus, Grafana, Alertmanager) not needed for development
**Components**: Prometheus, Grafana, Alertmanager
**To Enable**: Move to parent directory (`argocd/applications/dev/`)

## Why Are These Disabled?

For the development environment, we've opted for a minimal setup to:
1. **Reduce Resource Usage**: Development cluster has limited resources
2. **Faster Deployment**: Fewer components mean quicker deployment cycles
3. **Simpler Debugging**: Fewer moving parts during development
4. **Cost Optimization**: Monitoring/logging add infrastructure costs

## When to Enable

Consider enabling these applications when:
- **Logging**: You need to debug issues across multiple pods or track events over time
- **Monitoring**: You need metrics, dashboards, or alerting for performance testing

## Enabling Applications

To enable any application:

```bash
# Move the application to the active directory
mv argocd/applications/dev/disabled/logging.yaml argocd/applications/dev/

# Commit and push
git add argocd/applications/dev/
git commit -m "feat: enable logging for dev environment"
git push

# ArgoCD will automatically detect and deploy the application
```

## Production/UAT Environments

These applications are typically **enabled** in UAT and Production environments for:
- Production monitoring and alerting
- Compliance and audit logging
- Performance tracking
- Incident response

---

**Last Updated**: January 2025
