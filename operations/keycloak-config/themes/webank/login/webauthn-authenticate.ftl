<#import "template.ftl" as layout>
<@layout.registrationLayout displayInfo=false; section>
    <#if section = "header">
        ${msg("webauthn-login-title")}
    <#elseif section = "form">
        <div class="webauthn-container">
            <div class="webauthn-header">
                <h2 style="color: var(--webank-primary); margin-bottom: 8px;">
                    Sign in with your device
                </h2>
                <p style="color: var(--webank-gray-600); margin-bottom: 24px;">
                    Use your registered device for secure, passwordless authentication.
                </p>
            </div>

            <div id="kc-form-webauthn" class="${properties.kcFormClass!}">
                <form id="webauth" action="${url.loginAction}" method="post">
                    <input type="hidden" id="clientDataJSON" name="clientDataJSON"/>
                    <input type="hidden" id="authenticatorData" name="authenticatorData"/>
                    <input type="hidden" id="signature" name="signature"/>
                    <input type="hidden" id="credentialId" name="credentialId"/>
                    <input type="hidden" id="userHandle" name="userHandle"/>
                    <input type="hidden" id="error" name="error"/>
                </form>

                <div class="${properties.kcFormGroupClass!} no-bottom-margin">
                    <#if authenticators??>
                        <form id="authn_select" class="${properties.kcFormClass!}">
                            <#list authenticators.authenticators as authenticator>
                                <input type="hidden" name="authn_use_chk" value="${authenticator.credentialId}"/>
                            </#list>
                        </form>

                        <#if shouldDisplayAuthenticators?? && shouldDisplayAuthenticators>
                            <#if authenticators.authenticators?size gt 1>
                                <p class="${properties.kcSelectAuthListItemTitle!}" style="color: var(--webank-gray-700); font-weight: 600; margin-bottom: 16px;">
                                    ${msg("webauthn-available-authenticators")}
                                </p>
                            </#if>

                            <div class="webauthn-authenticators-list">
                                <#list authenticators.authenticators as authenticator>
                                    <div id="kc-webauthn-authenticator-item-${authenticator?index}" class="webauthn-authenticator-item">
                                        <div class="webauthn-authenticator-icon">
                                            <i class="${(properties['${authenticator.transports.iconClass}'])!'fa fa-shield-halved'} ${properties.kcSelectAuthListItemIconPropertyClass!}"></i>
                                        </div>
                                        <div class="webauthn-authenticator-details">
                                            <div id="kc-webauthn-authenticator-label-${authenticator?index}"
                                                 class="webauthn-authenticator-label">
                                                ${authenticator.label}
                                            </div>

                                            <#if authenticator.transports?? && authenticator.transports.displayNameProperties?has_content>
                                                <div id="kc-webauthn-authenticator-transport-${authenticator?index}"
                                                     class="webauthn-authenticator-transport">
                                                    <#list authenticator.transports.displayNameProperties as nameProperty>
                                                        <span>${msg(nameProperty)}</span>
                                                        <#if nameProperty?has_next>
                                                            <span>, </span>
                                                        </#if>
                                                    </#list>
                                                </div>
                                            </#if>

                                            <div class="webauthn-authenticator-created">
                                                <span id="kc-webauthn-authenticator-createdlabel-${authenticator?index}">
                                                    ${msg('webauthn-createdAt-label')}
                                                </span>
                                                <span id="kc-webauthn-authenticator-created-${authenticator?index}">
                                                    ${authenticator.createdAt}
                                                </span>
                                            </div>
                                        </div>
                                        <div class="webauthn-authenticator-fill"></div>
                                    </div>
                                </#list>
                            </div>
                        </#if>
                    </#if>

                    <div id="kc-form-buttons" class="${properties.kcFormButtonsClass!}" style="margin-top: 24px;">
                        <input id="authenticateWebAuthnButton" type="button" autofocus="autofocus"
                               value="${msg("webauthn-doAuthenticate")}"
                               class="btn btn-primary btn-block btn-large"/>
                    </div>
                </div>

                <#if isSetRetry?has_content>
                    <div class="alert alert-error" style="margin-top: 24px;">
                        ${kcSanitize(msg("webauthnLoginError"))?no_esc}
                    </div>
                </#if>

                <div class="lost-device-link" style="margin-top: 32px; padding-top: 24px; border-top: 1px solid var(--webank-gray-200); text-align: center;">
                    <a tabindex="6" href="${url.loginResetCredentialsUrl}" style="color: var(--webank-primary); text-decoration: none; font-size: 14px;">
                        ${msg("doLostDevice")}
                    </a>
                </div>
            </div>
        </div>

        <script type="module">
            <#outputformat "JavaScript">
            import { authenticateByWebAuthn } from "${url.resourcesPath}/js/webauthnAuthenticate.js";
            const authButton = document.getElementById('authenticateWebAuthnButton');
            authButton.addEventListener("click", function() {
                const input = {
                        isUserIdentified : ${isUserIdentified},
                        challenge : ${challenge?c},
                        userVerification : ${userVerification?c},
                        rpId : ${rpId?c},
                        createTimeout : ${createTimeout?c},
                        errmsg : ${msg("webauthn-unsupported-browser-text")?c}
                    };
                authenticateByWebAuthn(input);
            }, { once: true });
            </#outputformat>
        </script>
    </#if>
</@layout.registrationLayout>
