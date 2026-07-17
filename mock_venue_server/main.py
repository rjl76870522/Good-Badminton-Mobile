from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse

BASE_DIR = Path(__file__).resolve().parent
VIDEOS_DIR = BASE_DIR / "videos"
QR_IMAGE_PATH = BASE_DIR / "venue_qr.png"

VENUE = {
    "type": "venue",
    "venue_id": "SZ_BADMINTON_001",
    "venue_name": "智慧羽毛球馆",
    "server_url": "http://电脑IP:9000",
}

VIDEOS = [
    {
        "id": "video001",
        "court": "1号场",
        "time": "实训视频 A",
        "duration": "35 秒",
        "thumbnail": "",
        "filename": "shiyuqi_10_45.mp4",
    },
    {
        "id": "video002",
        "court": "2号场",
        "time": "实训视频 B",
        "duration": "10 秒",
        "thumbnail": "",
        "filename": "shiyuqi_test.mp4",
    },
]

app = FastAPI(title="Mock Venue Server", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", response_class=HTMLResponse, include_in_schema=False)
def venue_portal() -> str:
    """Show a browser-friendly landing page for QR-code testing."""
    return """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>智慧羽毛球馆 · 模拟服务</title>
  <style>
    body { margin: 0; min-height: 100vh; display: grid; place-items: center;
      background: #f4f8f2; color: #173b24; font-family: "Microsoft YaHei", sans-serif; }
    main { width: min(92vw, 440px); margin: 24px; padding: 28px; text-align: center;
      border-radius: 24px; background: #fff; box-shadow: 0 12px 32px #1d4d2c1a; }
    h1 { margin: 0 0 8px; font-size: 25px; }
    p { line-height: 1.65; color: #54705c; }
    img { width: min(72vw, 280px); aspect-ratio: 1; image-rendering: pixelated; }
    .tip { padding: 12px; border-radius: 14px; background: #e8f5e9; color: #236838; }
    a { display: inline-block; margin: 12px 6px 0; color: #236838; font-weight: 700; }
  </style>
</head>
<body>
  <main>
    <h1>智慧羽毛球馆</h1>
    <p>请用 Good-Badminton App 的“扫描球馆二维码”功能扫描下方二维码。</p>
    <img src="/venue/qr.png" alt="球馆二维码">
    <p class="tip">公网模式下，手机无需与电脑连接同一 Wi-Fi。</p>
    <a href="/venue">查看球馆 JSON</a>
    <a href="/videos">查看视频库 JSON</a>
  </main>
</body>
</html>"""


@app.get("/venue/qr.png", include_in_schema=False)
def get_venue_qr() -> FileResponse:
    """Serve the generated venue QR code inside the browser portal."""
    if not QR_IMAGE_PATH.is_file():
        raise HTTPException(status_code=404, detail="二维码不存在，请运行 generate_qr.py")
    return FileResponse(QR_IMAGE_PATH, media_type="image/png")


@app.get("/venue")
def get_venue() -> dict:
    """Return the simulated partner venue information."""
    return VENUE


@app.get("/videos")
def get_videos() -> dict:
    """Return the simulated match-video library without local file paths."""
    return {
        "venue_id": VENUE["venue_id"],
        "items": [
            {key: value for key, value in video.items() if key != "filename"}
            for video in VIDEOS
        ],
    }


@app.get("/videos/{video_id}/download")
def download_video(video_id: str) -> FileResponse:
    """Download a matching local test video."""
    video = next((item for item in VIDEOS if item["id"] == video_id), None)
    if video is None:
        raise HTTPException(status_code=404, detail="视频不存在")

    file_path = VIDEOS_DIR / video["filename"]
    if not file_path.is_file():
        raise HTTPException(
            status_code=404,
            detail="测试视频不存在，请运行 generate_sample_video.py",
        )
    return FileResponse(
        file_path,
        media_type="video/mp4",
        filename=f"{video_id}.mp4",
    )
