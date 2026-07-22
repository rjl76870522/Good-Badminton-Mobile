from __future__ import annotations

import json
import os
import shutil
import subprocess
import uuid
from datetime import datetime
from pathlib import Path

import cv2
from fastapi import FastAPI, File, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse

BASE_DIR = Path(__file__).resolve().parent
VIDEOS_DIR = BASE_DIR / "videos"
CLIPS_DIR = BASE_DIR / "clips"
LIBRARY_PATH = BASE_DIR / "venue_library.json"
QR_IMAGE_PATH = BASE_DIR / "venue_qr.png"
COURT_COUNT = 10
ALLOWED_SUFFIXES = {".mp4", ".mov", ".m4v", ".avi"}
ALLOW_OPERATOR_UPLOADS = os.getenv("VENUE_ALLOW_UPLOADS", "").lower() == "true"
DEFAULT_COURT_RECORDINGS = {
    1: "05.mp4",
    2: "04.mp4",
    3: "03.mp4",
    4: "01.mp4",
    5: "02.mp4",
    6: "05.mp4",
    7: "04.mp4",
    8: "03.mp4",
    9: "01.mp4",
    10: "02.mp4",
}

VENUE = {
    "type": "venue",
    "venue_id": "example",
    "venue_name": "示例球场",
    "server_url": os.getenv(
        "VENUE_PUBLIC_URL",
        "https://api.audacity6441.kdns.fr/venue-demo",
    ),
}

app = FastAPI(title="Mock Venue Server", version="0.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _court_name(court_id: int) -> str:
    if not 1 <= court_id <= COURT_COUNT:
        raise HTTPException(status_code=404, detail="场地不存在")
    return f"{court_id}号场"


def _court_id(value: str) -> int:
    try:
        return int(value.replace("号场", "").strip())
    except ValueError:
        return COURT_COUNT + 1


def _default_library() -> list[dict]:
    """Provide one complete camera recording for each example court."""
    recordings: list[dict] = []
    durations: dict[str, int | None] = {}
    base_time = datetime.now().strftime("%Y-%m-%d")
    for court_id, filename in DEFAULT_COURT_RECORDINGS.items():
        if filename not in durations:
            durations[filename] = _probe_duration_seconds(VIDEOS_DIR / filename)
        duration = durations[filename]
        source_number = Path(filename).stem
        recordings.append(
            {
                "id": f"court{court_id}-full-recording",
                "court": _court_name(court_id),
                "time": f"{base_time} 录像 {source_number}",
                "duration": f"{duration} 秒" if duration is not None else "时长未知",
                "thumbnail": "",
                "filename": filename,
                "source": "camera",
            }
        )
    return recordings


def _load_uploaded_library() -> list[dict]:
    if not LIBRARY_PATH.is_file():
        return []
    try:
        data = json.loads(LIBRARY_PATH.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except (OSError, json.JSONDecodeError):
        return []


def _save_uploaded_library(items: list[dict]) -> None:
    LIBRARY_PATH.write_text(
        json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def _all_videos() -> list[dict]:
    return _default_library() + _load_uploaded_library()


def _find_video(video_id: str) -> dict:
    video = next((item for item in _all_videos() if item["id"] == video_id), None)
    if video is None:
        raise HTTPException(status_code=404, detail="视频不存在")
    return video


def _video_path(video: dict) -> Path:
    path = VIDEOS_DIR / video["filename"]
    if not path.is_file():
        raise HTTPException(status_code=404, detail="视频文件不存在")
    return path


def _probe_duration_seconds(path: Path) -> int | None:
    capture = cv2.VideoCapture(str(path))
    try:
        fps = capture.get(cv2.CAP_PROP_FPS) or 0
        frames = capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0
        return max(1, round(frames / fps)) if fps > 0 and frames > 0 else None
    finally:
        capture.release()


@app.get("/", response_class=HTMLResponse, include_in_schema=False)
def venue_portal() -> str:
    return """<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>示例球场</title><style>
body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f4f8f2;color:#173b24;font-family:"Microsoft YaHei",sans-serif}main{width:min(92vw,440px);margin:24px;padding:28px;text-align:center;border-radius:24px;background:#fff;box-shadow:0 12px 32px #1d4d2c1a}h1{margin:0 0 8px;font-size:25px}p{line-height:1.65;color:#54705c}img{width:min(72vw,280px);aspect-ratio:1;image-rendering:pixelated}.tip{padding:12px;border-radius:14px;background:#e8f5e9;color:#236838}a{display:inline-block;margin:12px 6px 0;color:#236838;font-weight:700}</style></head>
<body><main><h1>示例球场</h1><p>请用 Good-Badminton App 的“扫描合作球馆”功能扫描下方二维码。</p><img src="venue/qr.png" alt="球馆二维码"><p class="tip">每个场地保留一段完整录像，可从同一录像截取多个回合片段。</p><a href="operator">打开视频运营台</a><a href="videos">查看视频库 JSON</a></main></body></html>"""


@app.get("/operator", response_class=HTMLResponse, include_in_schema=False)
def operator_portal() -> str:
    options = "".join(f'<option value="{court}">{court}号场</option>' for court in range(1, COURT_COUNT + 1))
    return f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>示例球场 · 视频运营台</title><style>
:root{{--green:#237a3b;--ink:#173b24;--line:#dbe7dc}}*{{box-sizing:border-box}}body{{margin:0;background:#f5f8f3;color:var(--ink);font-family:"Microsoft YaHei",sans-serif}}main{{max-width:1020px;margin:auto;padding:32px 18px 64px}}header{{display:flex;justify-content:space-between;gap:16px;align-items:end;margin-bottom:24px}}h1{{margin:0;font-size:clamp(26px,5vw,38px)}}p{{color:#617563}}.grid{{display:grid;grid-template-columns:1fr 1.1fr;gap:18px}}.card{{background:#fff;border:1px solid var(--line);border-radius:22px;padding:22px;box-shadow:0 10px 24px #1d4d2c0d}}label{{display:block;margin:14px 0 7px;font-weight:700}}select,input,button{{width:100%;font:inherit;border-radius:12px;padding:12px;border:1px solid var(--line)}}button{{border:0;background:var(--green);color:#fff;font-weight:700;cursor:pointer;margin-top:12px}}button:disabled{{opacity:.5;cursor:not-allowed}}.record{{margin-top:18px;padding:14px;border-radius:14px;background:#eef4ee;display:flex;gap:10px;align-items:center}}.dot{{width:10px;height:10px;border-radius:50%;background:#a7b8a8}}.recording .dot{{background:#e34b4b;animation:pulse 1s infinite}}.recording{{background:#fff0f0}}@keyframes pulse{{50%{{transform:scale(1.5);opacity:.5}}}}.courts{{display:grid;grid-template-columns:repeat(5,1fr);gap:8px}}.court{{padding:10px 6px;text-align:center;border-radius:12px;background:#edf5ee;font-weight:700}}.video{{padding:13px 0;border-bottom:1px solid #edf1ed}}.video:last-child{{border:0}}.muted{{font-size:13px;color:#718071}}@media(max-width:720px){{.grid{{grid-template-columns:1fr}}.courts{{grid-template-columns:repeat(5,1fr)}}}}</style></head>
<body><main><header><div><h1>视频运营台</h1><p>模拟各场地摄像头录制并上传比赛视频</p></div><a href="./">返回扫码页</a></header><div class="grid"><section class="card"><h2>模拟摄像头录制</h2><form id="uploadForm"><label>选择场地</label><select id="court" name="court_id">{options}</select><label>选择录像文件</label><input id="file" name="file" type="file" accept="video/*" required><button id="record" type="button">开始模拟录制</button><button id="upload" type="submit" disabled>结束录制并上传</button></form><div id="state" class="record"><span class="dot"></span><span>摄像头待机</span></div></section><section class="card"><h2>场地概览</h2><div id="courts" class="courts"></div><h2>最近视频</h2><div id="videos" class="muted">正在加载…</div></section></div></main><script>
const state=document.querySelector('#state'),record=document.querySelector('#record'),upload=document.querySelector('#upload'),form=document.querySelector('#uploadForm'),file=document.querySelector('#file'),court=document.querySelector('#court');let timer,seconds=0;
function status(text,on=false){{state.classList.toggle('recording',on);state.querySelector('span:last-child').textContent=text}}
async function load(){{const r=await fetch('videos');const d=await r.json();const count={{}};d.items.forEach(v=>count[v.court]=(count[v.court]||0)+1);document.querySelector('#courts').innerHTML=Array.from({{length:10}},(_,i)=>`<div class="court">${{i+1}}号场<br><small>${{count[`${{i+1}}号场`]||0}} 条</small></div>`).join('');document.querySelector('#videos').innerHTML=d.items.slice(0,12).map(v=>`<div class="video"><b>${{v.court}}</b> · ${{v.time}}<br><span class="muted">${{v.duration}}</span></div>`).join('')}}
record.onclick=()=>{{if(!file.files.length){{status('请先选择一段本地录像');return}}seconds=0;record.disabled=true;upload.disabled=false;status('摄像头录制中 00:00',true);timer=setInterval(()=>{{seconds++;status(`摄像头录制中 00:${{String(seconds).padStart(2,'0')}}`,true)}},1000)}};
form.onsubmit=async e=>{{e.preventDefault();clearInterval(timer);upload.disabled=true;status('正在上传录像…',true);const data=new FormData();data.append('file',file.files[0]);const res=await fetch(`courts/${{court.value}}/videos`,{{method:'POST',body:data}});if(!res.ok){{status('上传失败，请重试');record.disabled=false;return}}status('上传完成，视频库已更新');record.disabled=false;file.value='';await load()}};load();</script></body></html>"""


@app.get("/venue/qr.png", include_in_schema=False)
def get_venue_qr() -> FileResponse:
    if not QR_IMAGE_PATH.is_file():
        raise HTTPException(status_code=404, detail="二维码不存在，请运行 generate_qr.py")
    return FileResponse(QR_IMAGE_PATH, media_type="image/png")


@app.get("/venue")
def get_venue() -> dict:
    return VENUE


@app.get("/courts")
def get_courts() -> dict:
    videos = _all_videos()
    return {
        "items": [
            {
                "id": court_id,
                "name": _court_name(court_id),
                "video_count": sum(v["court"] == _court_name(court_id) for v in videos),
            }
            for court_id in range(1, COURT_COUNT + 1)
        ]
    }


@app.get("/videos")
def get_videos(court: str | None = None) -> dict:
    items = _all_videos()
    if court:
        items = [item for item in items if item["court"] == court]
    items.sort(key=lambda item: (_court_id(item["court"]), item["time"]), reverse=False)
    return {
        "venue_id": VENUE["venue_id"],
        "items": [{key: value for key, value in item.items() if key != "filename"} for item in items],
    }


@app.post("/courts/{court_id}/videos")
async def upload_recording(court_id: int, file: UploadFile = File(...)) -> dict:
    if not ALLOW_OPERATOR_UPLOADS:
        raise HTTPException(status_code=403, detail="公网示例球场只提供录像浏览")
    court = _court_name(court_id)
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(status_code=415, detail="仅支持 MP4、MOV、M4V 或 AVI 视频")

    VIDEOS_DIR.mkdir(parents=True, exist_ok=True)
    stored_name = f"upload_{uuid.uuid4().hex}{suffix}"
    destination = VIDEOS_DIR / stored_name
    try:
        with destination.open("wb") as output:
            shutil.copyfileobj(file.file, output)
    finally:
        await file.close()

    duration = _probe_duration_seconds(destination)
    item = {
        "id": f"upload-{uuid.uuid4().hex}",
        "court": court,
        "time": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "duration": f"{duration} 秒" if duration is not None else "时长未知",
        "thumbnail": "",
        "filename": stored_name,
        "source": "operator_upload",
    }
    uploaded = _load_uploaded_library()
    uploaded.insert(0, item)
    _save_uploaded_library(uploaded)
    return {key: value for key, value in item.items() if key != "filename"}


@app.get("/videos/{video_id}/clip")
def download_clip(
    video_id: str,
    start_ms: int = Query(ge=0),
    end_ms: int = Query(gt=0),
) -> FileResponse:
    if end_ms <= start_ms:
        raise HTTPException(status_code=422, detail="结束时间必须大于开始时间")

    source = _video_path(_find_video(video_id))
    duration_seconds = _probe_duration_seconds(source)
    if duration_seconds is None:
        raise HTTPException(status_code=422, detail="视频元数据无效")
    duration_ms = duration_seconds * 1000
    if start_ms >= duration_ms:
        raise HTTPException(status_code=422, detail="开始时间超出视频范围")

    end_ms = min(end_ms, duration_ms)
    if end_ms - start_ms < 500:
        raise HTTPException(status_code=422, detail="选择的片段过短")

    CLIPS_DIR.mkdir(parents=True, exist_ok=True)
    clip_path = (
        CLIPS_DIR / f"{video_id}_{source.stem}_{start_ms}_{end_ms}.mp4"
    )
    if not clip_path.is_file():
        temporary_path = clip_path.with_name(
            f"{clip_path.stem}.{uuid.uuid4().hex}.tmp.mp4"
        )
        command = [
            "ffmpeg",
            "-y",
            "-ss",
            f"{start_ms / 1000:.3f}",
            "-i",
            str(source),
            "-t",
            f"{(end_ms - start_ms) / 1000:.3f}",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "20",
            "-c:a",
            "aac",
            "-movflags",
            "+faststart",
            str(temporary_path),
        ]
        try:
            subprocess.run(
                command,
                check=True,
                capture_output=True,
                timeout=180,
            )
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            temporary_path.unlink(missing_ok=True)
            raise HTTPException(status_code=500, detail="生成视频片段失败")
        if not temporary_path.is_file() or temporary_path.stat().st_size == 0:
            temporary_path.unlink(missing_ok=True)
            raise HTTPException(status_code=500, detail="生成视频片段失败")
        try:
            temporary_path.replace(clip_path)
        finally:
            temporary_path.unlink(missing_ok=True)

    return FileResponse(clip_path, media_type="video/mp4", filename=f"{video_id}_{start_ms}_{end_ms}.mp4")


@app.get("/videos/{video_id}/download")
def download_video(video_id: str) -> FileResponse:
    file_path = _video_path(_find_video(video_id))
    return FileResponse(file_path, media_type="video/mp4", filename=f"{video_id}.mp4")
