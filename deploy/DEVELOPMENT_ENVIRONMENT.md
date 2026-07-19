# Isolated development backend

The production backend runs from `/data/projects/Good-Badminton-1` on port
`8001`. Do not use that worktree for experiments.

Development work happens in `/data/projects/Good-Badminton-1-dev` on branch
`feature/durable-task-queue`. Start it on localhost port `8002` with the
production virtual environment until the development worktree gets its own:

```bash
cd /data/projects/Good-Badminton-1-dev
/data/projects/Good-Badminton-1/.venv/bin/python -m uvicorn \
  backend_api:app --host 0.0.0.0 --port 8002
```

Use a local Android debug build with an API override pointing to the Ubuntu
machine's LAN address and port `8002`. TestFlight and production builds must
continue using `https://api.audacity6441.kdns.fr`.

Before promoting backend changes:

1. Run the Python and Flutter test suites in the development worktree
2. Submit several tasks from Android and verify FIFO order and restart recovery
3. Back up `mobile_backend_data/badminton.db`
4. Wait for the production worker to become idle
5. Merge the reviewed commit and restart only `good-badminton-backend`

Cloudflare Pages, the `www` hostname, and `cloudflared` are outside this flow.
