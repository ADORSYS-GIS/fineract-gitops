<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <meta name="robots" content="noindex, nofollow">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">

    <#if properties.meta?has_content>
        <#list properties.meta?split(' ') as meta>
            <meta name="${meta?split('==')[0]}" content="${meta?split('==')[1]}"/>
        </#list>
    </#if>

    <title>${msg("loginTitle",(realm.displayName!''))}</title>

    <link rel="icon" type="image/x-icon" href="${url.resourcesPath}/img/favicon.ico">

    <#if properties.stylesCommon?has_content>
        <#list properties.stylesCommon?split(' ') as style>
            <link href="${url.resourcesCommonPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.styles?has_content>
        <#list properties.styles?split(' ') as style>
            <link href="${url.resourcesPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.scripts?has_content>
        <#list properties.scripts?split(' ') as script>
            <script src="${url.resourcesPath}/${script}" type="text/javascript"></script>
        </#list>
    </#if>
    <#if scripts??>
        <#list scripts as script>
            <script src="${script}" type="text/javascript"></script>
        </#list>
    </#if>

    <style>
        /* Additional inline styles for immediate rendering */
        body {
            margin: 0;
            padding: 0;
        }
    </style>
</head>

<body class="${properties.kcBodyClass!}">
<div id="kc-container" class="${properties.kcContainerClass!}">
    <div id="kc-container-wrapper" class="${properties.kcContainerWrapperClass!}">

        <#-- Header / Logo Section -->
        <div id="kc-header" class="${properties.kcHeaderClass!}">
            <div id="kc-header-wrapper"
                 class="${properties.kcHeaderWrapperClass!}">
                <div class="kc-logo-text">
                    WEBANK
                </div>
                <div class="platform-subtitle">
                    Secure Banking Platform
                </div>
            </div>
        </div>

        <#-- Main Content -->
        <div id="kc-content">
            <div id="kc-content-wrapper">

                <#-- Display Messages (Errors, Warnings, Info) -->
                <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
                    <div class="alert alert-${message.type}">
                        <#if message.type = 'success'><span class="kc-feedback-text">${kcSanitize(message.summary)?no_esc}</span></#if>
                        <#if message.type = 'warning'><span class="kc-feedback-text">${kcSanitize(message.summary)?no_esc}</span></#if>
                        <#if message.type = 'error'><span class="kc-feedback-text">${kcSanitize(message.summary)?no_esc}</span></#if>
                        <#if message.type = 'info'><span class="kc-feedback-text">${kcSanitize(message.summary)?no_esc}</span></#if>
                    </div>
                </#if>

                <#-- Page Header (from child templates) -->
                <#nested "header">

                <#-- Main Form Content (from child templates) -->
                <#nested "form">

                <#-- Social Providers (from child templates) -->
                <#nested "socialProviders">

                <#-- Info Section (from child templates) -->
                <#if displayInfo>
                    <#nested "info">
                </#if>

            </div>
        </div>

        <#-- Footer / Security Badge -->
        <div id="kc-info" class="${properties.kcSignUpClass!}">
            <div id="kc-info-wrapper" class="${properties.kcInfoAreaWrapperClass!}">
                <div class="security-badge">
                    Protected by bank-level security
                </div>
                <div class="footer-copyright">
                    © ${.now?string('yyyy')} Webank. All rights reserved.
                </div>
            </div>
        </div>

    </div>
</div>
</body>
</html>
</#macro>
