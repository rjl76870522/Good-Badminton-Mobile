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
https://www.audacity6441.kdns.fr -> http://localhost:8090
```

To publish the website in Cloudflare Zero Trust, open the existing
`good-badminton` tunnel and add a Public Hostname:

```text
Subdomain: www
Domain: audacity6441.kdns.fr
Type: HTTP
URL: localhost:8090
```

The Android APK is built with this public API URL as the default backend.

## Sleep policy

This server is configured to avoid sleep/suspend/hibernate while it is used as
an API server. To restore normal sleep behavior:

```bash
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```
