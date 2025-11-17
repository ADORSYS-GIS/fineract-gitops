<#import "template.ftl" as layout>
<@layout.registrationLayout; section>
    <#if section = "header">
        ${msg("webauthnRegisterTitle")}
    <#elseif section = "form">

    <div class="webauthn-container">
        <h2 style="color: var(--webank-primary); margin-bottom: 16px;">
            Secure Your Account
        </h2>
        <p style="color: var(--webank-gray-600); margin-bottom: 32px;">
            Register your device for secure, passwordless authentication. Choose one of the options below:
        </p>

        <form id="register" class="${properties.kcFormClass!}" action="${url.loginAction}" method="post">
            <input type="hidden" id="clientDataJSON" name="clientDataJSON"/>
            <input type="hidden" id="attestationObject" name="attestationObject"/>
            <input type="hidden" id="publicKeyCredentialId" name="publicKeyCredentialId"/>
            <input type="hidden" id="authenticatorLabel" name="authenticatorLabel"/>
            <input type="hidden" id="transports" name="transports"/>
            <input type="hidden" id="error" name="error"/>

            <div class="webauthn-options">
                <div class="webauthn-option" onclick="registerWebAuthn('platform')">
                    <svg width="64" height="64" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" fill="var(--webank-accent)"/>
                    </svg>
                    <h3>Face ID / Touch ID</h3>
                    <p>Use your device's built-in biometric authentication for quick and secure login</p>
                </div>

                <div class="webauthn-option" onclick="registerWebAuthn('cross-platform')">
                    <svg width="64" height="64" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                        <rect x="4" y="8" width="16" height="10" rx="2" stroke="var(--webank-accent)" stroke-width="2"/>
                        <circle cx="12" cy="13" r="2" fill="var(--webank-accent)"/>
                    </svg>
                    <h3>Security Key</h3>
                    <p>Use a physical security key (like YubiKey) for maximum security</p>
                </div>
            </div>

            <#if isSetRetry?has_content>
                <div class="alert alert-error" style="margin-top: 24px;">
                    ${kcSanitize(msg("webauthnRegisterError"))?no_esc}
                </div>
            </#if>

            <div style="margin-top: 32px;">
                <button type="button" id="registerWebAuthnButton" class="btn btn-primary" onclick="registerWebAuthn('both')" style="margin-bottom: 12px;">
                    ${msg("webauthnRegister")}
                </button>

                <#if !isSetRetry?has_content>
                    <div style="text-align: center; margin-top: 16px; font-size: 14px; color: var(--webank-gray-600);">
                        You can also <a href="${url.loginRestartFlowUrl}">set this up later</a> in your account settings
                    </div>
                </#if>
            </div>
        </form>

        <div id="kc-info" style="margin-top: 32px; padding-top: 24px; border-top: 1px solid var(--webank-gray-200); text-align: center; font-size: 14px; color: var(--webank-gray-600);">
            <p>
                <strong>Why register a device?</strong><br/>
                Device registration adds an extra layer of security to your account. After registration, you'll be able to login quickly using biometric authentication or a security key.
            </p>
        </div>
    </div>

    <script type="text/javascript">
        function registerWebAuthn(authenticatorAttachment) {
            const challengeData = '${challenge}';
            const userId = '${userid}';
            const username = '${username}';
            const signatureAlgorithms = JSON.parse('${signatureAlgorithms}');
            const rpEntityName = '${rpEntityName}';
            const rpId = '${rpId}';
            const attestationConveyancePreference = '${attestationConveyancePreference}';
            const requireResidentKey = '${requireResidentKey}' === 'Yes';
            const userVerificationRequirement = '${userVerificationRequirement}';
            const createTimeout = parseInt('${createTimeout}');
            const excludeCredentialIds = JSON.parse('${excludeCredentialIds}');

            // Prepare public key credential creation options
            const publicKey = {
                challenge: base64urlToUint8array(challengeData),
                rp: {
                    name: rpEntityName,
                    id: rpId
                },
                user: {
                    id: base64urlToUint8array(userId),
                    name: username,
                    displayName: username
                },
                pubKeyCredParams: signatureAlgorithms.map(alg => ({ type: "public-key", alg: alg })),
                timeout: createTimeout * 1000,
                excludeCredentials: excludeCredentialIds.map(id => ({
                    type: "public-key",
                    id: base64urlToUint8array(id)
                })),
                authenticatorSelection: {
                    requireResidentKey: requireResidentKey,
                    userVerification: userVerificationRequirement
                },
                attestation: attestationConveyancePreference
            };

            // Set authenticator attachment if specified
            if (authenticatorAttachment !== 'both') {
                publicKey.authenticatorSelection.authenticatorAttachment = authenticatorAttachment;
            }

            // Register credential
            navigator.credentials.create({ publicKey: publicKey })
                .then(credential => {
                    const clientDataJSON = arrayToBase64String(credential.response.clientDataJSON);
                    const attestationObject = arrayToBase64String(credential.response.attestationObject);
                    const publicKeyCredentialId = arrayToBase64String(credential.rawId);

                    document.getElementById('clientDataJSON').value = clientDataJSON;
                    document.getElementById('attestationObject').value = attestationObject;
                    document.getElementById('publicKeyCredentialId').value = publicKeyCredentialId;
                    document.getElementById('authenticatorLabel').value = username + "'s " + (authenticatorAttachment === 'platform' ? 'Device' : 'Security Key');

                    if (credential.response.getTransports) {
                        const transports = credential.response.getTransports();
                        document.getElementById('transports').value = transports.join(',');
                    }

                    document.getElementById('register').submit();
                })
                .catch(error => {
                    document.getElementById('error').value = error;
                    document.getElementById('register').submit();
                });
        }

        function base64urlToUint8array(base64Bytes) {
            const padding = '===='.substring(0, (4 - (base64Bytes.length % 4)) % 4);
            const base64 = (base64Bytes + padding).replace(/\-/g, '+').replace(/_/g, '/');
            const rawData = atob(base64);
            const buffer = new Uint8Array(rawData.length);
            for (let i = 0; i < rawData.length; ++i) {
                buffer[i] = rawData.charCodeAt(i);
            }
            return buffer;
        }

        function arrayToBase64String(array) {
            return btoa(String.fromCharCode.apply(null, new Uint8Array(array)));
        }
    </script>

    </#if>
</@layout.registrationLayout>
