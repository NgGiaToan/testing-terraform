"""Formats account-level security/capacity notifications and posts them to Slack.
Two shapes arrive on the same SNS topic: raw EventBridge events (GuardDuty, Security Hub,
IAM Access Analyzer) and CloudWatch alarm notifications (service quotas) — this module has
no per-customer field to key off of either way, unlike modules/customer-monitoring."""

import json
import os
import urllib.request

import boto3

secrets_client = boto3.client("secretsmanager")

SLACK_TOKEN_SECRET_ARN = os.environ["SLACK_TOKEN_SECRET_ARN"]
SLACK_CHANNEL = os.environ.get("SLACK_CHANNEL", "")

_slack_token = None


def _get_slack_token():
    global _slack_token
    if _slack_token is None:
        _slack_token = secrets_client.get_secret_value(SecretId=SLACK_TOKEN_SECRET_ARN)["SecretString"]
    return _slack_token


def _format_guardduty(detail):
    severity = detail.get("severity", 0)
    label = "HIGH" if severity >= 7 else "MEDIUM" if severity >= 4 else "LOW"
    return "\n".join([
        f"*[GuardDuty {label}] {detail.get('type', 'unknown-finding')}*",
        f"Severity: {severity}  Resource: {detail.get('resource', {}).get('resourceType', 'unknown')}",
        f"Region: {detail.get('region', 'unknown')}",
        f"Description: {detail.get('description', '')}",
    ])


def _format_security_hub(detail):
    findings = detail.get("findings", [{}])
    finding = findings[0]
    severity = finding.get("Severity", {}).get("Label", "UNKNOWN")
    return "\n".join([
        f"*[Security Hub {severity}] {finding.get('Title', 'unknown-control')}*",
        f"Account: {finding.get('AwsAccountId', 'unknown')}  Region: {finding.get('Region', 'unknown')}",
        f"Description: {finding.get('Description', '')}",
    ])


def _format_access_analyzer(detail):
    return "\n".join([
        "*[Access Analyzer] New finding*",
        f"Resource: {detail.get('resource', 'unknown')}",
        f"Resource type: {detail.get('resourceType', 'unknown')}",
        f"Is public: {detail.get('isPublic', 'unknown')}",
    ])


def _format_cloudwatch_alarm(message):
    alarm_name = message.get("AlarmName", "unknown-alarm")
    state = message.get("NewStateValue", "UNKNOWN")
    return "\n".join([
        f"*[{state}] {alarm_name}*",
        message.get("NewStateReason", ""),
    ])


def _format_generic(subject, body):
    return "\n".join([f"*{subject or 'Account alert'}*", body])


def _post_to_slack(text):
    if not SLACK_CHANNEL:
        return
    req = urllib.request.Request(
        "https://slack.com/api/chat.postMessage",
        data=json.dumps({"channel": SLACK_CHANNEL, "text": text}).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {_get_slack_token()}",
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())
        if not result.get("ok"):
            raise RuntimeError(f"Slack API error: {result.get('error')}")


def handler(event, _context):
    for record in event["Records"]:
        sns = record["Sns"]
        raw_message = sns["Message"]
        try:
            message = json.loads(raw_message)
        except (ValueError, TypeError):
            _post_to_slack(_format_generic(sns.get("Subject"), raw_message))
            continue

        source = message.get("source")
        detail = message.get("detail", {})
        if source == "aws.guardduty":
            text = _format_guardduty(detail)
        elif source == "aws.securityhub":
            text = _format_security_hub(detail)
        elif source == "aws.access-analyzer":
            text = _format_access_analyzer(detail)
        elif "AlarmName" in message:
            text = _format_cloudwatch_alarm(message)
        else:
            text = _format_generic(sns.get("Subject"), raw_message)

        _post_to_slack(text)
