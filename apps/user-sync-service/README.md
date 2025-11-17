# Fineract-Keycloak User Sync Service

This microservice is responsible for synchronizing user data from Fineract (as the source of truth) to Keycloak (as the identity provider). It provides a RESTful API to create, update, and manage users in Keycloak based on data from Fineract.

## 1. Architecture

The User Sync Service acts as a bridge between Fineract and Keycloak. It is designed to be called by frontend applications (such as the Staff Dashboard) or other backend services whenever a user is created or updated in Fineract.

```mermaid
sequenceDiagram
    participant Frontend as Frontend App
    participant Fineract as Fineract API
    participant UserSync as User Sync Service
    participant Keycloak as Keycloak API

    Frontend->>+Fineract: Create/Update User
    Fineract-->>-Frontend: User Data

    Frontend->>+UserSync: POST /sync/user (with Fineract User Data)
    UserSync->>+Keycloak: GET /users (check if user exists)
    Keycloak-->>-UserSync: User Found or Not Found

    alt User Does Not Exist
        UserSync->>+Keycloak: POST /users (create user)
        Keycloak-->>-UserSync: User Created (with temporary password)
        UserSync-->>-Frontend: 201 Created (with temporary password)
    else User Exists
        UserSync->>+Keycloak: PUT /users/{id} (update user)
        Keycloak-->>-UserSync: User Updated
        UserSync-->>-Frontend: 200 OK (user updated)
    end
```

## 2. Features

*   **Single User Sync**: Create or update individual users in Keycloak from Fineract data.
*   **Bulk User Sync**: Migrate multiple users at once.
*   **Role Mapping**: Automatically map Fineract roles to corresponding Keycloak roles.
*   **Group Assignment**: Assign users to appropriate groups in Keycloak based on their Fineract office.
*   **Secure Password Generation**: Generate cryptographically secure temporary passwords for new users.
*   **Required Actions**: Force new users to change their password and set up multi-factor authentication (MFA) on their first login.
*   **Custom Attributes**: Store Fineract-specific metadata (e.g., `office_id`, `employee_id`) as custom attributes in Keycloak.

## 3. API Endpoints

### POST /sync/user

Synchronizes a single user from Fineract to Keycloak. If the user does not exist in Keycloak, it will be created. If the user already exists, their information will be updated.

**Request Body:**
```json
{
  "userId": 123,
  "username": "john.doe",
  "email": "john.doe@webank.com",
  "firstName": "John",
  "lastName": "Doe",
  "role": "Loan Officer",
  "officeId": 1,
  "officeName": "Head Office",
  "employeeId": "EMP001",
  "mobileNumber": "+254712345678"
}
```

**Responses:**
*   **201 Created**: If the user was successfully created in Keycloak.
    ```json
    {
      "status": "success",
      "message": "User john.doe synced to Keycloak successfully",
      "keycloak_user_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "temporary_password": "Xy9$mK2#pL4!qR8@",
      "required_actions": ["UPDATE_PASSWORD", "VERIFY_EMAIL", "webauthn-register"]
    }
    ```
*   **200 OK**: If the user already existed and was updated.
    ```json
    {
      "status": "exists",
      "message": "User john.doe already exists in Keycloak and was updated",
      "keycloak_user_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479"
    }
    ```

### POST /sync/bulk

Bulk synchronizes multiple users.

**Request Body:**
```json
{
  "users": [
    { "userId": 1, "username": "user1", "email": "user1@webank.com", ... },
    { "userId": 2, "username": "user2", "email": "user2@webank.com", ... }
  ]
}
```

**Response (200 OK):**
```json
{
  "total": 10,
  "created": 8,
  "updated": 1,
  "failed": 1,
  "details": [
    { "username": "user1", "status": "created", "temp_password": "Abc123!@#Xyz" },
    { "username": "user2", "status": "updated" }
  ]
}
```

### GET /user/<username>

Retrieves user details from Keycloak.

**Response (200 OK):**
```json
{
  "status": "success",
  "user": {
    "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "username": "john.doe",
    "email": "john.doe@webank.com",
    ...
  }
}
```

### GET /health

A health check endpoint to verify the service's status and its connection to Keycloak.

**Response (200 OK):**
```json
{
  "status": "healthy",
  "service": "fineract-keycloak-sync",
  "keycloak_connected": true,
  "realm": "fineract"
}
```

## 4. Role and Group Mapping

The service maps Fineract roles to Keycloak roles and groups to provide appropriate permissions.

| Fineract Role | Keycloak Role | Keycloak Group |
|---------------|---------------|----------------|
| Super User | `admin` | `head-office` |
| Admin | `admin` | `head-office` |
| Branch Manager | `branch-manager`| `branch-managers`|
| Loan Officer | `loan-officer` | `loan-officers` |
| Teller | `teller` | `tellers` |
| Cashier | `teller` | `tellers` |
| Accountant | `accountant` | - |
| Auditor | `readonly` | - |
| Client | `client` | `clients` |
| Staff | `staff` | - |

## 5. Configuration

The service is configured using environment variables.

| Variable | Description | Default | Required |
|-----------------------|------------------------------------------------|--------------------------------|----------|
| `KEYCLOAK_URL` | The URL of the Keycloak server. | `http://keycloak-service:8080` | Yes |
| `KEYCLOAK_REALM` | The Keycloak realm to use. | `fineract` | Yes |
| `ADMIN_CLI_CLIENT_ID` | The client ID for the Keycloak admin CLI. | `admin-cli` | Yes |
| `ADMIN_CLI_SECRET` | The client secret for the Keycloak admin CLI.| - | **Yes** |
| `PORT` | The port on which the service will run. | `5000` | No |
| `LOG_LEVEL` | The logging level for the application. | `INFO` | No |

## 6. Deployment

The User Sync Service is deployed using **GitOps with ArgoCD** for automated Kubernetes deployment.

### Deployment Architecture

```
Manual Image Build → Git Commit → ArgoCD Sync → Kubernetes Deploy
```

### Prerequisites

*   A running Kubernetes cluster
*   A running Keycloak instance
*   Docker installed locally for image builds
*   ArgoCD installed in the cluster
*   Required Kubernetes secrets (see below)

### Quick Start

**For detailed deployment instructions, see [DEPLOYMENT.md](./DEPLOYMENT.md)**

#### Step 1: Build Docker Image (Manual)

```bash
cd operations/keycloak-config/user-sync-service
docker build -t fineract-keycloak-sync:latest .
# Note: Image registry setup is deferred. Currently using :latest tag.
```

#### Step 2: Deploy via GitOps

```bash
# Commit changes (if any)
git add operations/keycloak-config/user-sync-service/
git add argocd/applications/operations/user-sync-service.yaml
git commit -m "feat: deploy user-sync-service"
git push origin develop

# ArgoCD automatically syncs within 3 minutes
# Or trigger manual sync:
argocd app sync user-sync-service
```

#### Step 3: Verify Deployment

```bash
# Check pod status
kubectl get pods -n fineract-dev -l app.kubernetes.io/name=fineract-keycloak-sync

# View logs
kubectl logs -n fineract-dev deployment/fineract-keycloak-sync

# Test health endpoint
kubectl port-forward -n fineract-dev svc/fineract-keycloak-sync 5000:5000
curl http://localhost:5000/health
```

### Required Secrets

Create these secrets before deployment:

```bash
# keycloak-client-secrets (admin-cli key)
kubectl create secret generic keycloak-client-secrets \
  --from-literal=admin-cli=<your-admin-cli-secret> \
  -n fineract-dev

# keycloak-admin-credentials (admin username/password)
kubectl create secret generic keycloak-admin-credentials \
  --from-literal=username=admin \
  --from-literal=password=<your-admin-password> \
  -n fineract-dev
```

### Configuration Structure

```
operations/keycloak-config/user-sync-service/
├── base/                  # Base Kubernetes manifests
│   ├── kustomization.yaml # Base configuration
│   └── deployment.yaml    # Deployment, Service, ServiceAccount
├── overlays/
│   └── dev/               # Dev environment overrides
│       └── kustomization.yaml
└── DEPLOYMENT.md          # Detailed deployment guide
```

### ArgoCD Application

The service is managed by ArgoCD Application at:
`argocd/applications/operations/user-sync-service.yaml`

- **Auto-sync**: Enabled
- **Self-heal**: Enabled
- **Prune**: Enabled
- **Namespace**: fineract-dev

### Legacy Deployment (Manual)

The old manual deployment method using `kubectl apply -f k8s/deployment.yaml` is deprecated.
Use the GitOps method above instead.

## 7. Monitoring and Troubleshooting

### Monitoring

*   **Health Checks**: Regularly poll the `/health` endpoint to ensure the service is running and connected to Keycloak.
*   **Logs**: Monitor the service's logs for errors, especially for failed user sync attempts.
*   **Metrics**:
    *   `user_sync_success_total`: Counter for successful user syncs.
    *   `user_sync_failed_total`: Counter for failed user syncs.
    *   `user_sync_latency_seconds`: Histogram of user sync latency.

### Troubleshooting

*   **"Keycloak error" during user sync**:
    *   **Cause**: The `ADMIN_CLI_SECRET` is incorrect, or the `admin-cli` client does not have the necessary permissions in Keycloak.
    *   **Solution**:
        1.  Verify the `ADMIN_CLI_SECRET` in the `user-sync-admin-cli-secret` Kubernetes secret.
        2.  In the Keycloak admin console, ensure the `admin-cli` client has the `realm-admin` role.

*   **"User already exists"**:
    *   **Cause**: A user with the same username already exists in Keycloak.
    *   **Solution**: This is not an error. The service will attempt to update the existing user. If you need to create a new user, ensure the username is unique.

## 8. Security Considerations

*   **Secret Management**: The `ADMIN_CLI_SECRET` is sensitive and should be managed securely using sealed secrets or another secret management solution.
*   **Network Policies**: The service should be protected by network policies that only allow traffic from trusted sources (e.g., the frontend gateway).
*   **Resource Limits**: The Kubernetes deployment includes resource requests and limits to prevent the service from consuming excessive resources.
*   **Non-root Container**: The Docker container runs as a non-root user to reduce the attack surface.
*   **Read-only Filesystem**: The container's root filesystem is set to read-only to prevent modifications at runtime.

## 9. Dependencies

*   Python 3.9+
*   Flask
*   requests
*   python-keycloak

## 10. Development

### Local Setup

1.  **Install dependencies**:
    ```bash
    pip install -r requirements.txt
    ```

2.  **Set environment variables**:
    ```bash
    export KEYCLOAK_URL="http://localhost:8080"
    export KEYCLOAK_REALM="fineract"
    export ADMIN_CLI_CLIENT_ID="admin-cli"
    export ADMIN_CLI_SECRET="your-local-admin-cli-secret"
    export PORT="5000"
    ```

3.  **Run the service**:
    ```bash
    python app/sync_service.py
    ```

### Running Tests

```bash
# Run unit tests
pytest

# Run integration tests (requires a running Keycloak instance)
pytest --integration
```
