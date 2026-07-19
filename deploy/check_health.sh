#!/usr/bin/env bash
set -euo pipefail

PUBLIC_URL="${GOOD_BADMINTON_HEALTH_URL:-https://api.audacity6441.kdns.fr/api/health}"
LOCAL_URL="${GOOD_BADMINTON_LOCAL_HEALTH_URL:-http://127.0.0.1:8001/api/health}"
TIMEOUT="${GOOD_BADMINTON_HEALTH_TIMEOUT:-20}"

echo "[good-badminton] checking local backend: ${LOCAL_URL}"
curl --fail --silent --show-error --max-time "${TIMEOUT}" "${LOCAL_URL}"
echo

echo "[good-badminton] checking public Cloudflare route: ${PUBLIC_URL}"
curl --fail --silent --show-error --noproxy '*' --max-time "${TIMEOUT}" "${PUBLIC_URL}"
echo

echo "[good-badminton] health check passed"
