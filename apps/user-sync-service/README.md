# User Sync Service

The User Sync Service is a Python-based microservice responsible for synchronizing user data between Apache Fineract and Keycloak. It provides endpoints for creating users in Keycloak, managing their status, and handling password resets, acting as a bridge between the Fineract user management in the admin frontend and the Keycloak identity provider.

## Overview

This service is a critical component for integrating Fineract's user management with the centralized authentication system provided by Keycloak. When an administrator creates a new user in the Fineract admin application, a request is sent to this service to create a corresponding user in Keycloak with the appropriate roles and a temporary password.

**Key Features**:
-   Creates users in Keycloak with a temporary password and forces a password change on the first login.
-   Maps Fineract roles to Keycloak roles.
-   Handles user status updates (enabling/disabling users).
-   Initiates password reset flows via Keycloak.
-   Provides a health check endpoint for monitoring.

## Architecture

The User Sync Service is deployed as a standalone microservice within the Kubernetes cluster. It is not directly exposed to the internet but is accessible through the Ingress NGINX controller, which routes requests from the frontend applications.

```
Browser → Ingress NGINX → OAuth2 Proxy → User Sync Service
```

-   **Frontend**: The Fineract admin app makes API calls to the User Sync Service.
-   **Ingress NGINX**: Routes requests to `/api/user-sync` to the service.
-   **OAuth2 Proxy**: Secures the service, ensuring only authenticated users can access it.
-   **User Sync Service**: A Flask application that communicates with the Keycloak Admin API.

## Components

### Deployment (`deployment.yaml`)

-   **Image**: `ghcr.io/adorsys-gis/fineract-apps/user-sync-service:main`
-   A Python Flask application.
-   Runs as a non-root user with a read-only root filesystem for security.

### Service (`service.yaml`)

-   **Type**: ClusterIP
-   **Port**: 5000 (HTTP)
-   Exposes the service internally within the cluster.

### ConfigMap (`configmap.yaml`)

-   Holds non-sensitive configuration, such as the Keycloak URL and realm.
-   Sensitive data (client secrets, admin credentials) is managed via Sealed Secrets.

## Configuration

The service is configured through a combination of a `ConfigMap` for non-sensitive data and `Sealed Secrets` for sensitive credentials.

### ConfigMap (`configmap.yaml`)

The following variables are configured in `apps/user-sync-service/base/configmap.yaml`:

| Variable         | Value                               | Description                                     |
| ---------------- | ----------------------------------- | ----------------------------------------------- |
| `KEYCLOAK_URL`   | `http://keycloak-service:8080/auth` | The internal URL of the Keycloak service.       |
| `KEYCLOAK_REALM` | `fineract`                          | The Keycloak realm for Fineract.                |

**Note**: The `KEYCLOAK_URL` is hardcoded to the internal Kubernetes service URL, as the User Sync Service communicates with Keycloak directly within the cluster. This value does not need to be changed for different environments.

### Secrets (Managed by Sealed Secrets)

The following sensitive variables must be created as `SealedSecret` resources in each environment:

| Variable                  | Description                                      |
| ------------------------- | ------------------------------------------------ |
| `KEYCLOAK_CLIENT_ID`      | The client ID for the User Sync Service.         |
| `KEYCLOAK_CLIENT_SECRET`  | The client secret for the User Sync Service.     |
| `KEYCLOAK_ADMIN_USER`     | The username for the Keycloak admin user.        |
| `KEYCLOAK_ADMIN_PASSWORD` | The password for the Keycloak admin user.        |

These secrets are environment-specific and should be managed securely.

## Deployment

The User Sync Service is deployed via an ArgoCD Application.

### Manual Deployment

```bash
# Deploy to development
kubectl apply -k apps/user-sync-service/base

# Verify deployment
kubectl get pods -n fineract-dev -l app=user-sync-service
```

## Routing

The service is accessible at `/api/user-sync`, which is routed by the Ingress NGINX controller. This path needs to be added to the existing Ingress configuration to route traffic to the `user-sync-service`.

## Security

-   **Non-root user**: The container runs as a non-root user.
-   **Read-only root filesystem**: The root filesystem is read-only.
-   **OAuth2 authentication**: All requests are authenticated via OAuth2 Proxy.
-   **Secrets Management**: Sensitive configuration is managed by Sealed Secrets.
