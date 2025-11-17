# Keycloak Webank Theme Deployment

This document describes how the Webank custom theme is deployed to Keycloak via GitOps.

## Architecture

The Webank theme is automatically deployed using:

1. **ConfigMaps** - Store theme files in Git
2. **Init Container** - Copies theme files to persistent storage on pod startup
3. **PVC** - Provides persistent storage for themes across pod restarts
4. **GitOps** - Any theme updates in Git are automatically deployed

## Components

### ConfigMaps

- `keycloak-webank-theme` - Contains FreeMarker templates, properties, and messages
- `keycloak-webank-theme-css` - Contains CSS stylesheets

### PersistentVolumeClaim

- `keycloak-themes` - 50Mi PVC for storing custom themes

### Init Container

The `deploy-webank-theme` init container runs before Keycloak starts and:
1. Creates the theme directory structure
2. Copies files from ConfigMaps to the PVC
3. Ensures theme is available when Keycloak starts

### Volume Mounts

- Main container: `/opt/keycloak/themes/webank` (read-only)
- Init container: `/themes` (read-write for initial deployment)

## Theme Structure

```
/opt/keycloak/themes/webank/
├── theme.properties
└── login/
    ├── template.ftl
    ├── login.ftl
    ├── messages/
    │   └── messages_en.properties
    └── resources/
        ├── css/
        │   └── webank.css
        ├── img/
        └── js/
```

## Updating the Theme

To update the theme:

1. Edit theme files in the ConfigMaps:
   - `apps/keycloak/base/theme-configmap.yaml`
   - `apps/keycloak/base/theme-css-configmap.yaml`

2. Commit and push changes to Git

3. ArgoCD will automatically:
   - Update the ConfigMaps
   - Restart the Keycloak pod (to trigger init container)
   - The init container will copy the new theme files

4. Clear Keycloak theme cache (if needed):
   ```bash
   kubectl exec -n keycloak deployment/keycloak -- \
     /opt/keycloak/bin/kc.sh build
   ```

## Theme Activation

The theme is activated in the realm configuration:

```yaml
# operations/keycloak-config/base/config/realm-fineract.yaml
loginTheme: webank
accountTheme: webank
adminTheme: keycloak
emailTheme: webank
```

## Advantages of This Approach

1. **GitOps-friendly** - All theme files are versioned in Git
2. **No custom Docker image** - Uses standard Keycloak image
3. **Easy updates** - Change ConfigMap, commit, and ArgoCD deploys
4. **Persistent** - Theme survives pod restarts via PVC
5. **Rollback-friendly** - Git revert to roll back theme changes

## Development Workflow

### Local Testing

1. Edit theme files in `operations/keycloak-config/themes/webank/`
2. Copy changes to ConfigMaps
3. Test with `kubectl kustomize apps/keycloak/base`
4. Deploy and verify

### Production Deployment

1. Make theme changes in `apps/keycloak/base/theme-*.yaml`
2. Commit to Git
3. Push to repository
4. ArgoCD syncs automatically
5. Keycloak pod restarts with new theme

## Troubleshooting

### Theme not appearing

Check init container logs:
```bash
kubectl logs -n keycloak deployment/keycloak -c deploy-webank-theme
```

### Theme files missing

Verify ConfigMap contents:
```bash
kubectl get configmap keycloak-webank-theme -n keycloak -o yaml
```

### Theme cache issues

Clear Keycloak cache:
```bash
kubectl exec -n keycloak deployment/keycloak -- \
  rm -rf /opt/keycloak/data/tmp/kc-gzip-cache
```

### Verify theme files in pod

```bash
kubectl exec -n keycloak deployment/keycloak -- \
  ls -la /opt/keycloak/themes/webank/login/resources/css/
```

## Future Enhancements

- Add email templates for password reset, verification, etc.
- Add account theme templates
- Add localization for additional languages (French, Swahili)
- Add custom error pages
- Add WebAuthn registration templates
