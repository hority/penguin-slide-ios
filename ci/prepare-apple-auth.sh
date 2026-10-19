#!/bin/bash
set -euo pipefail

umask 077
key_path="$RUNNER_TEMP/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
printf '%s\n' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$key_path"
printf 'APP_STORE_CONNECT_KEY_PATH=%s\n' "$key_path" >> "$GITHUB_ENV"
git_auth=$(printf 'x-access-token:%s' "$SIGNING_GIT_TOKEN" | base64 | tr -d '\n')
echo "::add-mask::$git_auth"
printf 'MATCH_GIT_BASIC_AUTHORIZATION=%s\n' "$git_auth" >> "$GITHUB_ENV"
