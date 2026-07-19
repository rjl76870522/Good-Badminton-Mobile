#!/bin/bash
cd /data/projects/Good-Badminton-1
export PYTHONPATH=/data/projects/Good-Badminton-1
export ALL_PROXY=""
export all_proxy=""
export NO_PROXY="*"
export no_proxy="*"
export ANALYSIS_WORKERS="${ANALYSIS_WORKERS:-auto}"
exec /data/projects/Good-Badminton-1/.venv/bin/python -u -m uvicorn backend_api:app --host 0.0.0.0 --port 8001
