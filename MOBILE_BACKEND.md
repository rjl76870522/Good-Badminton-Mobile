# Mobile backend loop

This is the first local backend for an iPhone or mobile-web demo.

## Start

From the project root:

```bat
start_mobile_backend.bat
```

Or manually:

```bat
C:\Users\jiale\miniconda3\envs\badminton\python.exe -m uvicorn backend_api:app --host 0.0.0.0 --port 8001
```

Open the API docs on the computer:

```text
http://127.0.0.1:8001/docs
```

From an iPhone on the same Wi-Fi, use:

```text
http://<computer-lan-ip>:8001
```

Windows Firewall may ask whether Python can accept private-network traffic.
Allow it for local phone testing.

## API

Upload a video:

```text
POST /api/videos/upload
```

Multipart fields:

- `file`: video file when no preview upload is being reused
- `source_upload_id`: ID returned by `/api/videos/preview-frame`
- `user_id`: stable identifier used to isolate device history
- `template_path`: optional template path. Defaults to `templates/badminton_template.png`,
  then `templates/my_template.png`, then `templates/demo.png`.
- `corners_json`: optional JSON array of 4 court corners, for example
  `[[835,684],[1711,679],[2096,1380],[455,1386]]`.
- `language`: `zh` or `en`, default `zh`.
- `pose_mode`: `lightweight`, `balanced`, or `performance`, default `balanced`.
- `keep_audio`: boolean, default `true`.

Create a preview before the final upload:

```text
POST /api/videos/preview-frame
```

Send multipart fields `file` and `user_id`. The response contains
`source_upload_id`, `image_url`, video metadata, optional automatic corners,
and frame-quality metrics. The final upload can reuse `source_upload_id`
instead of transferring the video again.

Poll a task:

```text
GET /api/tasks/{task_id}
```

Read queue and worker-pool status:

```text
GET /api/queue
```

Read the report:

```text
GET /api/tasks/{task_id}/report
```

Play the generated highlight video:

```text
GET /api/tasks/{task_id}/highlight
```

Read training history:

```text
GET /api/history?user_id=<device-user-id>&limit=20
GET /api/history?status=completed
```

Read a demo sample for UI development:

```text
GET /api/demo/sample
```

The report includes:

- summary metrics for the primary tracked player
- player-level movement stats
- generated advice text
- URLs for analysis video, highlight video, heatmap, trajectory image, metadata, and detections
- highlight segment reasons and scores

File URLs are relative paths. Prefix them with the backend base URL.

Example:

```text
http://172.29.72.218:8001/outputs/.../match_heatmap.png
```

## Notes

Tasks and status transitions are persisted in SQLite under
`mobile_backend_data/badminton.db`. Uploads can run concurrently. Analysis uses
a bounded worker pool: `ANALYSIS_WORKERS=auto` chooses a conservative capacity
from GPU memory, while the Ubuntu RTX 5000 service explicitly uses three workers.
Queued and interrupted tasks survive backend restarts.
