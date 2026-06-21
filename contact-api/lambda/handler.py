import json
import boto3
import os
import re
import time
from collections import defaultdict

# Initialize globals
AWS_REGION = None
ses = None

CONTACT_EMAIL = os.environ['CONTACT_EMAIL']
ALLOWED_ORIGIN = os.environ['ALLOWED_ORIGIN']

FIELD_LIMITS = {
    'firstName': 100,
    'lastName':  100,
    'email':     254,
    'subject':   200,
    'message':  2000,
}

CORS_HEADERS = {
    'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST,OPTIONS',
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
        return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': ''}

    # Extract source IP and apply rate limit check
    source_ip = (
        event.get('requestContext', {}).get('http', {}).get('sourceIp') or
        event.get('requestContext', {}).get('identity', {}).get('sourceIp') or
        'unknown'
    )
    if is_rate_limited(source_ip):
        return {
            'statusCode': 429,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Too many requests. Please try again later.'}),
        }

    try:
        body = json.loads(event.get('body') or '{}')
    except json.JSONDecodeError:
        return {'statusCode': 400, 'headers': CORS_HEADERS, 'body': json.dumps({'error': 'Invalid request body'})}

    first_name = (body.get('firstName') or '').strip()[:FIELD_LIMITS['firstName']]
    last_name  = (body.get('lastName') or '').strip()[:FIELD_LIMITS['lastName']]
    email      = (body.get('email') or '').strip()[:FIELD_LIMITS['email']]
    subject    = re.sub(r'[\r\n]', '', (body.get('subject') or 'Website Contact Form').strip())[:FIELD_LIMITS['subject']]
    message    = (body.get('message') or '').strip()[:FIELD_LIMITS['message']]

    if not all([first_name, last_name, email, message]):
        return {'statusCode': 400, 'headers': CORS_HEADERS, 'body': json.dumps({'error': 'Missing required fields'})}

    if not is_valid_email(email):
        return {'statusCode': 400, 'headers': CORS_HEADERS, 'body': json.dumps({'error': 'Invalid email address'})}

    email_body = f"""
New contact form submission from www.yusmojsolutions.com

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

    try:
        # Send email to admin
        ses.send_email(
            Source=CONTACT_EMAIL,
            Destination={'ToAddresses': [CONTACT_EMAIL]},
            ReplyToAddresses=[email],
            Message={
                'Subject': {'Data': f'[Yusmoj Solutions] {subject}'},
                'Body':    {'Text': {'Data': email_body}},
            },
        )
        
        # Send confirmation email to sender
        ses.send_email(
            Source=CONTACT_EMAIL,
            Destination={'ToAddresses': [email]},
            Message={
                'Subject': {'Data': 'We received your message - Yusmoj Solutions'},
                'Body':    {'Text': {'Data': confirmation_email_body}},
            },
        )
    except ses.exceptions.MessageRejected:
        return {'statusCode': 500, 'headers': CORS_HEADERS, 'body': json.dumps({'error': 'Failed to send email'})}

    return {
        'statusCode': 200,
        'headers': CORS_HEADERS,
        'body': json.dumps({'message': 'Message sent successfully'}),
    }
