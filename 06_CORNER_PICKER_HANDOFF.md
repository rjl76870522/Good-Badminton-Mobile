# Manual Court Corner Picker Handoff

This is the user-friendly replacement for manually typing `corners_json`.

## Goal

Users should not type JSON. The app should:

1. Let the user choose a video.
2. Ask the backend to select a good preview frame.
3. Show that frame with zoom and pan.
4. Let the user tap 4 court corners.
5. Convert taps to original video pixel coordinates.
6. Upload/start analysis with `corners_json`.

## Backend Flow

### 1. Create Preview Frame

```http
POST /api/videos/preview-frame
Content-Type: multipart/form-data
```

Fields:

| Field | Required | Notes |
| --- | --- | --- |
| `file` | yes | Video file |
| `user_id` | no | Stable guest/user id |

Response:

```json
{
  "source_upload_id": "1f2e3d...",
  "image_url": "/preview-frames/1f2e3d....jpg",
  "frame_index": 86,
  "time_sec": 2.86,
  "selection_reason": "auto_court_detected",
  "auto_corners": [[824,711],[1728,711],[2093,1382],[459,1382]],
  "video": {
    "width": 2560,
    "height": 1600,
    "duration_sec": 12.4,
    "fps": 30.0,
    "total_frames": 372
  }
}
```

The backend samples multiple frames and prefers frames where court lines can be auto-detected. It falls back to visual quality scoring when auto court detection fails.

### 2. Start Analysis

```http
POST /api/videos/upload
Content-Type: multipart/form-data
```

Use `source_upload_id` to avoid uploading the same video twice:

```text
source_upload_id: value from preview-frame
user_id: same user id
corners_json: [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]
language: zh
pose_mode: balanced
keep_audio: true
```

`file` is not required when `source_upload_id` is supplied.

## Corner Order

The frontend must collect points in this order:

```text
left-top, right-top, right-bottom, left-bottom
```

Chinese UI copy:

```text
左上角、右上角、右下角、左下角
```

## Coordinate Mapping

Use original video pixels, not screen pixels.

If the preview image is displayed in a widget of size `displayWidth x displayHeight`:

```text
videoX = tapX / displayWidth * video.width
videoY = tapY / displayHeight * video.height
```

Round to integers before sending:

```json
[[824,711],[1728,711],[2093,1382],[459,1382]]
```

If the image viewer supports zoom/pan, make sure tap coordinates are converted back into the image child coordinate system before applying the formula.

## Recommended UI

- Show current step: `请点选左上角`
- Show progress: `2/4`
- Support pinch zoom up to at least `16x`
- Support dragging/panning while zoomed
- Buttons:
  - `撤销`
  - `重选角点`
  - `重置缩放`
  - `使用自动识别` or reset all points
- Hide raw JSON from normal users.

## Current Flutter APK Behavior

The current Flutter app already implements:

- preview-frame upload
- backend selected preview frame
- auto-corner prefill when backend detects corners
- pinch zoom / pan
- tap 4 corners
- upload via `source_upload_id`
- automatic `corners_json` generation
