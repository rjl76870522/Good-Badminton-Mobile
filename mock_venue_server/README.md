# Mock Venue Server

独立的合作球馆模拟服务。它不依赖或修改 Good-Badminton 现有后端。

## 接口

| 接口 | 说明 |
| --- | --- |
| `GET /venue` | 返回模拟球馆信息 |
| `GET /videos` | 返回模拟比赛视频列表 |
| `GET /videos/{id}/download` | 下载对应的本地测试视频 |

## 启动

```powershell
cd C:\Users\lanld\Good-Badminton
python -m pip install -r mock_venue_server\requirements.txt
python mock_venue_server\generate_sample_video.py
python -m uvicorn mock_venue_server.main:app --host 0.0.0.0 --port 9000 --reload
```

浏览器测试：

```text
http://127.0.0.1:9000/venue
http://127.0.0.1:9000/videos
http://127.0.0.1:9000/videos/video001/download
```

## 生成测试二维码

先通过 `ipconfig` 获取电脑 Wi-Fi IPv4 地址，再执行：

```powershell
python mock_venue_server\generate_qr.py 192.168.183.147
```

二维码输出为 `mock_venue_server/venue_qr.png`，内容类似：

```json
{
  "type": "venue",
  "venue_id": "SZ_BADMINTON_001",
  "venue_name": "智慧羽毛球馆",
  "server_url": "http://192.168.183.147:9000"
}
```

## Flutter 联调说明

当前 Flutter 扫码页会解析二维码并进入球馆视频库；视频列表在第一阶段仍由 Flutter 的 `VenueService` Mock 数据提供，不会改变现有上传流程。

后续接入真实球馆视频库时，只需让 `VenueService.getVideos()` 使用二维码中的 `server_url` 请求 `/videos`，下载按钮使用 `/videos/{id}/download`。请保持手机与电脑在同一 Wi-Fi，真机不能使用 `127.0.0.1` 或 `localhost`。
