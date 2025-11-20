// Fineract Frontend Configuration - Angular
// Copy this file to your Angular project: src/environments/environment.development.ts
//
// Angular uses TypeScript files for environment configuration, not .env files
// Documentation: https://angular.io/guide/build#configuring-application-environments

export const environment = {
  // =============================================================================
  // Environment Settings
  // =============================================================================
  production: false,
  development: true,
  environmentName: 'development',

  // =============================================================================
  // API Configuration
  // =============================================================================

  // Base URL for all API calls (Apache Gateway)
  apiUrl: 'http://localhost:8080',

  // Fineract API endpoint
  fineractApi: 'http://localhost:8080/fineract-provider/api/v1',

  // Fineract tenant ID
  tenantId: 'default',

  // =============================================================================
  // Keycloak Authentication Configuration
  // =============================================================================

  keycloak: {
    // Keycloak server URL (through Apache Gateway)
    url: 'http://localhost:8080/auth',

    // Keycloak realm name
    realm: 'fineract',

    // Keycloak client ID
    clientId: 'apache-gateway',

    // Optional: Client secret (only if using confidential client)
    // clientSecret: 'your-client-secret',

    // Optional: Keycloak init options
    initOptions: {
      onLoad: 'login-required',
      checkLoginIframe: false, // Disable for localhost
      pkceMethod: 'S256'
    }
  },

  // =============================================================================
  // Optional Service URLs
  // =============================================================================

  // Message Gateway (for SMS/Email notifications)
  messageGatewayUrl: 'http://localhost:8080/message-gateway',

  // Note: User sync service has been removed. User management is handled through Keycloak SSO.
  // userSyncUrl: 'http://localhost:8080/api/user-sync',

  // =============================================================================
  // Application Configuration
  // =============================================================================

  // Application name
  appName: 'Fineract Banking Platform',

  // Application version
  appVersion: '1.0.0',

  // Branding
  branding: {
    logo: '/assets/logo.png',
    primaryColor: '#1976d2',
    accentColor: '#ff4081'
  },

  // =============================================================================
  // Feature Flags
  // =============================================================================

  features: {
    smsNotifications: true,
    emailNotifications: true,
    reports: true,
    pentahoReports: true,
    advancedSearch: true,
    bulkOperations: true
  },

  // =============================================================================
  // API Configuration
  // =============================================================================

  api: {
    // Request timeout (milliseconds)
    timeout: 30000,

    // Retry configuration
    retry: {
      maxRetries: 3,
      retryDelay: 1000 // milliseconds
    },

    // Enable request/response logging
    logging: true,

    // Default headers
    defaultHeaders: {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    }
  },

  // =============================================================================
  // Localization
  // =============================================================================

  localization: {
    defaultLanguage: 'en',
    availableLanguages: ['en', 'fr', 'sw'],
    dateFormat: 'yyyy-MM-dd',
    timeFormat: 'HH:mm:ss',
    currencyCode: 'USD',
    currencySymbol: '$'
  },

  // =============================================================================
  // Security Configuration
  // =============================================================================

  security: {
    // Enable CSRF protection
    csrf: false, // Disabled for development

    // Session timeout (milliseconds)
    sessionTimeout: 1800000, // 30 minutes

    // Enable secure cookies
    secureCookies: false, // Disabled for development (no HTTPS)

    // Enable XSS protection
    xssProtection: true
  },

  // =============================================================================
  // Logging Configuration
  // =============================================================================

  logging: {
    // Log level: 'debug' | 'info' | 'warn' | 'error'
    level: 'debug',

    // Enable console logging
    console: true,

    // Enable remote logging (if configured)
    remote: false,

    // Remote logging endpoint
    remoteEndpoint: ''
  },

  // =============================================================================
  // Performance Configuration
  // =============================================================================

  performance: {
    // Enable lazy loading
    lazyLoading: true,

    // Enable caching
    caching: true,

    // Cache duration (milliseconds)
    cacheDuration: 300000, // 5 minutes

    // Enable compression
    compression: true
  }
};

/*
 * For production, create environment.ts with:
 *
 * export const environment = {
 *   production: true,
 *   development: false,
 *   apiUrl: 'https://apps.yourbank.com',
 *   keycloak: {
 *     url: 'https://auth.yourbank.com/auth',
 *     realm: 'fineract',
 *     clientId: 'fineract-web-app'
 *   },
 *   logging: {
 *     level: 'error',
 *     console: false,
 *     remote: true
 *   }
 * };
 */
