# Good-Badminton Mobile API

This is the Flutter/mobile API surface. Use `backend_api.py`, not `server/main.py`, for app integration.

## Base URL

Same Wi-Fi development:

```text
http://172.29.72.218:8001
```

Computer-only testing:

```text
http://127.0.0.1:8001
```

When the backend is moved behind a tunnel or domain, only replace the base URL. Endpoint paths stay the same.

## Health Check

```http
GET /api/health
```

Expected:

```json
{
  "ok": true,
  "service": "good-badminton-mobile-backend",
  "version": "0.2.0"
}
```

## Create Preview

```http
POST /api/videos/preview-frame
Content-Type: multipart/form-data
```

Fields:

| Name | Required | Value |
| --- | --- | --- |
| `file` | yes | MP4, MOV, or M4V video, up to 200 MB |
| `user_id` | no | Stable device/user identifier |

The backend saves the video and returns a representative frame:

```json
{
  "source_upload_id": "4c66718b0c9f4e39a847c226a99638b1",
  "image_url": "/api/videos/preview-images/4c66718b0c9f4e39a847c226a99638b1",
  "frame_index": 264,
  "time_sec": 8.8,
  "selection_reason": "best_quality_sample",
  "auto_corners": [],
  "video": {
    "width": 1280,
    "height": 720,
    "duration_sec": 14.2,
    "fps": 30.0,
    "total_frames": 426
  },
  "quality": {
    "score": 0.82
  }
}
```

Use `image_url` for manual court-corner marking. Keep `source_upload_id`
for the final upload request so the video is not uploaded twice.

## Upload Video

```http
POST /api/videos/upload
Content-Type: multipart/form-data
```

Fields:

| Name | Required | Value |
| --- | --- | --- |
| `file` | conditionally | video file when `source_upload_id` is absent |
| `source_upload_id` | conditionally | ID from the preview endpoint |
| `user_id` | no | Same identifier used for preview and history |
| `template_path` | no | leave empty, or use `templates/badminton_template.png` |
| `corners_json` | no | leave empty, or JSON like `[[824,711],[1728,711],[2093,1382],[459,1382]]` |
| `language` | no | `zh` or `en`, default `zh` |
| `pose_mode` | no | `lightweight`, `balanced`, or `performance`, default `balanced` |
| `keep_audio` | no | `true` or `false`, default `true` |

Do not send Swagger's placeholder value `string` for `template_path` or `corners_json`.
Send exactly one of `file` and `source_upload_id`.

Response:

```json
{
  "task_id": "35c85ba1f82c4d689bbd5063f64e5be6",
  "status": "queued",
  "status_url": "/api/tasks/35c85ba1f82c4d689bbd5063f64e5be6",
  "report_url": "/api/tasks/35c85ba1f82c4d689bbd5063f64e5be6/report"
}
```

## Poll Task Status

```http
GET /api/tasks/{task_id}
```

Response:

```json
{
  "task_id": "35c85ba1f82c4d689bbd5063f64e5be6",
  "status": "processing",
  "progress": 0.42,
  "stage": "analyzing_video",
  "error": null,
  "video_name": "sample.mp4",
  "created_at": 1783069200.0,
  "updated_at": 1783069260.0,
  "report_url": "/api/tasks/35c85ba1f82c4d689bbd5063f64e5be6/report"
}
```

Status values:

| Status | Meaning |
| --- | --- |
| `queued` | waiting |
| `processing` | analyzing |
| `completed` | report is ready |
| `failed` | analysis failed; show `error` |

Poll every 2-5 seconds while status is `queued` or `processing`.

## Read Report

```http
GET /api/tasks/{task_id}/report
```

If analysis is not finished, the endpoint returns HTTP `202`.

Completed reports include:

```json
{
  "schema_version": "mobile-report-v1",
  "summary": {
    "total_distance_m": 18.48,
    "max_speed_mps": 6.03,
    "avg_speed_mps": 2.25,
    "intensity_score": 38,
    "detected_frames": 248,
    "shuttlecock_frames": 162
  },
  "players": [],
  "advice": [],
  "files": {
    "analysis_video": "/outputs/.../web_detect_sample.mp4",
    "heatmap": "/outputs/.../match_heatmap.png",
    "trajectory": "/outputs/.../match_scatter.png",
    "highlight": "/outputs/.../highlight.mp4"
  },
  "highlight_segments": [
    {
      "start_sec": 0.0,
      "end_sec": 9.24,
      "score": 83,
      "reason": "high-speed shuttle + fast player movement",
      "metrics": {
        "shuttle_peak_px_s": 2237.86,
        "player_peak_mps": 11.14,
        "player_distance_m": 32.93
      }
    }
  ]
}
```

File paths are relative. Build absolute URLs by prefixing the base URL:

```text
baseUrl + files.heatmap
```

Example:

```text
http://172.29.72.218:8001/outputs/.../match_heatmap.png
```

## Play Highlight

```http
GET /api/tasks/{task_id}/highlight
```

This returns `video/mp4` when a highlight has been generated. The same video is also exposed as `report.files.highlight`.

## History

```http
GET /api/history?limit=20
GET /api/history?status=completed
GET /api/history?user_id=DEVICE_USER_ID
```

Response:

```json
{
  "items": [
    {
      "task_id": "35c85ba1f82c4d689bbd5063f64e5be6",
      "status": "completed",
      "progress": 1.0,
      "stage": "completed",
      "video_name": "sample.mp4",
      "summary": {
        "total_distance_m": 18.48,
        "max_speed_mps": 6.03,
        "avg_speed_mps": 2.25,
        "intensity_score": 38
      },
      "thumbnail": "/outputs/.../match_heatmap.png",
      "report_url": "/api/tasks/35c85ba1f82c4d689bbd5063f64e5be6/report"
    }
  ],
  "total": 1
}
```

## Demo Sample

```http
GET /api/demo/sample
```

Use this to build UI before uploading real video. If a completed task exists, it returns the latest real report. Otherwise it returns mock data.

## Recommended App Flow

1. Open app and call `GET /api/health`.
2. Upload once to `POST /api/videos/preview-frame`.
3. Mark court corners on the returned preview image.
4. Submit `source_upload_id` and corners to `POST /api/videos/upload`.
5. Save `task_id`.
6. Poll `GET /api/tasks/{task_id}` until `completed` or `failed`.
7. On `completed`, call `GET /api/tasks/{task_id}/report`.
8. Prefix file URLs with the base URL and render video/images.
9. Use `GET /api/history?user_id=...` for the history page.
