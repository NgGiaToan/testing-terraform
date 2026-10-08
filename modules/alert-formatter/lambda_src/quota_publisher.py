"""Publishes `Lighthouse/Quotas` `QuotaUsagePercent` (dimension Quota) for the management
account's regional quotas that limit customer onboarding: VPCs and Elastic IPs. The AWS/Usage
metrics need "Monitor with CloudWatch" switched on per quota and give a count, not a
percentage, so this computes usage / quota itself.

QUOTAS is a JSON list of {"name", "service_code", "quota_code", "usage"} — `usage` selects
the counter below. Runs on a schedule (every 5 minutes, matching the alarm period)."""

import json
import os

import boto3

QUOTAS = json.loads(os.environ["QUOTAS"])
REGION = os.environ.get("AWS_REGION")

cloudwatch = boto3.client("cloudwatch")
quotas_client = boto3.client("service-quotas")
ec2 = boto3.client("ec2")


def _count_vpcs():
    return sum(len(page["Vpcs"]) for page in ec2.get_paginator("describe_vpcs").paginate())


def _count_elastic_ips():
    return len(ec2.describe_addresses()["Addresses"])


COUNTERS = {"vpcs": _count_vpcs, "elastic-ips": _count_elastic_ips}


def _quota_value(service_code, quota_code):
    try:
        return quotas_client.get_service_quota(ServiceCode=service_code, QuotaCode=quota_code)["Quota"]["Value"]
    except quotas_client.exceptions.NoSuchResourceException:
        # Never raised/lowered for this account: fall back to the AWS default.
        return quotas_client.get_aws_default_service_quota(ServiceCode=service_code, QuotaCode=quota_code)["Quota"]["Value"]


def handler(_event, _context):
    metric_data = []
    for quota in QUOTAS:
        used = COUNTERS[quota["usage"]]()
        limit = _quota_value(quota["service_code"], quota["quota_code"])
        metric_data.append(
            {
                "MetricName": "QuotaUsagePercent",
                "Dimensions": [{"Name": "Quota", "Value": quota["name"]}],
                "Value": used / limit * 100,
                "Unit": "Percent",
            }
        )
        print(f"{REGION} {quota['name']}: {used}/{limit}")
    cloudwatch.put_metric_data(Namespace="Lighthouse/Quotas", MetricData=metric_data)
