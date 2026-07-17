# Mock Venue Server

独立的合作球馆模拟服务。它不依赖或修改 Good-Badminton 现有后端。

## 接口

| 接口 | 说明 |
| --- | --- |
| `GET /venue` | 返回模拟球馆信息 |
| `GET /videos` | 返回模拟比赛视频列表 |
| `GET /videos/{id}/download` | 下载对应的本地测试视频 |

## 一键公网启动 / 关闭（Windows）

双击或在项目根目录执行：

```powershell
.\mock_venue_server\start_mock_venue_server.bat
```

该脚本会自动启动本地服务、通过 HTTP/2 创建临时 Cloudflare HTTPS 公网地址、重新生成二维码，
并在浏览器中打开二维码页面。手机不需要和电脑连接同一 Wi-Fi。脚本运行期间会显示
公网地址；请保持服务与隧道都运行。关闭时执行：

```powershell
.\mock_venue_server\stop_mock_venue_server.bat
```

如果浏览器偶尔提示 `ERR_CONNECTION_CLOSED`，等待 5 秒后刷新一次即可；Quick Tunnel
重连期间会短暂不可访问。每次重启都必须使用新生成的二维码，旧的 `trycloudflare.com` 地址会失效。

如果只想在同一 Wi-Fi 下进行本地联调，可使用备用脚本：

```powershell
.\mock_venue_server\start_local_mock_venue_server.bat
```

启动后可以直接打开下面的网页，页面会显示二维码，方便手机扫码：

```text
http://127.0.0.1:9000/
```

> 若之前是用终端手动启动的 Uvicorn，请在该终端按 `Ctrl+C` 关闭；停止脚本只管理由启动脚本创建的进程。

## 手动启动

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

公网启动脚本会自动完成 Quick Tunnel 和二维码生成。Quick Tunnel 的地址会在每次重启后变化，
只适合联调和演示；需要稳定地址时，应使用已配置域名的 Named Tunnel。

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
