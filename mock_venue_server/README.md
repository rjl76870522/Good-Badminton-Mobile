# 模拟球馆服务

`mock_venue_server` 是独立的合作球馆模拟服务，用于联调 Flutter 的“扫码 → 选择场地 → 选择视频 → 截取 / 保存 / 分析”流程。它不修改 Good-Badminton 的主后端、算法或数据库。

生产演示入口通过主 API 的只读子路径提供：

```text
https://api.audacity6441.kdns.fr/venue-demo
```

手机 App 直接使用该地址读取场地和录像。公网入口禁止上传；只有 Ubuntu
本机运行的运营台允许添加完整录像。

## 本次更新：10 场地视频运营模拟

- 智慧羽毛球馆现在有 **1～10 号场**。
- 每块场地默认有 2 条模拟摄像头录像，共 20 条视频；默认录像复用仓库内的两段小样本，不复制大文件。
- 新增视频运营台网页：选择场地、本地录像文件，点击“开始模拟录制”，再点击“结束录制并上传”。
- 上传记录会保存到本机 `venue_library.json`，刷新 Flutter 视频库即可显示新增录像。
- Flutter 球馆视频库支持“全部 / 1～10 号场”筛选，避免长列表堆叠。
- App 视频详情页支持选择时间范围；保存片段到系统相册或把片段带入现有分析流程。

> 片段由本模拟服务使用 FFmpeg 重新编码，原视频包含音轨时会保留声音。

## 页面

| 页面 | 地址 | 用途 |
| --- | --- | --- |
| 扫码页 | `http://127.0.0.1:9000/` | 显示球馆二维码，供 Flutter App 扫描。 |
| 视频运营台 | `http://127.0.0.1:9000/operator` | 向 1～10 号场模拟上传摄像头录像。 |
| 视频库 JSON | `http://127.0.0.1:9000/videos` | 查看所有场地视频数据。 |
| 场地统计 JSON | `http://127.0.0.1:9000/courts` | 查看每块场地的视频数量。 |

手机真机不能访问 `127.0.0.1`。同一 Wi-Fi 联调时，请将地址中的 `127.0.0.1` 替换为电脑 WLAN IPv4，例如 `http://192.168.0.29:9000/operator`。

## API

| 接口 | 说明 |
| --- | --- |
| `GET /venue` | 返回球馆信息。 |
| `GET /courts` | 返回 10 块场地及各自的视频数量。 |
| `GET /videos` | 返回全部比赛视频。 |
| `GET /videos?court=1号场` | 返回指定场地的视频。 |
| `POST /courts/{court_id}/videos` | 以 `multipart/form-data` 上传 `file` 到指定场地。支持 MP4、MOV、M4V、AVI。 |
| `GET /videos/{id}/download` | 下载完整视频。 |
| `GET /videos/{id}/clip?start_ms=1000&end_ms=4000` | 生成并下载指定时间段 MP4 片段。 |

## 启动

Ubuntu 服务器：

```bash
sudo cp deploy/good-badminton-venue.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now good-badminton-venue.service
```

本机访问 `http://127.0.0.1:9000/operator`。手机联调时，使用与手机可互通的
Ubuntu 地址重新生成二维码：

```bash
.venv/bin/python mock_venue_server/generate_qr.py 你的局域网IP
```

Windows：

```powershell
cd C:\Users\lanld\Good-Badminton
python -m pip install -r mock_venue_server\requirements.txt
python -m uvicorn mock_venue_server.main:app --host 0.0.0.0 --port 9000
```

或双击：

```text
mock_venue_server\start_local_mock_venue_server.bat
```

停止脚本管理的服务：

```text
mock_venue_server\stop_mock_venue_server.bat
```

## 二维码

先查看电脑 WLAN 的 IPv4：

```powershell
ipconfig
```

然后生成供同一 Wi-Fi 手机扫描的二维码：

```powershell
python mock_venue_server\generate_qr.py 192.168.0.29
```

二维码输出为 `mock_venue_server/venue_qr.png`。每次电脑 IP 改变后，应重新生成二维码；Windows 防火墙也需要允许 9000 端口。

## Flutter 联调步骤

1. 启动模拟球馆服务。
2. 打开扫码页，刷新后确认二维码是当前电脑局域网地址。
3. 手机与电脑连接同一个 Wi-Fi，使用 App 扫码进入球馆视频库。
4. 选择 1～10 号场之一，再选择录像进行预览、截取或分析。
5. 在运营台选择场地和本地视频，模拟录制并上传。
6. 返回 App 视频库并重新扫码 / 刷新，即可看到新增录像。

`venue_library.json`、生成片段和运营台上传的视频都属于本机运行数据，已被 Git 忽略。
