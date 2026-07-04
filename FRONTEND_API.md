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
  "project_root": "D:\\py\\Good-Badminton",
  "default_template": "D:\\py\\Good-Badminton\\templates\\badminton_template.png"
}
```

## Upload Video

```http
POST /api/videos/upload
Content-Type: multipart/form-data
```

Fields:

| Name | Required | Value |
| --- | --- | --- |
| `file` | yes | video file |
| `user_id` | no | stable guest/user id, default `guest` |
| `template_path` | no | leave empty, or use `templates/badminton_template.png` |
| `corners_json` | no | leave empty, or JSON like `[[824,711],[1728,711],[2093,1382],[459,1382]]` |
| `language` | no | `zh` or `en`, default `zh` |
| `pose_mode` | no | `lightweight`, `balanced`, or `performance`, default `balanced` |
| `keep_audio` | no | `true` or `false`, default `true` |

Do not send Swagger's placeholder value `string` for `template_path` or `corners_json`.

`corners_json` uses video-frame pixel coordinates, not screen CSS coordinates. The order is:

```text
left-top, right-top, right-bottom, left-bottom
```

If the user does not set manual corners, omit `corners_json` or send it as an empty value.

For guest mode, the app should generate one UUID, store it locally, and send it as `user_id` on uploads and history queries.

Current upload limits:

| Rule | Value |
| --- | --- |
| Max file size | 500 MB |
| Minimum duration | 5 seconds |
| Maximum duration | 3 minutes |

Recommended UI copy: use horizontal fixed-camera video; keep the full court visible; use 30 seconds to 3 minutes for real training reports.

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

If analysis cannot detect useful court/player frames, the task becomes `failed` and `error` contains the user-facing reason. Show that message and allow the user to retry with manual corners.

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
        "shuttle_raw_peak_px_s": 3012.44,
        "shuttle_samples": 18,
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
GET /api/history?user_id=guest&limit=20
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

## Error Format

API errors use a stable `detail.code` for UI handling:

```json
{
  "detail": {
    "code": "VIDEO_TOO_LONG",
    "message": "视频太长，请上传 3 分钟以内的视频。",
    "hint": "当前服务器按短视频训练复盘优化，长视频请先裁剪。"
  }
}
```

Common codes:

| Code | Meaning |
| --- | --- |
| `MISSING_VIDEO` | No video file was selected |
| `VIDEO_EMPTY` | Uploaded file is empty |
| `VIDEO_TOO_LARGE` | File exceeds 500 MB |
| `VIDEO_UNREADABLE` | OpenCV cannot read the video |
| `VIDEO_TOO_SHORT` | Video is under 5 seconds |
| `VIDEO_TOO_LONG` | Video is over 3 minutes |
| `TEMPLATE_NOT_FOUND` | Provided `template_path` does not exist |
| `INVALID_CORNERS_JSON` | `corners_json` is not valid JSON |
| `INVALID_CORNERS` | Corner array does not contain four `[x, y]` points |
| `TASK_NOT_FOUND` | Task id is invalid |
| `ANALYSIS_NOT_READY` | Report requested before completion |
| `ANALYSIS_FAILED` | Analysis failed |
| `HIGHLIGHT_NOT_AVAILABLE` | Highlight video is missing |

## Recommended App Flow

1. Open app and call `GET /api/health`.
2. Generate or load a local guest `user_id`.
3. Upload a video with `POST /api/videos/upload`.
4. Save `task_id`.
5. Poll `GET /api/tasks/{task_id}` until `completed` or `failed`.
6. On `completed`, call `GET /api/tasks/{task_id}/report`.
7. Prefix file URLs with the base URL and render video/images.
8. Use `GET /api/history` for the history page.
