"""Formats alerts from every customer account's priority SNS topics (and the management
account's own) and posts them to Slack through Incoming Webhooks.

CloudWatch alarms carry a JSON description written by Terraform (modules/customer-monitoring
alerts.tf): priority, customer, alert_type, service, condition, dashboard_url and notify (the
teams that receive it). The `notify` list picks the Slack webhook — Operations and/or
Engineering. AWS Budgets and Cost Anomaly Detection publish free text to the same topics;
those have no description, so their priority comes from the topic name (...-alerts-p1/p2/p3)
and they go to Operations.

The secret holds either one webhook URL (every team posts there) or JSON mapping a team to its
webhook URL: {"Operations": "https://hooks.slack.com/...", "Engineering": "..."}. A team missing
from the JSON falls back to Operations.

Slack failures are raised, so the Lambda `Errors` alarm fires instead of losing the alert."""

import json
import os
import re
import urllib.request
from datetime import datetime, timezone

import boto3

secrets_client = boto3.client("secretsmanager")

SLACK_WEBHOOK_SECRET_ARN = os.environ["SLACK_WEBHOOK_SECRET_ARN"]
DEFAULT_TEAMS = ["Operations"]

# Attachment colour bar and label per priority; recovery is always green.
PRIORITY_STYLE = {
    "P1": {"color": "#d9262c", "label": "P1 CRITICAL"},
    "P2": {"color": "#e8801a", "label": "P2 HIGH"},
    "P3": {"color": "#f2c744", "label": "P3 MEDIUM"},
}
OK_COLOR = "#2eb67d"

_webhooks = None


def _get_webhooks():
    """Team -> webhook URL, read once per container from Secrets Manager."""
    global _webhooks
    if _webhooks is None:
        raw = secrets_client.get_secret_value(SecretId=SLACK_WEBHOOK_SECRET_ARN)["SecretString"].strip()
        try:
            parsed = json.loads(raw)
        except ValueError:
            parsed = raw  # a bare URL: every team posts to the same webhook
        if isinstance(parsed, dict):
            default = parsed.get("Operations") or next(iter(parsed.values()), "")
            _webhooks = {team: parsed.get(team) or default for team in ("Operations", "Engineering")}
        else:
            _webhooks = {"Operations": raw, "Engineering": raw}
    return _webhooks


def _priority_from_topic(topic_arn):
    match = re.search(r"-alerts-(p[123])$", topic_arn.rsplit(":", 1)[-1])
    return match.group(1).upper() if match else "P3"


def _region_from_arn(arn):
    """arn:aws:cloudwatch:<region>:<account>:alarm:<name>"""
    parts = (arn or "").split(":")
    return parts[3] if len(parts) > 3 and parts[3] else "n/a"


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
        f"*Region:* {message.get('Region') or _region_from_arn(message.get('AlarmArn'))}",
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


def _post_to_slack(webhook_url, alert):
    body = {
        "text": alert["title"],
        "attachments": [{"color": alert["color"], "title": alert["title"], "text": alert["text"], "mrkdwn_in": ["text"]}],
    }
    req = urllib.request.Request(
        webhook_url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    # A webhook answers 200 "ok" on success and raises HTTPError (4xx/5xx) otherwise.
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


def handler(event, _context):
    failures = []
    webhooks = _get_webhooks()
    for record in event["Records"]:
        alert = _build_alert(record["Sns"])
        # A set, so an alert addressed to two teams that share a webhook posts once.
        urls = {webhooks.get(team) for team in alert["teams"]} - {None, ""}
        for url in sorted(urls):
            try:
                _post_to_slack(url, alert)
            except Exception as exc:  # keep going so one bad webhook doesn't drop the others
                # Never log the URL: it is the credential. Only the host's error is kept.
                failures.append(f"Slack webhook post failed: {type(exc).__name__}: {exc}")
    if failures:
        raise RuntimeError("; ".join(failures))
