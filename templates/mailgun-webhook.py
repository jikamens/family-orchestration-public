#!/usr/bin/env python3

from email.message import EmailMessage
import email.utils
import hmac
import json
import os
import pprint
import re
import sys
import smtplib
import syslog
from syslog import LOG_INFO, LOG_MAIL
from textwrap import dedent


def main():
    config_file = '/etc/sysconfig/mailgun-webhook'
    signing_key = None

    for line in open(config_file):
        match = re.match(r'^\s*signing-key\s*=\s*(.*?)\s*$', line)
        if match:
            signing_key = match.group(1)
            break
    else:
        sys.exit('No signing key in {}'.format(config_file))

    webhook_data = json.load(sys.stdin)
    signature_hash = webhook_data['signature']
    timestamp = signature_hash['timestamp']
    token = signature_hash['token']
    signature = signature_hash['signature']
    computed_signature = hmac_sha256_hex(timestamp + token, signing_key)
    if signature != computed_signature:
        error('Provided signature {} != computed signature {}'.format(
            signature, computed_signature))

    event_data = webhook_data['event-data']
    headers = event_data['message']['headers']
    message_id = headers['message-id']
    subject = headers['subject']
    try:
        sender = email.utils.getaddresses([headers['from']])[0][1]
    except Exception:
        sender = '[unknown]'
    recipient = event_data['recipient']
    delivery_status = event_data['delivery-status']
    status_code = delivery_status['code']
    status_description = delivery_status['description']
    status_message = delivery_status['message']
    message_template = 'Delivery of message from {} to {} with subject "{}" ' \
        'and message-id {} via MailGun failed: {} ({}{})'
    message = message_template.format(
        sender, recipient, subject, message_id, status_message, status_code,
        (' ' + status_description) if status_description else '')

    # Stupid Python syslog library includes the last slash in the path in the
    # default ident string, ugh.
    syslog.openlog(os.path.basename(sys.argv[0]))
    syslog.syslog(LOG_INFO | LOG_MAIL, message)

    if re.search(r'\@({{email_domain}}|{{andrea_domain}})>?$', sender,
                 re.IGNORECASE):
        send_message(sender, message, event_data)

    print('Status: 200 OK\r')
    print('Content-type: text/plain\r')
    print('\r')
    print(message + '\r')


def send_message(sender, message, event_data):
    msg = EmailMessage()
    msg['From'] = 'MAILER_DAEMON <>'
    msg['Subject'] = 'MAIL BOUNCE'
    msg['To'] = sender
    msg.set_content(dedent('''\
        {}

        Debugging information:

        {}
    ''').format(message, pprint.pformat(event_data)))
    smtp = smtplib.SMTP('localhost')
    smtp.send_message(msg)
    smtp.quit()


def error(msg):
    print('Status: 500 Internal Error\r')
    print('Content-Type: text/plain\r')
    print('\r')
    print(msg)
    sys.exit(1)


def hmac_sha256_hex(data, key):
    hash = hmac.new(key.encode(), data.encode(), 'sha256')
    return hash.hexdigest()


if __name__ == '__main__':
    main()
