# Webank User Onboarding Guide

## Welcome to Webank Secure Banking Platform

This guide will help you complete your first login and set up secure authentication for your Webank account.

## What You'll Need

- Your username and temporary password (provided by your administrator)
- A device with Face ID, Touch ID, or a Security Key (YubiKey)
- Your email address (for verification)
- 5-10 minutes of time

## Step-by-Step Guide

### Step 1: First Login

1. Open your web browser and navigate to: **https://auth.webank.com**
2. You'll see the Webank login page

3. Enter your **username** (e.g., john.doe)
4. Enter your **temporary password** (provided by your admin)
5. Click **Sign In**

**Screenshot**: Login page with Webank branding

### Step 2: Create Your New Password

After your first login, you'll be prompted to create a new password.

**Password Requirements**:
- ✅ At least **12 characters** long
- ✅ At least **1 uppercase letter** (A-Z)
- ✅ At least **1 lowercase letter** (a-z)
- ✅ At least **2 digits** (0-9)
- ✅ At least **1 special character** (!@#$%^&*)
- ✅ Cannot be the same as your username
- ✅ Cannot be one of your last 5 passwords

**Example of a strong password**: `MyBank2024!Secure`

**Tips**:
- Use a passphrase: "ILove2BankAt Webank!"
- Use a password manager (recommended)
- Don't reuse passwords from other sites

1. Enter your **new password**
2. **Confirm** your new password
3. Click **Continue**

### Step 3: Register Your Device

This is the most important step! Registering your device adds an extra layer of security and makes future logins faster and easier.

You'll see two options:

#### Option A: Face ID / Touch ID (Recommended)

**For iPhone, iPad, MacBook users**

1. Click **"Face ID / Touch ID"**
2. Your device will prompt: "Use Face ID to sign in to Webank"
3. Look at your device (Face ID) or place your finger on the sensor (Touch ID)
4. Device registered! ✅

**Benefits**:
- No need to enter password on future logins (after username)
- Biometric authentication is more secure
- Faster login experience

#### Option B: Security Key (YubiKey)

**For users with hardware security keys**

1. Click **"Security Key"**
2. Insert your YubiKey into USB port (or tap for NFC)
3. Browser will prompt: "Touch your security key"
4. Touch the gold button on your YubiKey
5. Device registered! ✅

**Benefits**:
- Highest level of security
- Can use same key on multiple devices
- Works on any computer

### Step 4: Complete Setup

After registering your device, you'll see a success message and be redirected to your application (Client Portal, Staff Dashboard, or Admin Console).

**You're all set!** 🎉

## Future Logins

### Quick Login with Face ID / Touch ID

1. Open **https://auth.webank.com**
2. Enter your **username**
3. Enter your **password**
4. Your device automatically prompts for Face ID / Touch ID
5. Authenticate → **You're in!**

### Login with Security Key

1. Open **https://auth.webank.com**
2. Enter your **username**
3. Enter your **password**
4. Insert and touch your **YubiKey**
5. **You're in!**

## Managing Your Devices

### View Registered Devices

1. After logging in, go to **Account Settings**
2. Click **Security** → **Registered Devices**
3. You'll see a list of all your registered devices:
   - Device name (e.g., "iPhone 13 - Face ID")
   - Registration date
   - Last used date

### Add Another Device

You can register multiple devices (e.g., work laptop + personal phone):

1. Go to **Account Settings** → **Security**
2. Click **"Add Device"**
3. Follow the registration steps
4. New device added!

**Recommended**: Register at least 2 devices (primary + backup)

### Remove a Device

If you lose a device or no longer use it:

1. Go to **Account Settings** → **Security** → **Registered Devices**
2. Find the device you want to remove
3. Click **"Remove"**
4. Confirm removal
5. Device removed! ✅

**Important**: If you remove all devices, you'll need to register a new one on your next login.

## Backup Authentication Method

### Set Up TOTP (Time-based One-Time Password)

If you don't have Face ID / Touch ID, you can use an authenticator app:

**Supported Apps**:
- Google Authenticator
- Microsoft Authenticator
- Authy
- 1Password

**Setup**:
1. Go to **Account Settings** → **Security**
2. Click **"Set up Authenticator App"**
3. Scan QR code with your authenticator app
4. Enter the 6-digit code from your app
5. TOTP enabled! ✅

**Future logins**:
1. Enter username + password
2. Enter 6-digit code from authenticator app
3. You're in!

## Troubleshooting

### "Failed to register device"

**Possible causes**:
- Browser doesn't support WebAuthn (use Chrome, Firefox, Safari, Edge)
- Device doesn't have biometric sensor
- Permission denied (allow Webank to access biometrics)

**Solution**:
- Try different browser
- Use Security Key instead
- Contact IT support

### "Your account has been locked"

**Cause**: Too many failed login attempts (3 attempts)

**Solution**:
- Wait 2 minutes and try again
- If you forgot your password, click **"Forgot Password?"**
- Contact your administrator if issue persists

### "Temporary password not working"

**Solution**:
- Check for typos (passwords are case-sensitive)
- Copy-paste password from email (avoid typing errors)
- Contact administrator for password reset

### Lost my only registered device

**Solution**:
- Use backup authenticator app (if configured)
- Contact your administrator to reset your account
- Administrator will provide new temporary password
- Register new device on next login

### Can't receive verification email

**Check**:
- Spam/junk folder
- Correct email address in your profile
- Email not blocked by company firewall

**Solution**: Contact IT support

## Security Best Practices

### DO ✅

- **Use strong, unique password** for Webank
- **Register Face ID / Touch ID** for convenience and security
- **Add backup device** or authenticator app
- **Log out** when done (especially on shared computers)
- **Report suspicious activity** to security@webank.com
- **Keep devices updated** with latest OS patches
- **Enable device lock** (PIN, password, biometric)

### DON'T ❌

- **Share your password** with anyone (even IT support)
- **Write down password** on sticky notes
- **Use same password** as other websites
- **Save password in browser** on shared computers
- **Access Webank from public computers** (internet cafes, libraries)
- **Click links in suspicious emails** claiming to be from Webank

## Need Help?

### IT Support

- **Email**: support@webank.com
- **Phone**: +254-XXX-XXXXXX
- **Hours**: Monday-Friday, 8am-6pm EAT

### Self-Service

- **Password Reset**: Click "Forgot Password?" on login page
- **Account Settings**: Manage your profile, devices, and security
- **FAQ**: https://docs.webank.com/faq

### Security Concerns

If you suspect your account has been compromised:

1. **Immediately** change your password
2. **Remove** all registered devices
3. **Contact** security@webank.com
4. **Report** incident to your supervisor

---

**Welcome to secure banking with Webank!** 🏦🔒

If you have any questions during the onboarding process, don't hesitate to contact IT support. We're here to help!
