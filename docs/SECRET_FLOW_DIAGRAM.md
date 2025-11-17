# Secret Flow: How Apps Use the Right Secrets

## 🔐 Complete Secret Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                         SECRET LIFECYCLE                              │
└──────────────────────────────────────────────────────────────────────┘

PHASE 1: CREATION (Local Machine)
═══════════════════════════════════════════════

┌─────────────────┐
│  Terraform      │  Outputs secret values
│  (AWS)          │  (RDS password, S3 buckets, etc.)
└────────┬────────┘
         │
         v
┌─────────────────┐
│  Script         │  ./scripts/seal-terraform-secrets.sh dev
│  (seal-*.sh)    │
└────────┬────────┘
         │
         v
┌─────────────────┐
│  kubectl create │  Creates secret YAML (in memory)
│  --dry-run      │  Never saved to disk!
└────────┬────────┘
         │
         v
┌─────────────────┐
│  kubeseal       │  Encrypts with cluster's public key
│  (CLI tool)     │  Uses RSA-2048 encryption
└────────┬────────┘
         │
         v
┌─────────────────┐
│  SealedSecret   │  secrets/dev/rds-connection-sealed.yaml
│  (encrypted)    │  ✅ SAFE TO COMMIT TO GIT
└────────┬────────┘
         │
         v
┌─────────────────┐
│  Git Repository │  git add → commit → push
│  (GitHub)       │  Encrypted secrets in version control
└────────┬────────┘
         │
         │
         │
PHASE 2: DEPLOYMENT (Kubernetes Cluster)
═══════════════════════════════════════════════
         │
         v
┌─────────────────┐
│  ArgoCD         │  Syncs from Git repository
│  (GitOps)       │  Detects new/changed SealedSecrets
└────────┬────────┘
         │
         v
┌─────────────────────────────────────────────┐
│  Kubernetes API Server                      │
│  ├─ Namespace: fineract-dev                 │
│  └─ Resource: SealedSecret/rds-connection   │
└────────┬────────────────────────────────────┘
         │
         v
┌─────────────────────────────────────────────┐
│  Sealed Secrets Controller                  │
│  (runs in kube-system namespace)            │
│                                             │
│  1. Watches for SealedSecret resources      │
│  2. Retrieves cluster's private key         │
│  3. Decrypts SealedSecret                   │
│  4. Creates regular Secret                  │
└────────┬────────────────────────────────────┘
         │
         v
┌─────────────────────────────────────────────┐
│  Kubernetes Secret                          │
│  Name: rds-connection                       │
│  Namespace: fineract-dev                    │
│  Type: Opaque                               │
│                                             │
│  Data:                                      │
│    host: fineract...rds.amazonaws.com       │
│    port: 5432                               │
│    database: fineract                       │
│    username: fineract                       │
│    password: <decrypted>                    │
└────────┬────────────────────────────────────┘
         │
         │
         │
PHASE 3: CONSUMPTION (Application Pods)
═══════════════════════════════════════════════
         │
         v
┌─────────────────────────────────────────────┐
│  Fineract Deployment                        │
│  (deployment-write.yaml)                    │
│                                             │
│  env:                                       │
│  - name: FINERACT_HIKARI_USERNAME           │
│    valueFrom:                               │
│      secretKeyRef:                          │
│        name: fineract-db-credentials  ◄─────┼─ References secret
│        key: username                        │   by name & key
│                                             │
│  - name: FINERACT_HIKARI_PASSWORD           │
│    valueFrom:                               │
│      secretKeyRef:                          │
│        name: fineract-db-credentials  ◄─────┼─ Same secret,
│        key: password                        │   different key
└────────┬────────────────────────────────────┘
         │
         v
┌─────────────────────────────────────────────┐
│  Kubelet (on K3s node)                      │
│                                             │
│  1. Reads Deployment spec                   │
│  2. Looks up Secret in namespace            │
│  3. Extracts values for specified keys      │
│  4. Mounts as environment variables         │
└────────┬────────────────────────────────────┘
         │
         v
┌─────────────────────────────────────────────┐
│  Fineract Pod (Running Container)           │
│                                             │
│  Environment Variables:                     │
│    FINERACT_HIKARI_USERNAME=fineract        │
│    FINERACT_HIKARI_PASSWORD=<actual-pwd>    │
│                                             │
│  Application Code:                          │
│    System.getenv("FINERACT_HIKARI_USERNAME")│
│    → Returns: "fineract"                    │
└─────────────────────────────────────────────┘
```

---

## 🔗 Secret Name Mapping

### **How Apps Find the Right Secret**

The **secret name** in your deployment MUST match the **secret name** created by Sealed Secrets.

| Sealed Secret File | K8s Secret Name | Used By | Environment Variables |
|-------------------|-----------------|---------|----------------------|
| `rds-connection-sealed.yaml` | `rds-connection` | Fineract | `FINERACT_DEFAULT_TENANTDB_*` |
| `aws-rds-credentials-sealed.yaml` | `aws-rds-credentials` | Fineract | `FINERACT_DEFAULT_TENANTDB_HOSTNAME` |
| `fineract-db-credentials-sealed.yaml` | `fineract-db-credentials` | Fineract | `FINERACT_HIKARI_USERNAME`, `FINERACT_HIKARI_PASSWORD` |
| `s3-connection-sealed.yaml` | `s3-connection` | Fineract | (IRSA - no env vars needed) |
| `smtp-credentials-sealed.yaml` | `smtp-credentials` | Keycloak | SMTP config |
| `redis-credentials-sealed.yaml` | `redis-credentials` | Redis | `REDIS_PASSWORD` |
| `keycloak-admin-credentials-sealed.yaml` | `keycloak-admin-credentials` | Keycloak | `KEYCLOAK_ADMIN`, `KEYCLOAK_ADMIN_PASSWORD` |

---

## 📝 Example: Complete Secret Flow

### **1. Script Creates Sealed Secret**

```bash
# seal-terraform-secrets.sh does this:
kubectl create secret generic fineract-db-credentials \
  --namespace=fineract-dev \
  --from-literal=username=fineract \
  --from-literal=password=SuperSecret123 \
  --dry-run=client -o yaml | \
kubeseal -o yaml > secrets/dev/fineract-db-credentials-sealed.yaml
```

### **2. Sealed Secret in Git**

```yaml
# secrets/dev/fineract-db-credentials-sealed.yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: fineract-db-credentials
  namespace: fineract-dev
spec:
  encryptedData:
    username: AgBK7xQ... # Encrypted "fineract"
    password: AgC9mP... # Encrypted "SuperSecret123"
  template:
    metadata:
      name: fineract-db-credentials
      namespace: fineract-dev
    type: Opaque
```

### **3. ArgoCD Deploys to Cluster**

```bash
# ArgoCD applies the SealedSecret
kubectl apply -f secrets/dev/fineract-db-credentials-sealed.yaml
```

### **4. Controller Decrypts**

```bash
# Sealed Secrets controller watches and decrypts
# Creates this regular secret:

apiVersion: v1
kind: Secret
metadata:
  name: fineract-db-credentials
  namespace: fineract-dev
type: Opaque
data:
  username: ZmluZXJhY3Q=          # base64("fineract")
  password: U3VwZXJTZWNyZXQxMjM=  # base64("SuperSecret123")
```

### **5. Deployment References Secret**

```yaml
# apps/fineract/base/deployment-write.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fineract-write
  namespace: fineract-dev
spec:
  template:
    spec:
      containers:
      - name: fineract
        env:
        - name: FINERACT_HIKARI_USERNAME
          valueFrom:
            secretKeyRef:
              name: fineract-db-credentials  # ← MUST MATCH secret name
              key: username                   # ← MUST MATCH secret key

        - name: FINERACT_HIKARI_PASSWORD
          valueFrom:
            secretKeyRef:
              name: fineract-db-credentials  # ← Same secret
              key: password                   # ← Different key
```

### **6. Pod Gets Environment Variables**

```bash
# Inside the running pod:
$ echo $FINERACT_HIKARI_USERNAME
fineract

$ echo $FINERACT_HIKARI_PASSWORD
SuperSecret123
```

### **7. Application Uses Values**

```java
// Fineract application code
String username = System.getenv("FINERACT_HIKARI_USERNAME");
String password = System.getenv("FINERACT_HIKARI_PASSWORD");

// Connects to database with these credentials
```

---

## 🎯 Critical Matching Requirements

For apps to use secrets correctly, these MUST match:

### ✅ **1. Namespace Match**

```yaml
# Sealed Secret
metadata:
  namespace: fineract-dev

# Deployment
metadata:
  namespace: fineract-dev

# ✅ BOTH in fineract-dev namespace
```

### ✅ **2. Secret Name Match**

```yaml
# Sealed Secret creates:
metadata:
  name: fineract-db-credentials

# Deployment references:
secretKeyRef:
  name: fineract-db-credentials

# ✅ Names EXACTLY match
```

### ✅ **3. Key Name Match**

```yaml
# Sealed Secret has keys:
encryptedData:
  username: ...
  password: ...

# Deployment references keys:
secretKeyRef:
  key: username  # ✅ Matches
secretKeyRef:
  key: password  # ✅ Matches
```

---

## 🔍 Debugging Secret Issues

### **Check if Sealed Secret exists:**
```bash
kubectl get sealedsecret fineract-db-credentials -n fineract-dev
```

### **Check if regular Secret was created:**
```bash
kubectl get secret fineract-db-credentials -n fineract-dev
```

### **Check Secret has correct keys:**
```bash
kubectl get secret fineract-db-credentials -n fineract-dev -o yaml
```

### **Check Pod can access Secret:**
```bash
kubectl describe pod <fineract-pod-name> -n fineract-dev
# Look for "Events" section - shows if secret is missing
```

### **Check controller logs:**
```bash
kubectl logs -n kube-system deployment/sealed-secrets-controller
```

### **Verify environment variables in Pod:**
```bash
kubectl exec -it <fineract-pod-name> -n fineract-dev -- env | grep FINERACT_HIKARI
```

---

## 🚨 Common Mistakes

### ❌ **Wrong Namespace**
```yaml
# Sealed Secret in: fineract-dev
# Deployment in: fineract-prod
# Result: Secret not found!
```

### ❌ **Typo in Secret Name**
```yaml
# Created: fineract-db-credentials
# Referenced: fineract-database-credentials
# Result: Secret not found!
```

### ❌ **Wrong Key Name**
```yaml
# Secret has key: username
# Deployment asks for: user
# Result: Key not found in secret!
```

### ❌ **Secret Not Decrypted**
```yaml
# SealedSecret exists
# But controller not running
# Result: No regular Secret created!
```

---

## ✅ Best Practices

1. **Use Descriptive Names**
   - `rds-connection` (good)
   - `secret1` (bad)

2. **Keep Keys Consistent**
   - Always use `username`, `password` (not `user`, `pass`, `pwd`)

3. **Document Secret Schema**
   ```yaml
   # fineract-db-credentials contains:
   # - username: Database username
   # - password: Database password
   ```

4. **Verify After Creating**
   ```bash
   kubectl get secret <name> -n <namespace>
   ```

5. **Test Secret Values**
   ```bash
   kubectl get secret <name> -n <namespace> -o json | \
     jq -r '.data.username' | base64 -d
   ```

---

## 🎉 Summary

**Q: How do apps use the right secret?**

**A: Through exact name and key matching:**

1. ✅ Sealed Secret created with specific **name** and **keys**
2. ✅ Controller decrypts into regular Secret (same name/keys)
3. ✅ Deployment references Secret by **exact name**
4. ✅ Deployment references specific **keys** in Secret
5. ✅ Kubelet injects Secret values as environment variables
6. ✅ Application reads environment variables

**The magic:** Kubernetes matches by **namespace + name + key**!

As long as these match, your apps will always find and use the correct secrets! 🎯
