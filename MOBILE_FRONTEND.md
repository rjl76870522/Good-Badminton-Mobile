# Good-Badminton Mobile Frontend

This is a lightweight static frontend for the mobile API backend. It is meant for local demos and for frontend handoff while the real app UI is still being built.

## Run

Start the mobile backend:

```bat
D:\py\Good-Badminton\start_mobile_backend.bat
```

Open on the computer:

```text
http://127.0.0.1:8001/app
```

Open on a phone in the same Wi-Fi:

```text
http://172.29.72.218:8001/app
```

The app uses the current browser origin as `baseUrl`, so the same files work on `127.0.0.1`, LAN IP, or a future tunnel/domain.

## What It Covers

- Health check against `GET /api/health`
- Local guest `user_id` stored in `localStorage`
- Video upload via `POST /api/videos/upload`
- Optional manual court corners via `corners_json`
- Task polling via `GET /api/tasks/{task_id}`
- History via `GET /api/history?user_id=...`
- Report via `GET /api/tasks/{task_id}/report`
- Media preview for analysis video, heatmap, trajectory, and highlight
- Unified backend error parsing from `detail.code`, `detail.message`, and `detail.hint`

## Files

```text
mobile_frontend/
  index.html
  styles.css
  app.js
```

`backend_api.py` mounts this directory at `/app` and redirects `/` to `/app/`.
