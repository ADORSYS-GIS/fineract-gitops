<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('password','password-confirm'); section>
    <#if section = "header">
        ${msg("updatePasswordTitle")}
    <#elseif section = "form">
        <div id="kc-form">
            <div style="margin-bottom: 24px; padding: 16px; background: var(--webank-gray-50); border-left: 4px solid var(--webank-accent); border-radius: 8px;">
                <p style="margin: 0; color: var(--webank-gray-800); font-size: 14px;">
                    <strong>Welcome to Webank!</strong><br/>
                    For your security, please create a new password for your account.
                </p>
            </div>

            <form id="kc-passwd-update-form" class="${properties.kcFormClass!}" action="${url.loginAction}" method="post">
                <input type="text" id="username" name="username" value="${username}" autocomplete="username"
                       readonly="readonly" style="display:none;"/>
                <input type="password" id="password" name="password" autocomplete="current-password" style="display:none;"/>

                <div class="form-group">
                    <label for="password-new" class="${properties.kcLabelClass!}">
                        ${msg("passwordNew")}
                    </label>
                    <input type="password" id="password-new" name="password-new" class="${properties.kcInputClass!}"
                           autofocus autocomplete="new-password"
                           aria-invalid="<#if messagesPerField.existsError('password','password-confirm')>true</#if>"
                    />

                    <#if messagesPerField.existsError('password')>
                        <span id="input-error-password" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                            ${kcSanitize(messagesPerField.get('password'))?no_esc}
                        </span>
                    </#if>
                </div>

                <div class="form-group">
                    <label for="password-confirm" class="${properties.kcLabelClass!}">
                        ${msg("passwordConfirm")}
                    </label>
                    <input type="password" id="password-confirm" name="password-confirm"
                           class="${properties.kcInputClass!}"
                           autocomplete="new-password"
                           aria-invalid="<#if messagesPerField.existsError('password-confirm')>true</#if>"
                    />

                    <#if messagesPerField.existsError('password-confirm')>
                        <span id="input-error-password-confirm" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                            ${kcSanitize(messagesPerField.get('password-confirm'))?no_esc}
                        </span>
                    </#if>

                </div>

                <#-- Password Requirements -->
                <div style="margin: 24px 0; padding: 16px; background: var(--webank-gray-50); border-radius: 8px;">
                    <h4 style="margin-top: 0; color: var(--webank-primary); font-size: 14px;">Password Requirements:</h4>
                    <ul style="margin: 0; padding-left: 20px; font-size: 13px; color: var(--webank-gray-700); line-height: 1.8;">
                        <li>At least 12 characters long</li>
                        <li>At least 1 uppercase letter (A-Z)</li>
                        <li>At least 1 lowercase letter (a-z)</li>
                        <li>At least 2 digits (0-9)</li>
                        <li>At least 1 special character (!@#$%^&*)</li>
                        <li>Cannot be the same as your username</li>
                    </ul>
                </div>

                <div class="${properties.kcFormGroupClass!}">
                    <div id="kc-form-options" class="${properties.kcFormOptionsClass!}">
                        <div class="${properties.kcFormOptionsWrapperClass!}">
                            <#if isAppInitiatedAction??>
                                <div class="checkbox">
                                    <label><input type="checkbox" id="logout-sessions" name="logout-sessions" value="on" checked>
                                        ${msg("logoutOtherSessions")}
                                    </label>
                                </div>
                            </#if>
                        </div>
                    </div>

                    <div id="kc-form-buttons" class="${properties.kcFormButtonsClass!}">
                        <#if isAppInitiatedAction??>
                            <input class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonLargeClass!}" type="submit" value="${msg("doSubmit")}" />
                            <button class="${properties.kcButtonClass!} ${properties.kcButtonDefaultClass!} ${properties.kcButtonLargeClass!}" type="submit" name="cancel-aia" value="true" />${msg("doCancel")}</button>
                        <#else>
                            <input class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonBlockClass!} ${properties.kcButtonLargeClass!}" type="submit" value="${msg("doSubmit")}" />
                        </#if>
                    </div>
                </div>
            </form>
        </div>
    </#if>
</@layout.registrationLayout>
