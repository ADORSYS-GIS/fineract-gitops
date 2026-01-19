# NGINX Ingress-Based Endpoint Restriction Guide

This document provides a guide on how to implement endpoint restrictions for Fineract applications using the NGINX Ingress Controller on Kubernetes.

## 1. Introduction

This guide assumes you have a running Kubernetes cluster with the NGINX Ingress Controller and OAuth2 Proxy deployed. The goal is to restrict access to API endpoints based on user roles, which are provided by an OIDC provider (like Keycloak) and passed to the NGINX Ingress Controller as a header (`X-Auth-Request-Roles`).

## 2. Keycloak Role Configuration

1.  **Create Roles:** In your Keycloak realm, define roles that correspond to the application roles (e.g., `account-manager`, `accountant`, `admin`, `branch-manager`, `cashier`, `reporting-user`).
2.  **Assign Roles to Users/Groups:** Assign these roles to the appropriate users or groups.
3.  **Configure Client Scopes:** Ensure your OAuth2 Proxy is configured to request the roles from Keycloak and pass them in the `X-Auth-Request-Roles` header to the upstream services.

## 3. NGINX Ingress Configuration

The endpoint restrictions are implemented directly in the Ingress resource that protects the Fineract API endpoints. The primary file for this configuration is `fineract-gitops/apps/ingress/base/fineract-oauth2-protected.yaml`.

### 3.1. Restriction using Ingress Annotations

The access control logic is added to the `nginx.ingress.kubernetes.io/configuration-snippet` annotation. This approach keeps the routing and authorization logic for a specific service in one place.

Here is a snippet from the configuration:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fineract-oauth2-protected
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      set $allowed 0;

      # Allow authentication endpoint for all authenticated users
      if ($request_uri ~* "^/fineract-provider/api/v1/authentication$") {
          set $allowed 1;
      }

      # Account Manager role
      if ($http_x_auth_request_roles ~* "account-manager") {
          if ($request_uri ~* "^/fineract-provider/api/v1/clients$") { set $allowed 1; }
          # ... more rules for account-manager
      }

      # Accountant role
      if ($http_x_auth_request_roles ~* "accountant") {
          if ($request_uri ~* "^/fineract-provider/api/v1/makercheckers$") { set $allowed 1; }
          # ... more rules for accountant
      }

      # ... rules for all other roles

      if ($allowed = 0) {
          return 403;
      }
```

This configuration works as follows:
1.  A variable `$allowed` is initialized to `0` (deny).
2.  The `/fineract-provider/api/v1/authentication` endpoint is always allowed for logged-in users.
3.  For each role, it checks if the `X-Auth-Request-Roles` header contains the role name.
4.  If the role matches, it checks the `$request_uri` against a series of regular expressions that correspond to the allowed endpoints for that role.
5.  If a match is found, the `$allowed` variable is set to `1` (allow).
6.  Finally, if `$allowed` is still `0`, the request is denied with a `403 Forbidden` error.

The complete list of endpoints for each role is defined in the `role-endpoint-mapping.md` document.

### 3.2. Alternative: Centralized RBAC with ConfigMap

An alternative and often cleaner approach is to use the global NGINX Ingress Controller ConfigMap, located at `fineract-gitops/apps/ingress-nginx/base/configmap.yaml`. This file contains a centralized RBAC mechanism using NGINX `map` directives.

This approach is more scalable and is recommended for managing complex access rules. However, for the current setup, the annotation-based approach in `fineract-oauth2-protected.yaml` is what is implemented.

## 4. Testing the Configuration

1.  **Deploy the Changes:** After applying the configuration changes to your Kubernetes cluster, wait for the NGINX Ingress Controller to reload the configuration.
2.  **Login as a User with a Specific Role:** Access your Fineract application and log in as a user with a single role (e.g., `cashier`).
3.  **Try to Access a Restricted Endpoint:** Use a tool like `curl` or Postman to try to access an endpoint that the `cashier` role should not have access to (e.g., `/v1/glclosures`). You should receive a `403 Forbidden` error.
4.  **Try to Access an Allowed Endpoint:** Access an endpoint that the `cashier` role *should* have access to (e.g., `/v1/userdetails`). You should receive a successful response.
5.  **Repeat for Other Roles:** Repeat the testing process for each role to ensure that the restrictions are working correctly.

This guide provides a framework for understanding the implemented role-based endpoint restrictions. You may need to adapt the configuration to your specific environment and requirements.
