from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

BASE_DIR = Path(__file__).resolve().parent
VIDEOS_DIR = BASE_DIR / "videos"

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
        "time": "2026-07-16 19:00",
        "duration": "60分钟",
        "thumbnail": "",
        "filename": "sample_match.mp4",
    },
    {
        "id": "video002",
        "court": "2号场",
        "time": "2026-07-16 20:00",
        "duration": "45分钟",
        "thumbnail": "",
        "filename": "sample_match.mp4",
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
