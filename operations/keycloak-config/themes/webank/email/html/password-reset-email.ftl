<#ftl output_format="HTML">
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Password Reset - Webank</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
            line-height: 1.6;
            color: #212529;
            margin: 0;
            padding: 0;
            background-color: #f8f9fa;
        }
        .container {
            max-width: 600px;
            margin: 40px auto;
            background: #ffffff;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 4px 8px rgba(0,0,0,0.1);
        }
        .header {
            background: linear-gradient(135deg, #003366 0%, #0066cc 100%);
            padding: 32px 24px;
            text-align: center;
            color: #ffffff;
        }
        .logo {
            font-size: 28px;
            font-weight: 700;
            letter-spacing: -0.5px;
            margin-bottom: 8px;
        }
        .tagline {
            font-size: 14px;
            opacity: 0.9;
        }
        .content {
            padding: 40px 32px;
        }
        h1 {
            color: #003366;
            font-size: 24px;
            margin-top: 0;
            margin-bottom: 16px;
        }
        p {
            margin-bottom: 16px;
            color: #343a40;
        }
        .button {
            display: inline-block;
            padding: 14px 32px;
            background: #0066cc;
            color: #ffffff !important;
            text-decoration: none;
            border-radius: 8px;
            font-weight: 600;
            margin: 24px 0;
        }
        .button:hover {
            background: #0055aa;
        }
        .alert {
            padding: 16px;
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            border-radius: 4px;
            margin: 24px 0;
            font-size: 14px;
            color: #856404;
        }
        .footer {
            padding: 24px 32px;
            background: #f8f9fa;
            text-align: center;
            font-size: 13px;
            color: #6c757d;
            border-top: 1px solid #dee2e6;
        }
        .security-notice {
            margin-top: 32px;
            padding-top: 24px;
            border-top: 1px solid #e9ecef;
            font-size: 14px;
            color: #6c757d;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo">WEBANK</div>
            <div class="tagline">Secure Banking Platform</div>
        </div>
        <div class="content">
            <h1>Password Reset Request</h1>
            <p>Hello,</p>
            <p>We received a request to reset your Webank account password. If you made this request, click the button below to set a new password:</p>

            <a href="${link}" class="button">Reset Password</a>

            <div class="alert">
                <strong>⏱ This link will expire in ${linkExpirationFormatter(linkExpiration)}.</strong><br/>
                Please complete your password reset within this time frame.
            </div>

            <p>If the button doesn't work, copy and paste this link into your browser:</p>
            <p style="word-break: break-all; font-size: 13px; color: #0066cc;">${link}</p>

            <div class="security-notice">
                <p><strong>🔒 Security Notice:</strong></p>
                <p style="margin: 8px 0;">If you did not request a password reset, please ignore this email. Your password will remain unchanged.</p>
                <p style="margin: 8px 0;">Never share your password with anyone. Webank will never ask for your password via email or phone.</p>
            </div>
        </div>
        <div class="footer">
            <p style="margin: 0;">This is an automated message from Webank.</p>
            <p style="margin: 8px 0 0 0;">© ${.now?string('yyyy')} Webank. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
