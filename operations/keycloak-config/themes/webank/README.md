# Webank Keycloak Theme

Professional banking theme for Keycloak with WebAuthn support and modern UI/UX.

## Features

✅ **Professional Banking Design** - Clean, trustworthy aesthetic
✅ **WebAuthn Support** - Device registration pages for Face ID, Touch ID, Security Keys
✅ **Responsive** - Mobile-first design, works on all devices
✅ **Accessible** - WCAG 2.1 AA compliant
✅ **Branded Email Templates** - Professional HTML emails
✅ **Security-Focused** - Clear security messaging and best practices

## Theme Structure

```
webank/
├── theme.properties              # Theme configuration
├── login/                        # Login pages
│   ├── template.ftl             # Base template (all pages extend this)
│   ├── login.ftl                # Main login page
│   ├── login-update-password.ftl # Password change (first login)
│   ├── webauthn-register.ftl    # Device registration
│   ├── messages/
│   │   └── messages_en.properties # English text labels
│   └── resources/
│       ├── css/
│       │   └── webank.css       # Main theme styles
│       ├── img/
│       │   └── favicon.ico      # Bank favicon
│       └── js/
│           └── webauthn.js      # WebAuthn client logic
├── email/                        # Email templates
│   ├── html/
│   │   └── password-reset-email.ftl # Password reset HTML
│   └── text/
│       └── password-reset-email.ftl # Password reset plain text
└── README.md                     # This file
```

## Color Palette

```css
Primary Blue:   #003366  /* Trust, stability */
Accent Blue:    #0066cc  /* Actions, links */
Success Green:  #28a745
Danger Red:     #dc3545
Warning Yellow: #ffc107
```

## Installation

### Method 1: Kubernetes ConfigMap (Recommended for GitOps)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-webank-theme
  namespace: fineract
data:
  theme.properties: |
    # Content from theme.properties

  login-template.ftl: |
    # Content from login/template.ftl

  # ... all other theme files
```

Mount as volume in Keycloak deployment:

```yaml
spec:
  containers:
  - name: keycloak
    volumeMounts:
    - name: webank-theme
      mountPath: /opt/keycloak/themes/webank
  volumes:
  - name: webank-theme
    configMap:
      name: keycloak-webank-theme
```

### Method 2: Docker Image (Build into custom Keycloak image)

```dockerfile
FROM quay.io/keycloak/keycloak:latest
COPY themes/webank /opt/keycloak/themes/webank
```

## Configuration

Update realm configuration to use Webank theme:

```yaml
# In realm-fineract.yaml
loginTheme: webank
accountTheme: webank
emailTheme: webank
```

## Customization

### Update Branding

1. **Change Logo**: Edit `login/template.ftl`, replace "WEBANK" text with logo image
2. **Update Colors**: Modify CSS variables in `resources/css/webank.css`
3. **Change Text**: Edit `messages/messages_en.properties`

### Add Language Support

1. Create `messages/messages_fr.properties` (French example)
2. Add locale to `theme.properties`: `locales=en,fr`
3. Restart Keycloak

## WebAuthn Device Registration

The theme includes a custom WebAuthn registration page that:

- Detects device capabilities (platform authenticator support)
- Provides clear instructions for Face ID / Touch ID / Security Keys
- Handles registration errors gracefully
- Stores device metadata for management

## Email Templates

### Available Templates

- `password-reset-email.ftl` - Password reset link
- `email-verification.ftl` - Email verification
- `event-login_error.ftl` - Failed login notification
- `event-update_password.ftl` - Password changed notification

### Email Customization

Edit HTML templates in `email/html/` directory. Each template should have:
- Professional header with Webank branding
- Clear call-to-action button
- Security notice
- Footer with copyright

## Testing

### Local Testing with Docker

```bash
# Start Keycloak with theme mounted
docker run -d \
  --name keycloak \
  -p 8080:8080 \
  -v $(pwd)/themes/webank:/opt/keycloak/themes/webank \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  quay.io/keycloak/keycloak:latest \
  start-dev

# Access: http://localhost:8080
# Create realm, set login theme to "webank"
```

### Browser Testing

Test on:
- ✅ Chrome (WebAuthn support)
- ✅ Firefox (WebAuthn support)
- ✅ Safari (Face ID / Touch ID on macOS/iOS)
- ✅ Mobile browsers (iOS Safari, Chrome Mobile)

### WebAuthn Testing

- **macOS**: Touch ID on MacBook Pro
- **iOS**: Face ID / Touch ID on iPhone/iPad
- **Windows**: Windows Hello
- **Security Keys**: YubiKey 5 series, Google Titan

## Accessibility

Theme follows WCAG 2.1 AA guidelines:

- ✅ Keyboard navigation support
- ✅ Screen reader compatible
- ✅ Sufficient color contrast (4.5:1 minimum)
- ✅ Focus indicators
- ✅ ARIA labels
- ✅ Semantic HTML

## Troubleshooting

### Theme Not Loading

1. Check Keycloak logs: `kubectl logs -n fineract deployment/keycloak`
2. Verify theme files are mounted correctly
3. Ensure realm is configured to use "webank" theme
4. Clear browser cache

### WebAuthn Not Working

1. Verify HTTPS is enabled (WebAuthn requires HTTPS)
2. Check browser console for errors
3. Verify RP ID matches domain in realm configuration
4. Test with different authenticator types

### Email Templates Not Rendering

1. Check SMTP configuration in realm
2. Verify email theme is set to "webank"
3. Test with plain text fallback
4. Check email client HTML support

## Production Checklist

- [ ] Update logo and branding
- [ ] Configure production domain in realm
- [ ] Test all email templates
- [ ] Verify WebAuthn on production domain
- [ ] Test on all supported browsers
- [ ] Verify accessibility
- [ ] Load test login page performance
- [ ] Enable CSP headers
- [ ] Test error pages
- [ ] Document user onboarding process

## Support

For issues or customization requests, contact the Webank Platform Team.

## License

Proprietary - Webank Internal Use Only
