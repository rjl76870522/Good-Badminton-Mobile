#!/usr/bin/env bash
set -euo pipefail

exec /home/john/.local/bin/cloudflared tunnel run good-badminton
