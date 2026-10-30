import json
import os
import re
from datetime import datetime, timezone

import boto3
import urllib3

secrets_client = boto3.client("secretsmanager")
http = urllib3.PoolManager(timeout=urllib3.Timeout(connect=5, read=10))

SLACK_WEBHOOK_SECRET_ARN = os.environ["SLACK_WEBHOOK_SECRET_ARN"]
TEAMS = ("Operations", "Engineering")  # one webhook (channel) each
Operations_TEAMS = ["Operations"]  # alerts that name no team (Budgets, Cost Anomaly)

# Attachment colour bar and label per priority; recovery is always green.
PRIORITY_STYLE = {
    "P1": {"color": "#d9262c", "label": "P1 CRITICAL"},
    "P2": {"color": "#e8801a", "label": "P2 HIGH"},
    "P3": {"color": "#f2c744", "label": "P3 MEDIUM"},
}
OK_COLOR = "#2eb67d"

_webhooks = None


def _get_webhooks():
    global _webhooks
    if _webhooks is None:
        raw = secrets_client.get_secret_value(SecretId=SLACK_WEBHOOK_SECRET_ARN)["SecretString"]
        try:
            parsed = json.loads(raw)
        except ValueError:
            raise RuntimeError("Slack webhook secret is not valid JSON") from None
        if not isinstance(parsed, dict):
            raise RuntimeError("Slack webhook secret must be a JSON object with a URL per team")
        missing = [team for team in TEAMS if not parsed.get(team)]
        if missing:
            raise RuntimeError(f"Slack webhook secret has no URL for: {', '.join(missing)}")
        _webhooks = {team: parsed[team].strip() for team in TEAMS}
    return _webhooks


def _priority_from_topic(topic_arn: str) -> str:
    """Priority ("P1", "P2" or "P3") from the SNS topic ARN's `-alerts-p<n>` suffix; "P3" if absent."""
    match = re.search(r"-alerts-(p[123])$", topic_arn.rsplit(":", 1)[-1])
    return match.group(1).upper() if match else "P3"


def _region_from_arn(arn):
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

    environment = meta.get("environment")
    fields = [
        f"*Customer:* {meta.get('customer', 'n/a')}",
        f"*Environment:* {environment or 'n/a'}",
        f"*Region:* {message.get('Region') or _region_from_arn(message.get('AlarmArn'))}",
        f"*Service:* {meta.get('service', 'n/a')}",
        f"*Alert:* {meta.get('alert_type', message.get('Trigger', {}).get('MetricName', 'n/a'))}",
        f"*Condition:* {meta.get('condition') or message.get('AlarmDescription') or 'n/a'}",
        f"*State:* {state} — {message.get('NewStateReason', '')}",
        f"*Time:* {message.get('StateChangeTime', datetime.now(timezone.utc).isoformat())}",
    ]
    if meta.get("dashboard_url"):
        fields.append(f"*Dashboard:* <{meta['dashboard_url']}|Environment Overview>")

    env_tag = f"[{environment}] " if environment else ""
    title = f"{'RESOLVED' if recovered else style['label']} · {env_tag}{message.get('AlarmName', 'unknown-alarm')}"
    return {
        "title": title,
        "text": "\n".join(fields),
        "color": OK_COLOR if recovered else style["color"],
        "teams": meta.get("notify") or Operations_TEAMS,
    }


def _generic_alert(subject, body, topic_arn):
    priority = _priority_from_topic(topic_arn)
    style = PRIORITY_STYLE[priority]
    return {
        "title": f"{style['label']} · {subject or 'Alert'}",
        "text": f"{body}\n*Time:* {datetime.now(timezone.utc).isoformat()}",
        "color": style["color"],
        "teams": Operations_TEAMS,
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
    resp = http.request(
        "POST",
        webhook_url,
        body=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
    )
    response_text = resp.data.decode("utf-8", errors="replace")
    # Logged for every post: the alert title, Slack's status code and its reply ("ok", or an
    # error such as "no_service" or "invalid_payload"). The webhook URL is never logged.
    print({"alert": alert["title"], "status_code": resp.status, "response": response_text})
    # urllib3 does not raise on 4xx/5xx, so check the status. Slack answers 200 "ok" on success.
    if resp.status != 200:
        raise RuntimeError(f"Slack returned {resp.status}: {response_text}")


def _redact(text, webhook_url):
    secret_path = urllib3.util.parse_url(webhook_url).path
    text = text.replace(webhook_url, "<webhook>")
    return text.replace(secret_path, "<path>") if secret_path else text


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
                # The URL is the credential: redact it from the error before it is kept.
                failures.append(f"Slack webhook post failed: {type(exc).__name__}: {_redact(str(exc), url)}")
    if failures:
        raise RuntimeError("; ".join(failures))
