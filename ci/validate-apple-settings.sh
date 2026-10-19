#!/bin/bash
set -euo pipefail

missing=0
for name in APPLE_TEAM_ID APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_PRIVATE_KEY MATCH_PASSWORD MATCH_GIT_URL SIGNING_GIT_TOKEN; do
  if [ -z "${!name:-}" ]; then
    echo "::error::Missing $name. Follow docs/RELEASING.md."
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then exit 1; fi

if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo '::error::APPLE_TEAM_ID must be the 10-character Team ID from Apple Developer.'
  exit 1
fi
if [[ ! "$APP_STORE_CONNECT_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo '::error::APP_STORE_CONNECT_KEY_ID must be a 10-character API Key ID.'
  exit 1
fi
if [[ ! "$APP_STORE_CONNECT_ISSUER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo '::error::APP_STORE_CONNECT_ISSUER_ID must be the team API Issuer ID (UUID).'
  exit 1
fi
# Restrict the signing destination to a credential-free GitHub HTTPS URL.
if [[ ! "$MATCH_GIT_URL" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$ ]]; then
  echo '::error::MATCH_GIT_URL must be a credential-free GitHub HTTPS repository URL ending in .git.'
  exit 1
fi
if [ "$MATCH_GIT_URL" = "https://github.com/${GITHUB_REPOSITORY:-}.git" ]; then
  echo '::error::Signing assets must use a separate private repository.'
  exit 1
fi

# Confirm the token reaches a private repository before match reads any assets.
# Never echo the token, API response, or repository contents into public logs.
repo_path="${MATCH_GIT_URL#https://github.com/}"
repo_path="${repo_path%.git}"
if ! curl --fail --silent --show-error   -H "Authorization: Bearer $SIGNING_GIT_TOKEN"   -H "Accept: application/vnd.github+json"   "https://api.github.com/repos/$repo_path"   | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("private") is True else 1)'; then
  echo '::error::Signing repository must be private and readable by SIGNING_GIT_TOKEN.'
  exit 1
fi

# Validate the key without printing its contents or persisting it in the checkout.
key_file=$(mktemp)
chmod 600 "$key_file"
trap 'rm -f "$key_file"' EXIT
printf '%s\n' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$key_file"
if ! openssl pkey -in "$key_file" -check -noout >/dev/null 2>&1; then
  echo '::error::APP_STORE_CONNECT_PRIVATE_KEY must contain the complete contents of the downloaded .p8 file.'
  exit 1
fi
echo 'Apple settings passed validation. No secret values were printed.'
