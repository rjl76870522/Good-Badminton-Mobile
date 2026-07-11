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

## Health checks

Local backend:

```bash
curl http://127.0.0.1:8001/api/health
```

Public API through Cloudflare:

```bash
curl --noproxy '*' https://api.audacity6441.kdns.fr/api/health
```

## Public routing

Cloudflare routes:

```text
https://api.audacity6441.kdns.fr -> http://localhost:8001
```

The Android APK is built with this public API URL as the default backend.

## Sleep policy

This server is configured to avoid sleep/suspend/hibernate while it is used as
an API server. To restore normal sleep behavior:

```bash
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```
