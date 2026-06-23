import json
import boto3
import botocore.exceptions
import os
import re
import time
import logging
from collections import defaultdict

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize globals
AWS_REGION = None
ses = None

CONTACT_EMAIL = os.environ['CONTACT_EMAIL']
ALLOWED_ORIGIN = os.environ['ALLOWED_ORIGIN']
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get('ALLOWED_ORIGINS', ALLOWED_ORIGIN).split(',')
    if origin.strip()
]

FIELD_LIMITS = {
    'firstName': 100,
    'lastName':  100,
    'email':     254,
    'subject':   200,
    'message':  2000,
}

def get_cors_headers(event) -> dict:
    headers = event.get('headers') or {}
    request_origin = headers.get('origin') or headers.get('Origin')
    allow_origin = request_origin if request_origin in ALLOWED_ORIGINS else ALLOWED_ORIGINS[0]

    return {
        'Access-Control-Allow-Origin': allow_origin,
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'POST,OPTIONS',
        'Vary': 'Origin',
    }

# ─── In-memory rate limiter ───────────────────────────────────────────────────
# Allows MAX_REQUESTS per IP within WINDOW_SECONDS.
# Stored in the Lambda execution context — persists across warm invocations.
MAX_REQUESTS   = 3
WINDOW_SECONDS = 60

_rate_store: dict = defaultdict(list)

def is_rate_limited(ip: str) -> bool:
    now      = time.time()
    window   = now - WINDOW_SECONDS
    timestamps = [t for t in _rate_store[ip] if t > window]
    _rate_store[ip] = timestamps
    if len(timestamps) >= MAX_REQUESTS:
        return True
    _rate_store[ip].append(now)
    return False

# ─────────────────────────────────────────────────────────────────────────────

def is_valid_email(email: str) -> bool:
    return bool(re.match(r'^[^@\s]+@[^@\s]+\.[^@\s]+$', email))

def handler(event, context):
    cors_headers = get_cors_headers(event)

    # Initialize region and SES client on first invocation
    global AWS_REGION, ses
    if AWS_REGION is None:
        # Extract AWS region from Lambda context ARN
        # ARN format: arn:aws:lambda:us-east-1:ACCOUNT:function:FUNCTION_NAME
        arn_parts = context.invoked_function_arn.split(':')
        AWS_REGION = arn_parts[3]
        ses = boto3.client('ses', region_name=AWS_REGION)
    
    # Handle CORS preflight
    if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 200, 'headers': cors_headers, 'body': ''}

    # Extract source IP and apply rate limit check
    source_ip = (
        event.get('requestContext', {}).get('http', {}).get('sourceIp') or
        event.get('requestContext', {}).get('identity', {}).get('sourceIp') or
        'unknown'
    )
    if is_rate_limited(source_ip):
        return {
            'statusCode': 429,
            'headers': cors_headers,
            'body': json.dumps({'error': 'Too many requests. Please try again later.'}),
        }

    try:
        body = json.loads(event.get('body') or '{}')
    except json.JSONDecodeError:
        return {'statusCode': 400, 'headers': cors_headers, 'body': json.dumps({'error': 'Invalid request body'})}

    first_name = (body.get('firstName') or '').strip()[:FIELD_LIMITS['firstName']]
    last_name  = (body.get('lastName') or '').strip()[:FIELD_LIMITS['lastName']]
    email      = (body.get('email') or '').strip()[:FIELD_LIMITS['email']]
    subject    = re.sub(r'[\r\n]', '', (body.get('subject') or 'Website Contact Form').strip())[:FIELD_LIMITS['subject']]
    message    = (body.get('message') or '').strip()[:FIELD_LIMITS['message']]
    source_app = (body.get('sourceApp') or 'website-contact-form').strip()[:120]

    headers = event.get('headers') or {}
    origin = headers.get('origin') or headers.get('Origin') or 'unknown'

    if not all([first_name, last_name, email, message]):
        return {'statusCode': 400, 'headers': cors_headers, 'body': json.dumps({'error': 'Missing required fields'})}

    if not is_valid_email(email):
        return {'statusCode': 400, 'headers': cors_headers, 'body': json.dumps({'error': 'Invalid email address'})}

    email_body = f"""
New contact form submission

Source app: {source_app}
Origin:     {origin}

Name:    {first_name} {last_name}
Email:   {email}
Subject: {subject}

Message:
{message}

---
This message was sent via the Yusmoj Solutions website contact form.
"""

    confirmation_email_body = f"""
Dear {first_name} {last_name},

Thank you for reaching out to Yusmoj Solutions! We have received your message and will get back to you as soon as possible.

Your message details:
Subject: {subject}

---
This is an automated confirmation email. Please do not reply to this email.
If you have any urgent matters, please contact us directly at info@yusmojsolutions.com

Best regards,
Yusmoj Solutions Team
"""

    # ── Send notification to admin (mandatory) ───────────────────────────────
    try:
        ses.send_email(
            Source=CONTACT_EMAIL,
            Destination={'ToAddresses': [CONTACT_EMAIL]},
            ReplyToAddresses=[email],
            Message={
                'Subject': {'Data': f'[Yusmoj Solutions] {subject}'},
                'Body':    {'Text': {'Data': email_body}},
            },
        )
        logger.info('Admin notification sent successfully to %s', CONTACT_EMAIL)
    except botocore.exceptions.ClientError as exc:
        error_code = exc.response['Error']['Code']
        error_msg  = exc.response['Error']['Message']
        logger.error('SES admin notification failed — %s: %s', error_code, error_msg)
        return {
            'statusCode': 500,
            'headers': cors_headers,
            'body': json.dumps({'error': 'Failed to send email. Please try again or email us directly at info@yusmojsolutions.com'}),
        }

    # ── Send confirmation to submitter (best-effort; never blocks success) ───
    try:
        ses.send_email(
            Source=CONTACT_EMAIL,
            Destination={'ToAddresses': [email]},
            Message={
                'Subject': {'Data': 'We received your message - Yusmoj Solutions'},
                'Body':    {'Text': {'Data': confirmation_email_body}},
            },
        )
        logger.info('Confirmation email sent to %s', email)
    except botocore.exceptions.ClientError as exc:
        # Log but do NOT fail the request — the admin was already notified.
        # Common in SES sandbox mode where the submitter's address is unverified.
        error_code = exc.response['Error']['Code']
        error_msg  = exc.response['Error']['Message']
        logger.warning(
            'Confirmation email to %s failed (non-fatal) — %s: %s',
            email, error_code, error_msg,
        )

    return {
        'statusCode': 200,
        'headers': cors_headers,
        'body': json.dumps({'message': 'Message sent successfully'}),
    }
