# Ubuntu server operations

This machine runs the Good Badminton backend behind Cloudflare Tunnel.

## Services

Backend API:

```bash
sudo systemctl status good-badminton-backend --no-pager
sudo systemctl restart good-badminton-backend
journalctl -u good-badminton-backend -n 100 --no-pager
```

Cloudflare Tunnel:

```bash
sudo systemctl status cloudflared --no-pager
sudo systemctl restart cloudflared
journalctl -u cloudflared -n 100 --no-pager
```

Static website:

```bash
sudo systemctl status good-badminton-site --no-pager
sudo systemctl restart good-badminton-site
journalctl -u good-badminton-site -n 100 --no-pager
```

Health timer:

```bash
sudo systemctl status good-badminton-healthcheck.timer --no-pager
journalctl -u good-badminton-healthcheck -n 100 --no-pager
```

## Health checks

Local backend:

```bash
curl http://127.0.0.1:8001/api/health
```

Local website:

```bash
curl http://127.0.0.1:8090/
```

Public API through Cloudflare:

```bash
curl --noproxy '*' https://api.audacity6441.kdns.fr/api/health
```

Full diagnostics:

```bash
curl http://127.0.0.1:8001/api/diagnostics
./deploy/check_health.sh
.venv/bin/python deploy/check_gpu.py
```

## Analysis concurrency

Uploads are accepted concurrently and persisted as separate SQLite tasks. The
analysis worker pool is bounded independently so several phones can upload at
once without starting an unbounded number of CUDA jobs.

The Quadro RTX 5000 16 GB server is configured for four concurrent analyses:

```ini
Environment=ANALYSIS_WORKERS=4
```

Inspect live capacity and queue pressure with:

```bash
curl http://127.0.0.1:8001/api/queue
```

The response reports `queued`, `processing`, `capacity`, and `active_workers`.
Use `ANALYSIS_WORKERS=auto` outside systemd to select 1-4 workers from detected
GPU memory. Do not raise the production value above 4 without repeating the
multi-video GPU stress test and checking CPU load, disk throughput, and CUDA OOM
errors. Matplotlib report rendering is serialized because it uses global state;
model inference and video processing remain concurrent.

## Optional timer install

```bash
sudo cp deploy/good-badminton-healthcheck.service /etc/systemd/system/
sudo cp deploy/good-badminton-healthcheck.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now good-badminton-healthcheck.timer
```

The timer logs health-check failures into journald.

## Optional journal limits

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo cp deploy/journald-good-badminton.conf /etc/systemd/journald.conf.d/good-badminton.conf
sudo systemctl restart systemd-journald
```

## Public routing

Cloudflare routes:

```text
https://api.audacity6441.kdns.fr -> http://localhost:8001
https://www.audacity6441.kdns.fr -> Cloudflare Pages
```

The static website should be deployed with Cloudflare Pages so it remains
available while the Ubuntu server is offline. Connect the GitHub repository
and use these build settings:

```text
Production branch: main
Framework preset: None
Build command: leave empty
Build output directory: website
Root directory: /
```

After the first deployment, add `www.audacity6441.kdns.fr` as the Pages custom
domain. Remove the old `www` Public Hostname from the Cloudflare Tunnel first
to prevent conflicting DNS routes. Keep `api.audacity6441.kdns.fr` on the
Tunnel because video analysis still runs on this Ubuntu server.

`website/_headers` defines cache and security headers. Cloudflare Pages provides
clean `/privacy` and `/support` URLs automatically for the matching HTML files.

The Android APK is built with this public API URL as the default backend.

## Sleep policy

This server is configured to avoid sleep/suspend/hibernate while it is used as
an API server. To restore normal sleep behavior:

```bash
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```
