# Good-Badminton Frontend Handoff

This document is for the teammate building the mobile frontend.

## Project Role

This repo contains two backend surfaces:

| Port | Entry | Purpose |
| --- | --- | --- |
| `8000` | `server/main.py` | Browser demo with built-in web UI |
| `8001` | `backend_api.py` | Mobile App API for Flutter/iOS integration |

Frontend work should use **port 8001**.

## Start The Mobile API

On the backend computer:

```bat
D:\py\Good-Badminton\start_mobile_backend.bat
```

Or manually:

```bat
C:\Users\jiale\miniconda3\envs\badminton\python.exe -m uvicorn backend_api:app --host 0.0.0.0 --port 8001
```

Open API docs on the backend computer:

```text
http://127.0.0.1:8001/docs
```

Open from a phone on the same Wi-Fi:

```text
http://BACKEND_COMPUTER_IP:8001/api/health
```

Current local test IP was:

```text
http://172.29.72.218:8001
```

The IP may change. On Windows, run:

```powershell
ipconfig
```

Use the IPv4 address under `WLAN`, not VPN/WSL/Clash adapters.

## Base URL

For same-Wi-Fi development:

```text
http://172.29.72.218:8001
```

When deploying through tunnel/public server later, replace only the base URL.
Endpoint paths stay the same.

## Main App Flow

1. Check backend health.
2. Upload video.
3. Save `task_id`.
4. Poll task status every 2-5 seconds.
5. When status is `completed`, load report.
6. Render report cards, images, analysis video, and highlight video.
7. Use history endpoint for the history page.

## Endpoints

### Health

```http
GET /api/health
```

### Upload Video

```http
POST /api/videos/upload
Content-Type: multipart/form-data
```

Fields:

| Field | Required | Notes |
| --- | --- | --- |
| `file` | yes | Video file |
| `template_path` | no | Leave empty, or use `templates/badminton_template.png` |
| `corners_json` | no | Leave empty unless manual court corners are known |
| `language` | no | `zh` or `en`, default `zh` |
| `pose_mode` | no | `lightweight`, `balanced`, or `performance` |
| `keep_audio` | no | `true` or `false` |

Important:

Do **not** send Swagger placeholder text `string` for `template_path` or `corners_json`.

Successful response:

```json
{
  "task_id": "35c85ba1f82c4d689bbd5063f64e5be6",
  "status": "queued",
  "status_url": "/api/tasks/35c85ba1f82c4d689bbd5063f64e5be6",
  "report_url": "/api/tasks/35c85ba1f82c4d689bbd5063f64e5be6/report"
}
```

### Poll Task

```http
GET /api/tasks/{task_id}
```

Status values:

| Status | Meaning |
| --- | --- |
| `queued` | Waiting |
| `processing` | AI analysis running |
| `completed` | Report ready |
| `failed` | Analysis failed; show `error` |

### Read Report

```http
GET /api/tasks/{task_id}/report
```

If the task is still running, this returns HTTP `202`.

Important report fields:

```json
{
  "summary": {
    "total_distance_m": 18.48,
    "max_speed_mps": 6.03,
    "avg_speed_mps": 2.25,
    "intensity_score": 38
  },
  "players": [],
  "advice": [],
  "files": {
    "analysis_video": "/outputs/.../web_detect_xxx.mp4",
    "highlight": "/outputs/.../highlight.mp4",
    "heatmap": "/outputs/.../match_heatmap.png",
    "trajectory": "/outputs/.../match_scatter.png"
  },
  "highlight_segments": [
    {
      "start_sec": 0.0,
      "end_sec": 9.24,
      "score": 83,
      "reason": "high-speed shuttle + fast player movement + high movement distance"
    }
  ]
}
```

### Play Highlight

```http
GET /api/tasks/{task_id}/highlight
```

This returns `video/mp4`.

The same file is also available through:

```text
baseUrl + report.files.highlight
```

### History

```http
GET /api/history?limit=20
GET /api/history?status=completed
```

Use this for the history page.

### Demo Sample

```http
GET /api/demo/sample
```

Use this to build UI before uploading a real video. It returns the latest completed real report if one exists, otherwise mock data.

## File URL Rule

All file URLs in the report are relative paths.

Example:

```json
{
  "heatmap": "/outputs/webui_xxx/position_visualizations/heatmaps/match_heatmap.png"
}
```

Frontend should render:

```text
baseUrl + heatmap
```

Example:

```text
http://172.29.72.218:8001/outputs/webui_xxx/position_visualizations/heatmaps/match_heatmap.png
```

## Flutter Integration Notes

Recommended packages:

- `dio` for upload progress and API requests
- `video_player` for analysis/highlight videos
- `cached_network_image` for heatmap/trajectory images

Suggested pages:

- Home
- Upload
- Task status
- Report
- Highlight
- History
- Profile/About

## Development Constraints

For MVP testing:

- Use short videos first: 8 seconds to 1 minute.
- Prefer one complete rally without rest or shuttle-pickup footage.
- Avoid 4K/large videos during early testing.
- Fixed horizontal camera angle gives much better results.
- The backend processes one AI job at a time for stability.

## Remote Access / Tunnel

Do not start with public tunneling while APIs are still changing.

Recommended order:

1. Finish same-Wi-Fi integration with `8001`.
2. Confirm upload, task polling, report, history, and highlight all work.
3. Add upload size/duration limits.
4. Then use a tunnel/public URL.

Recommended tunnel options:

- Development: Tailscale or ZeroTier
- Demo/public HTTPS: Cloudflare Tunnel
- More controllable deployment: `frp` plus a cloud server

When tunneling is ready, the frontend only changes:

```text
baseUrl = https://your-public-domain
```

## Related Docs

- `FRONTEND_API.md`: detailed API contract
- `MOBILE_BACKEND.md`: backend notes
- `backend_api.py`: mobile API implementation
- `server/main.py`: browser demo backend
