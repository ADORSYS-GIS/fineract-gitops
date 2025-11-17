# Frontend Configuration Examples

This directory contains ready-to-use configuration file templates for developing Fineract frontend applications locally.

## Available Templates

| Framework | File | Description |
|-----------|------|-------------|
| **React + Vite** | `react-vite-example.env.local` | Environment variables for React with Vite |
| **Next.js** | `nextjs-example.env.local` | Environment variables for Next.js |
| **Angular** | `angular-example-environment.development.ts` | TypeScript environment config for Angular |
| **Vue 3** | `vue3-example.env.local` | Environment variables for Vue 3 with Vite |

## Quick Start

### 1. Choose Your Framework

Select the appropriate configuration file for your frontend framework.

### 2. Copy to Your Project

#### React / Vue 3:
```bash
# Copy the file to your project root
cp react-vite-example.env.local /path/to/your-project/.env.local

# Or for Vue 3
cp vue3-example.env.local /path/to/your-vue-project/.env.local
```

#### Next.js:
```bash
# Copy the file to your project root
cp nextjs-example.env.local /path/to/your-nextjs-project/.env.local
```

#### Angular:
```bash
# Copy the file to your Angular environments directory
cp angular-example-environment.development.ts /path/to/your-angular-project/src/environments/environment.development.ts
```

### 3. Start Development Proxy

```bash
# In the fineract-gitops directory
./scripts/dev-proxy.sh
```

### 4. Start Your Frontend

```bash
# In your frontend project directory
npm run dev
# or
npm start
# or
yarn dev
```

## Configuration Explained

All configuration files are pre-configured to work with the local development proxy at `http://localhost:8080`.

### Key Configuration Values

| Setting | Value | Description |
|---------|-------|-------------|
| **API Base URL** | `http://localhost:8080` | Apache Gateway proxy endpoint |
| **Fineract API** | `http://localhost:8080/fineract-provider/api/v1` | Fineract REST API |
| **Keycloak URL** | `http://localhost:8080/auth` | Keycloak authentication server |
| **Realm** | `fineract` | Keycloak realm name |
| **Client ID** | `apache-gateway` | Keycloak client identifier |
| **Tenant ID** | `default` | Fineract tenant identifier |

## Customization

### Change API Port

If you're using a different port for the development proxy:

```bash
# Start proxy on different port
./scripts/dev-proxy.sh fineract-dev 9080
```

Then update your configuration file:
```bash
# React/Vue/Next.js
VITE_API_BASE_URL=http://localhost:9080

# Angular
apiUrl: 'http://localhost:9080',
```

### Add Custom Environment Variables

#### React/Vue/Next.js:

Add to `.env.local`:
```bash
VITE_CUSTOM_FEATURE_ENABLED=true
VITE_CUSTOM_API_ENDPOINT=http://localhost:8080/custom-api
```

Access in code:
```javascript
const isEnabled = import.meta.env.VITE_CUSTOM_FEATURE_ENABLED;
const apiUrl = import.meta.env.VITE_CUSTOM_API_ENDPOINT;
```

#### Angular:

Add to `environment.development.ts`:
```typescript
export const environment = {
  // ... existing config
  customFeature: true,
  customApiEndpoint: 'http://localhost:8080/custom-api'
};
```

Access in code:
```typescript
import { environment } from '@environments/environment';

const isEnabled = environment.customFeature;
```

## Environment-Specific Configuration

### Development (Local)
Use the provided examples as-is. They're configured for local development with `http://localhost:8080`.

### Staging
Create `.env.staging` or `environment.staging.ts`:
```bash
VITE_API_BASE_URL=https://staging.yourbank.com
VITE_KEYCLOAK_URL=https://auth-staging.yourbank.com/auth
```

### Production
Create `.env.production` or `environment.ts`:
```bash
VITE_API_BASE_URL=https://apps.yourbank.com
VITE_KEYCLOAK_URL=https://auth.yourbank.com/auth
VITE_DEBUG=false
VITE_LOG_API_REQUESTS=false
```

## Framework-Specific Notes

### React + Vite

**Variable Prefix**: All variables must start with `VITE_`

**Access in Code**:
```javascript
import.meta.env.VITE_API_BASE_URL
```

**Build**:
```bash
npm run build  # Uses .env.production
```

---

### Next.js

**Variable Prefixes**:
- `NEXT_PUBLIC_` - Exposed to browser
- No prefix - Server-side only

**Access in Code**:
```javascript
// Client-side
process.env.NEXT_PUBLIC_API_URL

// Server-side
process.env.KEYCLOAK_CLIENT_SECRET
```

**Build**:
```bash
npm run build  # Uses .env.production
```

---

### Angular

**Configuration Files**:
- `environment.development.ts` - Development
- `environment.ts` - Production

**Access in Code**:
```typescript
import { environment } from '@environments/environment';

const apiUrl = environment.apiUrl;
```

**Build**:
```bash
ng build --configuration=development
ng build --configuration=production
```

---

### Vue 3

**Variable Prefix**: All variables must start with `VITE_` (Vue 3 uses Vite)

**Access in Code**:
```javascript
import.meta.env.VITE_API_BASE_URL
```

**Build**:
```bash
npm run build  # Uses .env.production
```

## Common Issues

### Variables Not Loading

**React/Vue/Next.js**:
- Ensure variables start with correct prefix (`VITE_` or `NEXT_PUBLIC_`)
- Restart dev server after changing `.env.local`
- Clear `.vite` or `.next` cache if needed

**Angular**:
- Ensure importing correct environment file
- Rebuild after changing environment files

### CORS Errors

**Solution**: Make sure you're using the Apache Gateway proxy (`http://localhost:8080`), not direct service URLs.

### Authentication Not Working

**Solution**:
1. Verify proxy is running: `lsof -i :8080`
2. Check Keycloak URL: `curl http://localhost:8080/auth`
3. Clear browser cookies/localStorage

## Additional Examples

### API Service Configuration (React/TypeScript)

```typescript
// src/config/api.ts
const API_BASE = import.meta.env.VITE_API_BASE_URL;
const TENANT_ID = import.meta.env.VITE_TENANT_ID;

export const apiConfig = {
  baseURL: `${API_BASE}/fineract-provider/api/v1`,
  headers: {
    'X-Fineract-Platform-TenantId': TENANT_ID,
    'Content-Type': 'application/json'
  }
};

// src/services/api.ts
import axios from 'axios';
import { apiConfig } from '@/config/api';

const api = axios.create(apiConfig);

// Add auth token interceptor
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export default api;
```

### Keycloak Integration (React)

```typescript
// src/config/keycloak.ts
import Keycloak from 'keycloak-js';

const keycloak = new Keycloak({
  url: import.meta.env.VITE_KEYCLOAK_URL,
  realm: import.meta.env.VITE_KEYCLOAK_REALM,
  clientId: import.meta.env.VITE_KEYCLOAK_CLIENT_ID
});

export default keycloak;

// src/main.tsx
import keycloak from './config/keycloak';

keycloak.init({
  onLoad: 'login-required',
  checkLoginIframe: false
}).then((authenticated) => {
  if (authenticated) {
    // Render app
  }
});
```

## Testing Configuration

### Verify Environment Variables

**React/Vue**:
```javascript
console.log('API URL:', import.meta.env.VITE_API_BASE_URL);
console.log('Keycloak URL:', import.meta.env.VITE_KEYCLOAK_URL);
```

**Next.js**:
```javascript
console.log('API URL:', process.env.NEXT_PUBLIC_API_URL);
```

**Angular**:
```typescript
console.log('Environment:', environment);
```

### Test API Connection

```javascript
// Quick test
fetch('http://localhost:8080/health')
  .then(res => res.text())
  .then(data => console.log('Gateway health:', data));

// Test Fineract API
fetch('http://localhost:8080/fineract-provider/api/v1/offices', {
  headers: {
    'X-Fineract-Platform-TenantId': 'default',
    'Authorization': 'Bearer YOUR_TOKEN'
  }
})
  .then(res => res.json())
  .then(data => console.log('Offices:', data));
```

## Resources

- [Local Frontend Development Guide](../../LOCAL_FRONTEND_DEVELOPMENT.md)
- [Apache Gateway Configuration](../../../apps/apache-gateway/base/configmap-routing.yaml)
- [Keycloak Realm Configuration](../../../operations/keycloak-config/config/realm-fineract.yaml)
- [Development Proxy Script](../../../scripts/dev-proxy.sh)

## Support

For issues or questions:
1. Check the [troubleshooting guide](../../LOCAL_FRONTEND_DEVELOPMENT.md#troubleshooting)
2. Verify proxy is running: `./scripts/dev-proxy.sh`
3. Test connection: `curl http://localhost:8080/health`
4. Check logs: `kubectl logs -n fineract-dev -l app=apache-gateway`

---

**Happy Coding!** 🚀
