# Good-Badminton Flutter App

这是对接 `backend_api.py` Mobile API 的最小 Flutter 客户端。它不使用旧的
`server/main.py` 接口。

## 1. 环境准备

安装 Flutter SDK 和 Android Studio，然后检查环境：

```powershell
flutter doctor
```

本仓库创建客户端时，开发电脑的 PATH 中没有 Flutter SDK，因此首次拉取后如果
`frontend_flutter/android` 缺少 Gradle 包装器或其他平台模板文件，请在本目录执行：

```powershell
cd C:\Users\lanld\Good-Badminton\frontend_flutter
flutter create . --platforms=android
```

执行后确认
`android/app/src/main/AndroidManifest.xml` 仍包含：

```xml
<uses-permission android:name="android.permission.INTERNET" />
android:usesCleartextTraffic="true"
```

## 2. 启动后端

在项目根目录运行：

```powershell
cd C:\Users\lanld\Good-Badminton
python -m uvicorn backend_api:app --host 0.0.0.0 --port 8001
```

也可以双击：

```text
start_mobile_backend.bat
```

电脑浏览器访问以下地址确认后端运行：

```text
http://127.0.0.1:8001/api/health
http://127.0.0.1:8001/docs
```

## 3. 后端访问地址

默认通过 Cloudflare Tunnel 访问 Ubuntu 后端：

```text
https://api.audacity6441.kdns.fr
```

本机调试仍然可以使用：

```text
http://127.0.0.1:8001
```

如果不用 Cloudflare Tunnel，而是同一 Wi-Fi 联调，手机必须访问电脑的局域网 IPv4，
不能使用 `localhost` 或 `127.0.0.1`。

## 4. 配置后端 baseUrl

默认后端地址定义在：

```text
lib/config/api_config.dart
```

当前值：

```dart
static const String _defaultBaseUrl = 'https://api.audacity6441.kdns.fr';
```

构建或运行时也可以覆盖地址，不需要改源码：

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8001
flutter build apk --release --dart-define=API_BASE_URL=https://api.audacity6441.kdns.fr
```

项目其他文件不重复写死后端地址。

## 5. 运行 App

连接 Android 真机并打开 USB 调试，随后执行：

```powershell
cd C:\Users\lanld\Good-Badminton\frontend_flutter
flutter pub get
flutter devices
flutter run
```

如果手机无法连接后端：

1. 在手机浏览器打开 `https://api.audacity6441.kdns.fr/api/health`。
2. 确认后端使用 `--host 0.0.0.0 --port 8001` 启动。
3. 确认 Cloudflare Tunnel 正在运行，并把 `api.audacity6441.kdns.fr` 转发到 `http://127.0.0.1:8001`。
4. 如果改用同 Wi-Fi 地址，确认 `API_BASE_URL` 是电脑当前 WLAN IPv4 地址。

## 6. 功能测试

1. 启动 `backend_api.py` Mobile API。
2. 打开 App。
3. 点击“测试后端连接”，确认显示 `ok`、`project_root` 和
   `default_template`。
4. 点击“上传视频”。
5. 选择一个 5 秒到 3 分钟的本地视频。
6. 等待 App 调用预览接口，并在预览图上确认或重新选四个球场角点。
7. 点击“上传视频”；App 优先使用 `source_upload_id`，不会重复上传视频。
8. 后端返回 `task_id` 后，App 每 3 秒查询一次任务状态。
9. 等待状态变成 `completed`，点击“查看报告”。
10. 确认 summary、coaching、精彩片段和结果媒体可以显示。
11. 确认图片和视频使用 `baseUrl + 相对路径` 加载。
12. 返回首页查看按本机游客 ID 隔离的历史记录和训练档案。

早期联调建议使用 8 秒到 1 分钟的低分辨率视频，避免长时间等待模型推理。

## 7. 当前接口

- `GET /api/health`
- `POST /api/videos/preview-frame`
- `POST /api/videos/upload`
- `GET /api/tasks/{task_id}`
- `GET /api/tasks/{task_id}/report`
- `GET /api/history?user_id=xxx&limit=30`
- `GET /api/demo/sample`

预览请求发送 `file` 和稳定的本地 `user_id`。上传表单发送：

- `file` 或预览接口返回的 `source_upload_id`
- `user_id`
- 可选的 `corners_json`
- `language=zh`
- `pose_mode=balanced`
- `keep_audio=true`

没有实际值时不会发送 `template_path`、`corners_json` 等占位字符串。

## 8. 任务恢复与失败重试

- 上传成功后，App 会在本地保存当前 `task_id` 和视频缓存路径。
- App 重启时会向后端重新查询该任务。
- `queued` 或 `processing` 任务会在首页显示“发现未完成任务”，点击后继续轮询。
- `completed` 任务会清理本地恢复信息。
- `failed` 任务会保留原视频路径，任务页和历史页可进入“重新上传”。
- 如果系统已经清理了原视频缓存，App 会提示重新选择视频。
- 历史页支持全部、排队中、分析中、已完成、失败状态筛选。

## 9. 报告文件检查

前端在显示报告图片和视频链接前，会检查后端文件 URL：

- HTTP 2xx：显示图片或文件链接。
- URL 为空：显示“暂无文件”。
- 文件返回 404 或网络异常：显示“文件未生成或已失效”。

该检查用于避免展示破损图片和无效视频链接，不会修改后端报告数据。

## 10. 视频上传限制

选择视频后，App 会在上传前读取并检查：

```text
格式：MP4、MOV、M4V
大小：不超过 200 MB
时长：5 秒～3 分钟（推荐一个完整回合，并去掉休息片段）
元数据读取：最长等待 20 秒
```

不符合要求时会显示具体原因并禁用上传按钮。限制统一定义在：

```text
lib/config/upload_constraints.dart
```

修改产品限制时只需调整该文件，并同步后端校验规则。

## 11. UI 说明

- 首页提供功能引导和后端连接状态。
- 上传页显示视频要求、格式、大小、时长和检查结果。
- 角点页支持自动角点、四点重选、坐标换算和跳过手动角点。
- 任务页使用状态卡、百分比和进度条展示分析进度。
- 临时断网时任务页保留 `task_id` 并自动继续轮询。
- 历史页按游客 ID 查询，展示缩略图、摘要并支持失败任务重试。
- 报告页优先展示 `coaching`，旧 `advice` 仅作为兼容回退。
