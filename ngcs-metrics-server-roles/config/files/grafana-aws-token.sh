#!/usr/bin/env bash
# Managed by Ansible (role config).
#
# Asks the Azure instance metadata service for a token of the Managed Identity of this VM, for the audience that
# the AWS OIDC provider trusts, and writes it to TOKEN_FILE. Grafana reads that file as
# AWS_WEB_IDENTITY_TOKEN_FILE and AWS SDK Default exchanges it for temporary AWS credentials
# (sts:AssumeRoleWithWebIdentity). Run by grafana-aws-token.timer; the values come from the unit's Environment.
set -euo pipefail

: "${AZURE_AUDIENCE:?AZURE_AUDIENCE is not set}"
: "${AZURE_CLIENT_ID:?AZURE_CLIENT_ID is not set}"
: "${TOKEN_FILE:?TOKEN_FILE is not set}"

# Write a temporary file in the same directory, then rename it, so Grafana never reads a half-written token.
tmp="$(mktemp "${TOKEN_FILE}.XXXXXX")"
trap 'rm -f "${tmp}"' EXIT

curl --silent --show-error --fail --max-time 10 \
  --header "Metadata:true" --get \
  --data-urlencode "api-version=2018-02-01" \
  --data-urlencode "resource=${AZURE_AUDIENCE}" \
  --data-urlencode "client_id=${AZURE_CLIENT_ID}" \
  "http://169.254.169.254/metadata/identity/oauth2/token" \
  | jq --exit-status --raw-output '.access_token' > "${tmp}"

chmod 0640 "${tmp}"
mv -f "${tmp}" "${TOKEN_FILE}"
