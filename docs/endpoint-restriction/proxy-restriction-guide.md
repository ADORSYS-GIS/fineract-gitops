# NGINX Ingress-Based Endpoint Restriction Guide

This document provides a guide on how to implement endpoint restrictions for Fineract applications using the NGINX Ingress Controller on Kubernetes.

## 1. Introduction

This guide assumes you have a running Kubernetes cluster with the NGINX Ingress Controller and OAuth2 Proxy deployed. The goal is to restrict access to API endpoints based on user roles, which are provided by an OIDC provider (like Keycloak) and passed to the NGINX Ingress Controller as a header (`X-Auth-Request-Roles`).

## 2. Keycloak Role Configuration

1.  **Create Roles:** In your Keycloak realm, define roles that correspond to the application roles (e.g., `account-manager`, `accountant`, `admin`, `branch-manager`, `cashier`).
2.  **Assign Roles to Users/Groups:** Assign these roles to the appropriate users or groups.
3.  **Configure Client Scopes:** Ensure your OAuth2 Proxy is configured to request the roles from Keycloak and pass them in the `X-Auth-Request-Roles` header to the upstream services.

## 3. NGINX Ingress Configuration

The endpoint restrictions are implemented centrally in the global NGINX Ingress Controller ConfigMap, located at `fineract-gitops/apps/ingress-nginx/base/configmap.yaml`. This approach is clean, scalable, and the recommended way to manage access control.

The logic uses a chain of two `map` directives within the `http-snippet` section of the ConfigMap.

### 3.1. Step 1: Endpoint Categorization

The first map, `$endpoint_category`, takes the HTTP method and the request URI as input and maps them to a category. Categories typically correspond to a specific role or a group of roles that share access to an endpoint.

**Note:** Reporting endpoints are categorized as `public` and are accessible to all authenticated users.

Here is a snippet of the map:

```nginx
map "$request_method:$request_uri" $endpoint_category {
    default                                                     "public";

    # Account Manager Endpoints
    "~^POST:/fineract-provider/api/v1/clients$"                  "account-manager";
    # ... more account manager endpoints

    # Shared Endpoints
    "~^GET:/fineract-provider/api/v1/offices$"                   "common-offices";
    # ... more shared endpoints
}
```

### 3.2. Step 2: Role-Based Authorization

The second map, `$rbac_allowed`, takes the endpoint category (from the first map) and the user's roles (from the `$http_x_auth_request_roles` header) as input. It outputs `1` if the user is allowed access and `0` otherwise.

Here is a snippet of the map:

```nginx
map "$endpoint_category:$http_x_auth_request_roles" $rbac_allowed {
    default                                           0;

    "~^public:.*"                                     1;
    "~^account-manager:.*account-manager.*"           1;
    # ... rules for other roles

    # Shared Endpoint Permissions
    "~^common-offices:.*(account-manager|accountant|admin|branch-manager).*" 1;
    # ... rules for other shared endpoints
}
```

### 3.3. Step 3: Enforcing the Decision

The final piece is a small snippet in the Ingress resource (`fineract-gitops/apps/ingress/base/fineract-oauth2-protected.yaml`) that checks the result of the `$rbac_allowed` map and denies access if it's `0`.

```yaml
nginx.ingress.kubernetes.io/configuration-snippet: |
  if ($rbac_allowed = 0) {
    return 403;
  }
```

This setup ensures that all the complex authorization logic is centralized in the `configmap.yaml`, keeping the Ingress resources clean and simple.

## 4. Testing the Configuration

1.  **Deploy the Changes:** After applying the configuration changes to your Kubernetes cluster, wait for the NGINX Ingress Controller to reload the configuration.
2.  **Login as a User with a Specific Role:** Access your Fineract application and log in as a user with a single role (e.g., `cashier`).
3.  **Try to Access a Restricted Endpoint:** Use a tool like `curl` or Postman to try to access an endpoint that the `cashier` role should not have access to (e.g., `/v1/glclosures`). You should receive a `403 Forbidden` error.
4.  **Try to Access an Allowed Endpoint:** Access an endpoint that the `cashier` role *should* have access to (e.g., `/v1/userdetails`). You should receive a successful response.
5.  **Repeat for Other Roles:** Repeat the testing process for each role to ensure that the restrictions are working correctly.

This guide provides a framework for understanding the implemented role-based endpoint restrictions. You may need to adapt the configuration to your specific environment and requirements.
