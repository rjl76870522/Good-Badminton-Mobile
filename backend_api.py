"""FastAPI backend for a mobile Good-Badminton demo loop.

Run from the project root:

    uvicorn backend_api:app --host 0.0.0.0 --port 8001
"""

from __future__ import annotations

import json
import math
import os
import threading
import time
import uuid
from pathlib import Path
from typing import Any

from fastapi import BackgroundTasks, FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

PROJECT_ROOT = Path(__file__).resolve().parent
UPLOAD_DIR = PROJECT_ROOT / "mobile_backend_data" / "uploads"
TASK_DIR = PROJECT_ROOT / "mobile_backend_data" / "tasks"
PREVIEW_DIR = PROJECT_ROOT / "mobile_backend_data" / "previews"
SOURCE_DIR = PROJECT_ROOT / "mobile_backend_data" / "sources"
OUTPUTS_DIR = PROJECT_ROOT / "outputs"
MAX_UPLOAD_BYTES = 500 * 1024 * 1024
ALLOWED_VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v"}
COPY_CHUNK_BYTES = 1024 * 1024
DEFAULT_TEMPLATE_CANDIDATES = [
    PROJECT_ROOT / "templates" / "badminton_template.png",
    PROJECT_ROOT / "templates" / "my_template.png",
    PROJECT_ROOT / "templates" / "demo.png",
]

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
TASK_DIR.mkdir(parents=True, exist_ok=True)
PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
SOURCE_DIR.mkdir(parents=True, exist_ok=True)
OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Good-Badminton Mobile Backend", version="0.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/outputs", StaticFiles(directory=str(OUTPUTS_DIR)), name="outputs")

TASKS: dict[str, dict[str, Any]] = {}
TASKS_LOCK = threading.Lock()
ANALYSIS_LOCK = threading.Lock()


@app.get("/api/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "good-badminton-mobile-backend",
        "version": app.version,
    }


@app.post("/api/videos/preview-frame")
def preview_video_frame(
    file: UploadFile = File(...),
    user_id: str = Form(default=""),
) -> dict[str, Any]:
    """Store a video once and return a representative frame for court marking."""
    source_upload_id = uuid.uuid4().hex
    safe_name = _validate_video_filename(file.filename)
    upload_path = UPLOAD_DIR / f"{source_upload_id}_{safe_name}"
    try:
        size = _save_upload(file, upload_path)
        preview = _extract_preview_frame(upload_path, source_upload_id)
    except Exception:
        upload_path.unlink(missing_ok=True)
        (PREVIEW_DIR / f"{source_upload_id}.jpg").unlink(missing_ok=True)
        raise
    finally:
        file.file.close()

    source = {
        "source_upload_id": source_upload_id,
        "user_id": user_id.strip(),
        "video_name": safe_name,
        "upload_path": str(upload_path),
        "size": size,
        "created_at": time.time(),
        "preview": preview,
    }
    _write_json_atomic(SOURCE_DIR / f"{source_upload_id}.json", source)
    return {key: value for key, value in preview.items() if key != "image_path"}


@app.get("/api/videos/preview-images/{source_upload_id}")
def get_preview_image(source_upload_id: str) -> FileResponse:
    source = _get_source_or_404(source_upload_id)
    preview_path = Path(source["preview"]["image_path"])
    if not preview_path.is_file():
        raise HTTPException(status_code=404, detail="Preview image not found.")
    return FileResponse(str(preview_path), media_type="image/jpeg")


@app.post("/api/videos/upload")
def upload_video(
    background_tasks: BackgroundTasks,
    file: UploadFile | None = File(default=None),
    source_upload_id: str | None = Form(default=None),
    user_id: str = Form(default=""),
    template_path: str | None = Form(default=None),
    corners_json: str | None = Form(default=None),
    language: str = Form(default="zh"),
    pose_mode: str = Form(default="balanced"),
    keep_audio: bool = Form(default=True),
) -> dict[str, Any]:
    template = _resolve_template(template_path)
    corners = _parse_corners(corners_json)
    task_id = uuid.uuid4().hex
    normalized_user_id = user_id.strip()
    source_id = (source_upload_id or "").strip()
    if source_id:
        if file is not None:
            raise HTTPException(
                status_code=400,
                detail="Send either file or source_upload_id, not both.",
            )
        source = _get_source_or_404(source_id)
        source_user_id = str(source.get("user_id") or "")
        if source_user_id and source_user_id != normalized_user_id:
            raise HTTPException(status_code=403, detail="Source upload belongs to another user.")
        safe_name = str(source["video_name"])
        upload_path = Path(source["upload_path"])
        if not upload_path.is_file():
            raise HTTPException(status_code=410, detail="Source video is no longer available.")
    else:
        if file is None:
            raise HTTPException(status_code=400, detail="A video file is required.")
        safe_name = _validate_video_filename(file.filename)
        upload_path = UPLOAD_DIR / f"{task_id}_{safe_name}"
        try:
            _save_upload(file, upload_path)
        finally:
            file.file.close()

    task = {
        "task_id": task_id,
        "status": "queued",
        "progress": 0.0,
        "stage": "queued",
        "error": None,
        "user_id": normalized_user_id,
        "source_upload_id": source_id or None,
        "video_name": safe_name,
        "upload_path": str(upload_path),
        "template_path": str(template),
        "created_at": time.time(),
        "updated_at": time.time(),
        "report": None,
    }
    _set_task(task_id, task)

    background_tasks.add_task(
        _run_analysis_task,
        task_id=task_id,
        video_path=str(upload_path),
        template_path=str(template),
        corners=corners,
        language=language,
        pose_mode=pose_mode,
        keep_audio=keep_audio,
    )

    return {
        "task_id": task_id,
        "status": "queued",
        "status_url": f"/api/tasks/{task_id}",
        "report_url": f"/api/tasks/{task_id}/report",
    }


@app.get("/api/tasks")
def list_tasks() -> dict[str, Any]:
    tasks = _load_all_tasks()
    tasks.sort(key=lambda item: item["created_at"], reverse=True)
    return {"tasks": [_public_task(t) for t in tasks]}


@app.get("/api/history")
def get_history(
    user_id: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    status: str | None = Query(default=None),
) -> dict[str, Any]:
    tasks = _load_all_tasks()
    if user_id:
        tasks = [task for task in tasks if task.get("user_id") == user_id]
    if status:
        tasks = [task for task in tasks if task.get("status") == status]
    tasks.sort(key=lambda item: item.get("created_at", 0), reverse=True)
    return {
        "items": [_history_item(task) for task in tasks[:limit]],
        "total": len(tasks),
    }


@app.get("/api/tasks/{task_id}")
def get_task(task_id: str) -> dict[str, Any]:
    task = _get_task_or_404(task_id)
    return _public_task(task)


@app.get("/api/tasks/{task_id}/report")
def get_report(task_id: str) -> dict[str, Any]:
    task = _get_task_or_404(task_id)
    if task["status"] == "failed":
        raise HTTPException(status_code=409, detail=task["error"] or "Analysis failed.")
    if task["status"] != "completed" or not task.get("report"):
        raise HTTPException(status_code=202, detail="Analysis is not completed yet.")
    return task["report"]


@app.get("/api/tasks/{task_id}/highlight")
def get_highlight(task_id: str) -> FileResponse:
    task = _get_task_or_404(task_id)
    report = task.get("report") or {}
    files = report.get("files") or {}
    highlight_url = files.get("highlight")
    highlight_path = _output_url_to_path(highlight_url)
    if highlight_path is None or not highlight_path.is_file():
        raise HTTPException(status_code=404, detail="Highlight video is not available.")
    return FileResponse(str(highlight_path), media_type="video/mp4")


@app.get("/api/demo/sample")
def get_demo_sample() -> dict[str, Any]:
    tasks = [
        task for task in _load_all_tasks()
        if task.get("status") == "completed" and task.get("report")
    ]
    tasks.sort(key=lambda item: item.get("updated_at", item.get("created_at", 0)), reverse=True)
    if tasks:
        return {
            "source": "latest_completed_task",
            "task": _history_item(tasks[0]),
            "report": tasks[0]["report"],
        }
    return {
        "source": "mock_sample",
        "task": {
            "task_id": "demo_sample",
            "status": "completed",
            "progress": 1.0,
            "stage": "completed",
            "error": None,
            "video_name": "demo_sample.mp4",
            "created_at": None,
            "updated_at": None,
            "report_url": "/api/demo/sample",
        },
        "report": _mock_demo_report(),
    }


def _run_analysis_task(
    *,
    task_id: str,
    video_path: str,
    template_path: str,
    corners: list[list[int]] | None,
    language: str,
    pose_mode: str,
    keep_audio: bool,
) -> None:
    from badminton_analysis.highlight import generate_highlight
    from webui.pipeline import prepare_court, run_analysis

    with ANALYSIS_LOCK:
        try:
            _update_task(task_id, status="processing", stage="preparing_court", progress=0.02)
            if corners is None:
                court = prepare_court(template_path)
                corners = court.get("corners")
            if not corners or len(corners) != 4:
                raise RuntimeError("Could not resolve court corners from the template.")

            options = {
                "pose_family": "yolo-pose",
                "pose_mode": pose_mode,
                "language": language,
                "audio": keep_audio,
                "show_skeletons": True,
                "show_player_trajectories": True,
                "show_court_trajectory": True,
                "show_shuttlecock_trajectory": True,
                "show_player_stats": True,
                "show_pose_roi": True,
                "visualize_positions": True,
                "yolo_pose_model": "weights/yolo11n-pose.pt",
                "ball_model": "weights/yolo11s-ball.pt",
            }

            def progress_cb(frame: int, total: int) -> None:
                ratio = frame / total if total else 0.0
                _update_task(
                    task_id,
                    status="processing",
                    stage="analyzing_video",
                    progress=round(0.05 + ratio * 0.85, 4),
                )

            result = run_analysis(
                video_path=video_path,
                template_path=template_path,
                corners=corners,
                options=options,
                progress_cb=progress_cb,
            )

            _update_task(task_id, stage="building_highlight", progress=0.92)
            highlight = generate_highlight(
                video_path=result.get("video") or video_path,
                detections_path=result.get("detections"),
                output_dir=result.get("output_dir") or OUTPUTS_DIR,
            )
            result["highlight"] = highlight.get("video")
            result["highlight_segments"] = highlight.get("segments", [])
            result["highlight_error"] = highlight.get("error")

            _update_task(task_id, stage="building_report", progress=0.96)
            report = _build_report_with_urls(task_id, result)
            _update_task(
                task_id,
                status="completed",
                stage="completed",
                progress=1.0,
                report=report,
                output_dir=result.get("output_dir"),
            )
        except Exception as exc:
            _update_task(
                task_id,
                status="failed",
                stage="failed",
                progress=1.0,
                error=str(exc),
            )


def _build_report_with_urls(task_id: str, result: dict[str, Any]) -> dict[str, Any]:
    from badminton_analysis.mobile_report import build_mobile_report

    report = build_mobile_report(result=result)
    files = {
        "analysis_video": _path_to_output_url(result.get("video")),
        "highlight": _path_to_output_url(result.get("highlight")),
        "metadata": _path_to_output_url(result.get("metadata")),
        "detections": _path_to_output_url(result.get("detections")),
        "visualizations": [_path_to_output_url(p) for p in result.get("visualizations", [])],
    }
    files["heatmap"] = _first_matching(files["visualizations"], "heatmap")
    files["trajectory"] = _first_matching(files["visualizations"], "scatter")
    report.update(
        {
            "task_id": task_id,
            "status": "completed",
            "files": files,
            "highlight_segments": result.get("highlight_segments", []),
            "highlight_error": result.get("highlight_error"),
        }
    )
    return report


def _path_to_output_url(path: str | os.PathLike[str] | None) -> str | None:
    if not path:
        return None
    p = Path(path)
    if not p.is_absolute():
        p = PROJECT_ROOT / p
    try:
        rel = p.resolve().relative_to(OUTPUTS_DIR.resolve())
    except ValueError:
        return None
    return "/outputs/" + rel.as_posix()


def _output_url_to_path(url: str | None) -> Path | None:
    if not url or not url.startswith("/outputs/"):
        return None
    rel = url.removeprefix("/outputs/").replace("/", os.sep)
    return OUTPUTS_DIR / rel


def _first_matching(urls: list[str | None], needle: str) -> str | None:
    for url in urls:
        if url and needle.lower() in url.lower():
            return url
    return None


def _public_task(task: dict[str, Any]) -> dict[str, Any]:
    return {
        "task_id": task["task_id"],
        "user_id": task.get("user_id", ""),
        "status": task["status"],
        "progress": task["progress"],
        "stage": task["stage"],
        "error": task["error"],
        "video_name": task["video_name"],
        "created_at": task["created_at"],
        "updated_at": task["updated_at"],
        "report_url": f"/api/tasks/{task['task_id']}/report",
    }


def _history_item(task: dict[str, Any]) -> dict[str, Any]:
    public = _public_task(task)
    report = task.get("report") or {}
    files = report.get("files") or {}
    public.update(
        {
            "summary": report.get("summary"),
            "video": report.get("video"),
            "thumbnail": files.get("heatmap") or files.get("trajectory"),
            "files": {
                "analysis_video": files.get("analysis_video"),
                "heatmap": files.get("heatmap"),
                "trajectory": files.get("trajectory"),
                "highlight": files.get("highlight"),
            },
        }
    )
    return public


def _load_all_tasks() -> list[dict[str, Any]]:
    tasks_by_id: dict[str, dict[str, Any]] = {}
    for snapshot in TASK_DIR.glob("*.json"):
        try:
            with snapshot.open("r", encoding="utf-8") as f:
                task = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        task_id = task.get("task_id")
        if task_id:
            tasks_by_id[task_id] = task

    with TASKS_LOCK:
        tasks_by_id.update(TASKS)

    return list(tasks_by_id.values())


def _mock_demo_report() -> dict[str, Any]:
    return {
        "schema_version": "mobile-report-v1",
        "video": {
            "name": "demo_sample",
            "duration_sec": 60.0,
            "fps": 30.0,
            "width": 1920,
            "height": 1080,
        },
        "summary": {
            "total_distance_m": 438.0,
            "max_speed_mps": 4.8,
            "avg_speed_mps": 1.6,
            "intensity_score": 82,
            "detected_frames": 1800,
            "shuttlecock_frames": 960,
        },
        "players": [],
        "advice": [
            "本次训练爆发性移动明显，建议加强连续多拍后的恢复能力。",
            "可结合热力图观察前后场覆盖是否均衡。",
        ],
        "raw": {"metadata": {}},
        "task_id": "demo_sample",
        "status": "completed",
        "files": {
            "analysis_video": None,
            "metadata": None,
            "detections": None,
            "visualizations": [],
            "heatmap": None,
            "trajectory": None,
            "highlight": None,
        },
    }


def _set_task(task_id: str, task: dict[str, Any]) -> None:
    with TASKS_LOCK:
        TASKS[task_id] = task
    _write_task_snapshot(task_id)


def _update_task(task_id: str, **changes: Any) -> None:
    with TASKS_LOCK:
        task = TASKS[task_id]
        task.update(changes)
        task["updated_at"] = time.time()
    _write_task_snapshot(task_id)


def _get_task_or_404(task_id: str) -> dict[str, Any]:
    with TASKS_LOCK:
        task = TASKS.get(task_id)
        if task is not None:
            return dict(task)

    snapshot = TASK_DIR / f"{task_id}.json"
    if snapshot.is_file():
        with snapshot.open("r", encoding="utf-8") as f:
            task = json.load(f)
        with TASKS_LOCK:
            TASKS[task_id] = task
        return dict(task)

    raise HTTPException(status_code=404, detail="Task not found.")


def _write_task_snapshot(task_id: str) -> None:
    with TASKS_LOCK:
        task = TASKS.get(task_id)
        if not task:
            return
        payload = dict(task)
    _write_json_atomic(TASK_DIR / f"{task_id}.json", payload)


def _save_upload(file: UploadFile, destination: Path) -> int:
    destination.parent.mkdir(parents=True, exist_ok=True)
    size = 0
    try:
        with destination.open("wb") as out:
            while chunk := file.file.read(COPY_CHUNK_BYTES):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(
                        status_code=413,
                        detail="Video exceeds the 500 MB upload limit.",
                    )
                out.write(chunk)
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    if size == 0:
        destination.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="Video file is empty.")
    return size


def _extract_preview_frame(video_path: Path, source_upload_id: str) -> dict[str, Any]:
    import cv2

    capture = cv2.VideoCapture(str(video_path))
    try:
        if not capture.isOpened():
            raise HTTPException(status_code=400, detail="The uploaded video cannot be opened.")
        fps = float(capture.get(cv2.CAP_PROP_FPS) or 0)
        total_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        if not math.isfinite(fps) or fps <= 0 or total_frames <= 0 or width <= 0 or height <= 0:
            raise HTTPException(status_code=400, detail="The uploaded video metadata is invalid.")

        start = max(0, int(total_frames * 0.05))
        end = max(start, int(total_frames * 0.95) - 1)
        sample_count = min(12, max(1, total_frames))
        positions = {
            round(start + (end - start) * index / max(sample_count - 1, 1))
            for index in range(sample_count)
        }
        best: tuple[float, int, Any, dict[str, float]] | None = None
        for frame_index in sorted(positions):
            capture.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
            ok, frame = capture.read()
            if not ok or frame is None:
                continue
            score, quality = _score_preview_frame(frame)
            if best is None or score > best[0]:
                best = (score, frame_index, frame.copy(), quality)
        if best is None:
            raise HTTPException(status_code=400, detail="No readable frame was found in the video.")
    finally:
        capture.release()

    _, frame_index, frame, quality = best
    preview_path = PREVIEW_DIR / f"{source_upload_id}.jpg"
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(preview_path), frame, [cv2.IMWRITE_JPEG_QUALITY, 90]):
        raise HTTPException(status_code=500, detail="Could not create the preview image.")

    auto_corners: list[list[int]] = []
    try:
        from badminton_analysis.court.detector import auto_detect_court_corners

        detected, _mask, _debug = auto_detect_court_corners(frame)
        if detected and len(detected) == 4:
            auto_corners = [[int(point[0]), int(point[1])] for point in detected]
    except Exception:
        # Preview extraction is still useful when optional court detection fails.
        auto_corners = []

    return {
        "source_upload_id": source_upload_id,
        "image_url": f"/api/videos/preview-images/{source_upload_id}",
        "image_path": str(preview_path),
        "frame_index": frame_index,
        "time_sec": round(frame_index / fps, 3),
        "selection_reason": "best_quality_sample",
        "auto_corners": auto_corners,
        "video": {
            "width": width,
            "height": height,
            "duration_sec": round(total_frames / fps, 3),
            "fps": round(fps, 3),
            "total_frames": total_frames,
        },
        "quality": quality,
    }


def _score_preview_frame(frame: Any) -> tuple[float, dict[str, float]]:
    import cv2

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    sharpness_raw = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    brightness_raw = float(gray.mean())
    sharpness = min(1.0, sharpness_raw / 500.0)
    brightness = max(0.0, 1.0 - abs(brightness_raw - 115.0) / 115.0)
    edges = cv2.Canny(gray, 60, 160)
    edge_density = min(1.0, float(cv2.countNonZero(edges)) / max(gray.size * 0.12, 1))
    score = sharpness * 0.45 + brightness * 0.25 + edge_density * 0.30
    return score, {
        "score": round(score, 4),
        "sharpness": round(sharpness, 4),
        "brightness": round(brightness, 4),
        "edge_density": round(edge_density, 4),
    }


def _get_source_or_404(source_upload_id: str) -> dict[str, Any]:
    if not source_upload_id or not source_upload_id.isalnum():
        raise HTTPException(status_code=404, detail="Source upload not found.")
    path = SOURCE_DIR / f"{source_upload_id}.json"
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Source upload not found.")
    try:
        with path.open("r", encoding="utf-8") as f:
            source = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=500, detail="Source upload metadata is unavailable.") from exc
    return source


def _write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    temporary.replace(path)


def _validate_video_filename(filename: str | None) -> str:
    if not filename:
        raise HTTPException(status_code=400, detail="Missing video filename.")
    safe_name = _safe_filename(filename)
    if Path(safe_name).suffix.lower() not in ALLOWED_VIDEO_EXTENSIONS:
        raise HTTPException(status_code=415, detail="Only MP4, MOV, and M4V videos are supported.")
    return safe_name


def _resolve_template(template_path: str | None) -> Path:
    if template_path:
        candidate = Path(template_path)
        if not candidate.is_absolute():
            candidate = PROJECT_ROOT / candidate
        if candidate.is_file():
            return candidate
        raise HTTPException(status_code=400, detail=f"Template not found: {template_path}")
    return _default_template_path()


def _default_template_path() -> Path:
    for candidate in DEFAULT_TEMPLATE_CANDIDATES:
        if candidate.is_file():
            return candidate
    raise HTTPException(status_code=500, detail="No default court template found.")


def _parse_corners(corners_json: str | None) -> list[list[int]] | None:
    if not corners_json:
        return None
    try:
        corners = json.loads(corners_json)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="corners_json is not valid JSON.") from exc
    if not isinstance(corners, list) or len(corners) != 4:
        raise HTTPException(status_code=400, detail="corners_json must contain 4 points.")
    parsed = []
    for point in corners:
        if not isinstance(point, list | tuple) or len(point) != 2:
            raise HTTPException(status_code=400, detail="Each corner must be [x, y].")
        parsed.append([int(point[0]), int(point[1])])
    return parsed


def _safe_filename(filename: str) -> str:
    name = Path(filename).name
    return "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in name)
