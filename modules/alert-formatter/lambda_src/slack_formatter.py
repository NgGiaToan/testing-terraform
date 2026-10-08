"""Formats alerts from every customer account's priority SNS topics (and the management
account's own) and posts them to Slack with chat.postMessage.

CloudWatch alarms carry a JSON description written by Terraform (modules/customer-monitoring
alerts.tf): priority, customer, alert_type, service, condition, dashboard_url and notify (the
teams that receive it). The `notify` list picks the Slack channels — Operations and/or
Engineering. AWS Budgets and Cost Anomaly Detection publish free text to the same topics;
those have no description, so their priority comes from the topic name (...-alerts-p1/p2/p3)
and they go to Operations.

Slack failures are raised, so the Lambda `Errors` alarm fires instead of losing the alert."""

import json
import os
import re
import urllib.request
from datetime import datetime, timezone

import boto3

secrets_client = boto3.client("secretsmanager")

SLACK_TOKEN_SECRET_ARN = os.environ["SLACK_TOKEN_SECRET_ARN"]
CHANNELS = {
    "Operations": os.environ.get("SLACK_CHANNEL_OPERATIONS", ""),
    "Engineering": os.environ.get("SLACK_CHANNEL_ENGINEERING", ""),
}
DEFAULT_TEAMS = ["Operations"]

# Attachment colour bar and label per priority; recovery is always green.
PRIORITY_STYLE = {
    "P1": {"color": "#d9262c", "label": "P1 CRITICAL"},
    "P2": {"color": "#e8801a", "label": "P2 HIGH"},
    "P3": {"color": "#f2c744", "label": "P3 MEDIUM"},
}
OK_COLOR = "#2eb67d"

_slack_token = None


def _get_slack_token():
    global _slack_token
    if _slack_token is None:
        _slack_token = secrets_client.get_secret_value(SecretId=SLACK_TOKEN_SECRET_ARN)["SecretString"]
    return _slack_token


def _priority_from_topic(topic_arn):
    match = re.search(r"-alerts-(p[123])$", topic_arn.rsplit(":", 1)[-1])
    return match.group(1).upper() if match else "P3"


def _parse_description(raw):
    """The alarm description is JSON written by Terraform; tolerate a plain-text one."""
    try:
        parsed = json.loads(raw or "")
        return parsed if isinstance(parsed, dict) else {}
    except ValueError:
        return {}


def _alarm_alert(message, topic_arn):
    meta = _parse_description(message.get("AlarmDescription"))
    state = message.get("NewStateValue", "UNKNOWN")
    priority = meta.get("priority") or _priority_from_topic(topic_arn)
    style = PRIORITY_STYLE.get(priority, PRIORITY_STYLE["P3"])
    recovered = state == "OK"

    fields = [
        f"*Customer:* {meta.get('customer', 'n/a')}",
        f"*Service:* {meta.get('service', 'n/a')}",
        f"*Alert:* {meta.get('alert_type', message.get('Trigger', {}).get('MetricName', 'n/a'))}",
        f"*Condition:* {meta.get('condition') or message.get('AlarmDescription') or 'n/a'}",
        f"*State:* {state} — {message.get('NewStateReason', '')}",
        f"*Time:* {message.get('StateChangeTime', datetime.now(timezone.utc).isoformat())}",
    ]
    if meta.get("dashboard_url"):
        fields.append(f"*Dashboard:* <{meta['dashboard_url']}|Environment Overview>")

    title = f"{'RESOLVED' if recovered else style['label']} · {message.get('AlarmName', 'unknown-alarm')}"
    return {
        "title": title,
        "text": "\n".join(fields),
        "color": OK_COLOR if recovered else style["color"],
        "teams": meta.get("notify") or DEFAULT_TEAMS,
    }


def _generic_alert(subject, body, topic_arn):
    priority = _priority_from_topic(topic_arn)
    style = PRIORITY_STYLE[priority]
    return {
        "title": f"{style['label']} · {subject or 'Alert'}",
        "text": f"{body}\n*Time:* {datetime.now(timezone.utc).isoformat()}",
        "color": style["color"],
        "teams": DEFAULT_TEAMS,
    }


def _build_alert(sns):
    topic_arn = sns["TopicArn"]
    raw = sns["Message"]
    try:
        message = json.loads(raw)
    except ValueError:
        message = None
    if isinstance(message, dict) and "AlarmName" in message:
        return _alarm_alert(message, topic_arn)
    return _generic_alert(sns.get("Subject"), raw, topic_arn)


def _post_to_slack(channel, alert):
    body = {
        "channel": channel,
        "text": alert["title"],
        "attachments": [{"color": alert["color"], "title": alert["title"], "text": alert["text"], "mrkdwn_in": ["text"]}],
    }
    req = urllib.request.Request(
        "https://slack.com/api/chat.postMessage",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {_get_slack_token()}",
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())
    if not result.get("ok"):
        raise RuntimeError(f"Slack API error posting to {channel}: {result.get('error')}")


def handler(event, _context):
    failures = []
    for record in event["Records"]:
        alert = _build_alert(record["Sns"])
        # A set, so an alert addressed to two teams that share a channel posts once.
        channels = {CHANNELS.get(team) for team in alert["teams"]} - {None, ""}
        for channel in sorted(channels):
            try:
                _post_to_slack(channel, alert)
            except Exception as exc:  # keep going so one bad channel doesn't drop the others
                failures.append(str(exc))
    if failures:
        raise RuntimeError("; ".join(failures))
