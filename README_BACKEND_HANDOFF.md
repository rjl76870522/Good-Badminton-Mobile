# Good-Badminton 前端 → 后端交接说明

本文档由 Flutter 前端侧维护，用于说明移动端当前实际使用的后端接口、字段和联调要求。

## 1. 对接范围

- 移动端只连接根目录的 `backend_api.py`。
- 默认端口：`8001`。
- 不连接旧的 `server/main.py` 或 `8888` 端口。
- `baseUrl` 中不包含 `/api`，接口路径由 Flutter 服务层拼接。
- 当前配置文件：`frontend_flutter/lib/config/api_config.dart`。

开发环境示例：

```text
http://192.168.x.x:8001
```

Android 模拟器访问本机后端时也可以使用：

```text
http://10.0.2.2:8001
```

## 2. 前端当前流程

```text
健康检查
→ 选择视频
→ 获取预览帧
→ 自动或手动标记四个球场角点
→ 使用 source_upload_id 提交分析
→ 每 3 秒轮询任务
→ 获取报告
→ 展示指标、建议、图片和视频
→ 在历史记录中查看或删除任务
```

## 3. 当前使用的接口

### 健康检查

```http
GET /api/health
```

前端使用：

- `ok`
- `project_root`
- `default_template`

### 游客身份

```http
POST /api/users/register
Content-Type: application/json

{"user_id": "guest_xxxxxxxxxxxxxxxx"}
```

```http
GET /api/users/{user_id}
```

前端本地生成并持久化稳定的 `guest_<随机十六进制>`，上传、预览、历史和删除操作必须使用同一个 `user_id`。

用户响应格式：

```json
{
  "user": {
    "user_id": "guest_xxxxxxxxxxxxxxxx",
    "created_at": 1783324257.0,
    "updated_at": 1783324257.0
  }
}
```

### 获取预览帧

```http
POST /api/videos/preview-frame
Content-Type: multipart/form-data
```

字段：

- `file`：必填视频文件。
- `user_id`：必填游客 ID。

前端使用的响应字段：

```json
{
  "source_upload_id": "preview-id",
  "image_url": "/preview-frames/preview-id.jpg",
  "frame_index": 100,
  "time_sec": 3.3,
  "score": 0.91,
  "selection_reason": "auto_court_detected",
  "scene_ok": true,
  "scene_warning": null,
  "quality": {},
  "auto_corners": [[599, 578], [1297, 572], [1488, 994], [424, 1000]],
  "video": {
    "width": 1920,
    "height": 1080,
    "duration_sec": 35.0,
    "fps": 30.0,
    "total_frames": 1050
  }
}
```

角点顺序固定为：

```text
左上 → 右上 → 右下 → 左下
```

前端会把屏幕点击坐标换算成原始视频像素坐标。

### 上传并创建分析任务

```http
POST /api/videos/upload
Content-Type: multipart/form-data
```

字段：

- `file`：没有 `source_upload_id` 时必填。
- `source_upload_id`：预览成功后优先使用，避免重复上传视频。
- `user_id`
- `corners_json`：可选，JSON 四角点数组。
- `language=zh`
- `pose_mode=balanced`
- `keep_audio=true`

无值时前端不会发送 `"string"`、空角点或伪造模板路径。

成功响应：

```json
{
  "task_id": "task-id",
  "status": "queued",
  "status_url": "/api/tasks/task-id",
  "report_url": "/api/tasks/task-id/report"
}
```

### 查询任务

```http
GET /api/tasks/{task_id}
```

前端使用：

- `task_id`
- `user_id`
- `status`
- `progress`
- `stage`
- `error`
- `video_name`
- `created_at`
- `updated_at`
- `report_url`

状态必须是：

```text
queued | processing | completed | failed
```

`progress` 范围为 `0.0`～`1.0`。

`queued` 和 `processing` 状态下，前端每 3 秒轮询一次。网络临时中断时前端保留 `task_id` 并继续重试。

### 获取报告

```http
GET /api/tasks/{task_id}/report
```

- 未完成时返回 HTTP `202`。
- 分析失败时返回结构化错误。
- 完成时返回 `mobile-report-v1`。

前端当前支持：

- `video`
- `summary`
- `report_summary`
- `players`
- `coaching`
- `advice`
- `advice_sources`
- `files`
- `highlight_segments`
- `highlight_error`

`summary` 当前读取：

- `total_distance_m`
- `primary_player_distance_m`
- `max_speed_mps`
- `raw_max_speed_mps`
- `avg_speed_mps`
- `intensity_score`
- `detected_frames`
- `shuttlecock_frames`
- `active_time_sec`
- `distance_per_min`
- `combined_distance_per_min`
- `coverage_area_m2`
- `court_span_x_m`
- `court_span_y_m`
- `front_court_ratio`
- `back_court_ratio`
- `left_court_ratio`
- `right_court_ratio`
- `high_intensity_moves`
- `stable_position_frames`
- `dropped_jump_count`
- `tracking_quality_score`
- `shuttlecock_ratio`

训练建议优先读取：

```text
coaching.strengths
coaching.weaknesses
coaching.improvements
```

每条建议支持：

- `id`
- `title`
- `detail`
- `basis`
- `training_focus`
- `source_ids`

只有在整个 `coaching` 为空时，前端才回退展示旧字段 `advice`。

精彩片段支持：

- `start_sec`
- `end_sec`
- `score`
- `reason`
- `reason_zh`
- `tags`
- `metrics`
- `display_metrics`

### 历史记录

```http
GET /api/history?user_id={user_id}&limit=30
GET /api/history?user_id={user_id}&limit=30&status=completed
```

响应：

```json
{
  "items": [],
  "total": 0
}
```

历史卡片使用：

- 任务基础状态字段。
- `summary`
- `report_summary`
- `thumbnail`
- `files`
- `highlight_segments`

### 删除任务

```http
DELETE /api/tasks/{task_id}?user_id={user_id}
```

后端必须校验任务所属 `user_id`，并返回：

```json
{
  "ok": true,
  "task_id": "task-id",
  "deleted_paths": []
}
```

### Demo

```http
GET /api/demo/sample
```

响应必须包含顶层 `report`：

```json
{
  "source": "mock_sample",
  "task": {},
  "report": {}
}
```

## 4. 文件 URL 与媒体播放要求

`files` 中的地址必须是以 `/` 开头的相对 URL：

```json
{
  "analysis_video": "/outputs/job/analysis.mp4",
  "heatmap": "/outputs/job/heatmap.png",
  "trajectory": "/outputs/job/scatter.png",
  "highlight": "/outputs/job/highlight.mp4"
}
```

前端会使用：

```text
baseUrl + files.xxx
```

图片和视频展示前会发送 `HEAD` 检查，因此静态文件服务需要正确响应 `GET` 和 `HEAD`。

视频在 App 内通过 Flutter `video_player` 播放，后端应保证：

- HTTP 状态为 `200`。
- `Content-Type: video/mp4`。
- 支持 `Accept-Ranges: bytes`，用于拖动进度。
- 编码优先采用 H.264。
- 像素格式采用 `yuv420p`。
- 音频采用 AAC；没有音频时也必须能正常播放。
- MP4 使用 `faststart`，避免等待完整下载后才能播放。

## 5. 错误格式

非成功响应统一使用：

```json
{
  "detail": {
    "code": "VIDEO_TOO_LONG",
    "message": "视频太长，请上传 3 分钟以内的视频。",
    "hint": "请先裁剪后再上传。"
  }
}
```

前端直接向用户展示中文 `message` 和 `hint`，同时保留 `code` 用于界面分支。

任务失败后的 `error` 应说明真实原因。对于球场/球员检测不足，前端会展示重新上传和手动标记角点建议。

## 6. CORS 与网络

开发阶段后端需要：

- 监听 `0.0.0.0:8001`。
- 允许局域网设备访问。
- 配置 CORS。
- Windows 防火墙放行 TCP 8001。

启动命令：

```powershell
python -m uvicorn backend_api:app --host 0.0.0.0 --port 8001
```

真机与电脑必须处于同一网络，手机不能使用 `localhost` 或 `127.0.0.1`。

## 7. 后端交付前验收

后端负责人交付前请至少验证：

1. `/api/health` 返回 `ok=true`。
2. 同一个 `user_id` 可以完成注册、查询和历史隔离。
3. 预览响应包含有效图片、视频尺寸和角点。
4. `source_upload_id` 可以直接创建任务。
5. 状态可从 `queued/processing` 正确进入 `completed/failed`。
6. 完成报告包含 `summary`、`coaching` 和 `files`。
7. 所有返回的文件 URL 都真实存在。
8. 图片支持 `GET/HEAD`。
9. MP4 支持手机端播放和 Range 请求。
10. 删除接口不会删除其他 `user_id` 的任务。
11. 失败响应使用统一的 `detail.code/message/hint`。

## 8. 前端验证命令

```powershell
cd frontend_flutter
flutter analyze
flutter test
flutter build apk --debug
```

APK 输出位置：

```text
frontend_flutter/build/app/outputs/flutter-apk/app-debug.apk
```

当前前端仍属于游客模式，不包含登录注册、支付或云账号体系。
