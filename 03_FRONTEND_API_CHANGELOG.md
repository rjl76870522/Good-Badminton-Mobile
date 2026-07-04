# Frontend API Changelog

This note summarizes the latest backend API changes that frontend should use.

## Version

Mobile backend: `backend_api.py`

Base URL for same-Wi-Fi development:

```text
http://172.29.72.218:8001
```

Computer local testing:

```text
http://127.0.0.1:8001
```

## 1. Guest `user_id`

The upload and history APIs now support a guest/user id.

### Frontend Action

Generate one UUID on first app launch, store it locally, and reuse it.

Example:

```text
user_id = "guest_8f3a2c9e"
```

Send this `user_id` when uploading videos and when loading history.

### Upload

```http
POST /api/videos/upload
```

Multipart fields:

```text
file: video file
user_id: stable local user id
language: zh
pose_mode: balanced
keep_audio: true
```

Do not send placeholder values like `string` for optional fields.

Optional manual corners:

```text
corners_json: [[824,711],[1728,711],[2093,1382],[459,1382]]
```

The coordinates are video-frame pixel coordinates. Order: left-top, right-top, right-bottom, left-bottom. Leave it empty unless the user manually sets corners.

### History

```http
GET /api/history?user_id=guest_8f3a2c9e&limit=20
```

If `user_id` is not provided, backend defaults to:

```text
guest
```

Old test tasks are under `guest`.

## 2. Upload Limits

Backend now validates uploaded video before starting AI analysis.

| Rule | Value |
| --- | --- |
| Max file size | 500 MB |
| Minimum video duration | 5 seconds |
| Maximum video duration | 3 minutes |

### Frontend Action

Show upload guidance before selecting video:

```text
建议上传横屏固定机位视频，画面尽量覆盖完整球场。
视频建议 30 秒到 3 分钟，最大 500MB。
```

The backend still allows quick testing videos from 5 seconds upward.

## 3. Unified Error Format

Backend errors now use a stable JSON shape:

```json
{
  "detail": {
    "code": "VIDEO_TOO_LONG",
    "message": "视频太长，请上传 3 分钟以内的视频。",
    "hint": "当前服务器按短视频训练复盘优化，长视频请先裁剪。"
  }
}
```

### Frontend Action

Use:

```text
detail.message
```

as the main user-facing error message.

Optionally show:

```text
detail.hint
```

as secondary help text.

Use:

```text
detail.code
```

for conditional UI handling.

Task-level analysis failures are reported through `GET /api/tasks/{task_id}` as:

```json
{
  "status": "failed",
  "error": "未检测到有效球场/球员数据。请检查视频是否完整拍到球场，或在上传时手动填写四个球场角点。"
}
```

Show `error` directly and let the user adjust manual corners or pick another video.

## 4. Highlight Scoring

The highlight generator no longer discards shuttle speed samples above a fixed pixel-speed cap. It uses shuttle image speed, player speed, and player movement distance, then reports extra metrics such as:

```json
{
  "shuttle_peak_px_s": 2237.86,
  "shuttle_raw_peak_px_s": 3012.44,
  "shuttle_samples": 18
}
```

Frontend can display only the highlight video first; these metrics are optional debug/detail data.

## Common Error Codes

| Code | Meaning | Suggested UI |
| --- | --- | --- |
| `MISSING_VIDEO` | No video selected | Ask user to choose a video |
| `VIDEO_EMPTY` | Empty file | Ask user to reselect video |
| `VIDEO_TOO_LARGE` | Over 500 MB | Ask user to trim/compress video |
| `VIDEO_UNREADABLE` | Backend cannot read video | Ask for MP4/MOV valid file |
| `VIDEO_TOO_SHORT` | Under 5 seconds | Ask for longer video |
| `VIDEO_TOO_LONG` | Over 3 minutes | Ask user to trim video |
| `TEMPLATE_NOT_FOUND` | Bad template path | Leave `template_path` empty |
| `INVALID_CORNERS_JSON` | Bad corners JSON | Leave `corners_json` empty |
| `INVALID_CORNERS` | Corners are not 4 `[x, y]` points | Leave `corners_json` empty |
| `TASK_NOT_FOUND` | Invalid task id | Return to history/upload page |
| `ANALYSIS_NOT_READY` | Report requested too early | Keep polling task status |
| `ANALYSIS_FAILED` | AI analysis failed | Show error and allow retry |
| `HIGHLIGHT_NOT_AVAILABLE` | Highlight missing | Hide highlight player or show fallback |

## Current Endpoint List

```text
GET  /api/health
POST /api/videos/upload
GET  /api/tasks
GET  /api/history
GET  /api/tasks/{task_id}
GET  /api/tasks/{task_id}/report
GET  /api/tasks/{task_id}/highlight
GET  /api/demo/sample
```

## Recommended Frontend Flow

1. Generate/load local `user_id`.
2. Call `GET /api/health`.
3. Use `GET /api/demo/sample` to build UI without uploading.
4. Upload real video with `POST /api/videos/upload`.
5. Save `task_id`.
6. Poll `GET /api/tasks/{task_id}` until `completed` or `failed`.
7. On `completed`, call `GET /api/tasks/{task_id}/report`.
8. Play video/image files by prefixing relative file paths with `baseUrl`.
9. Use `GET /api/history?user_id=...&limit=20` for history page.

## File URL Reminder

Report file paths are relative:

```json
{
  "highlight": "/outputs/.../highlight.mp4"
}
```

Frontend should render:

```text
baseUrl + highlight
```

Example:

```text
http://172.29.72.218:8001/outputs/.../highlight.mp4
```
