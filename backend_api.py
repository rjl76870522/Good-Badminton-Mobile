"""FastAPI backend for a mobile Good-Badminton demo loop.

Run from the project root:

    uvicorn backend_api:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import json
import os
import shutil
import threading
import time
import uuid
from pathlib import Path
from typing import Any

import cv2
from fastapi import BackgroundTasks, FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from badminton_analysis.highlight import generate_highlight
from badminton_analysis.mobile_report import build_mobile_report
from webui.pipeline import prepare_court, run_analysis


PROJECT_ROOT = Path(__file__).resolve().parent
UPLOAD_DIR = PROJECT_ROOT / "mobile_backend_data" / "uploads"
TASK_DIR = PROJECT_ROOT / "mobile_backend_data" / "tasks"
OUTPUTS_DIR = PROJECT_ROOT / "outputs"
FRONTEND_DIR = PROJECT_ROOT / "mobile_frontend"
DEFAULT_USER_ID = "guest"
MAX_UPLOAD_BYTES = 500 * 1024 * 1024
MIN_VIDEO_DURATION_SEC = 5.0
MAX_VIDEO_DURATION_SEC = 180.0
MIN_DETECTION_RECORDS = 3
DEFAULT_TEMPLATE_CANDIDATES = [
    PROJECT_ROOT / "templates" / "badminton_template.png",
    PROJECT_ROOT / "templates" / "my_template.png",
    PROJECT_ROOT / "templates" / "demo.png",
]

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
TASK_DIR.mkdir(parents=True, exist_ok=True)
OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Good-Badminton Mobile Backend", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/outputs", StaticFiles(directory=str(OUTPUTS_DIR)), name="outputs")
if FRONTEND_DIR.is_dir():
    app.mount("/app", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="mobile_frontend")

TASKS: dict[str, dict[str, Any]] = {}
TASKS_LOCK = threading.Lock()
ANALYSIS_LOCK = threading.Lock()


@app.get("/api/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "project_root": str(PROJECT_ROOT),
        "default_template": str(_default_template_path()),
    }


@app.get("/", include_in_schema=False)
def index() -> RedirectResponse:
    return RedirectResponse(url="/app/")


@app.post("/api/videos/upload")
def upload_video(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    user_id: str = Form(default=DEFAULT_USER_ID),
    template_path: str | None = Form(default=None),
    corners_json: str | None = Form(default=None),
    language: str = Form(default="zh"),
    pose_mode: str = Form(default="balanced"),
    keep_audio: bool = Form(default=True),
) -> dict[str, Any]:
    if not file.filename:
        raise_api_error(
            status_code=400,
            code="MISSING_VIDEO",
            message="请选择要上传的视频文件。",
        )

    user_id = _safe_user_id(user_id)
    task_id = uuid.uuid4().hex
    safe_name = _safe_filename(file.filename)
    upload_path = UPLOAD_DIR / f"{task_id}_{safe_name}"

    with upload_path.open("wb") as out:
        shutil.copyfileobj(file.file, out)
    _validate_uploaded_video(upload_path)

    template = _resolve_template(template_path)
    corners = _parse_corners(corners_json)
    task = {
        "task_id": task_id,
        "status": "queued",
        "progress": 0.0,
        "stage": "queued",
        "error": None,
        "video_name": safe_name,
        "user_id": user_id,
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
def list_tasks(user_id: str | None = Query(default=None)) -> dict[str, Any]:
    tasks = _load_all_tasks()
    tasks = _filter_tasks_by_user(tasks, user_id)
    tasks.sort(key=lambda item: item["created_at"], reverse=True)
    return {"tasks": [_public_task(t) for t in tasks]}


@app.get("/api/history")
def get_history(
    limit: int = Query(default=20, ge=1, le=100),
    user_id: str | None = Query(default=None),
    status: str | None = Query(default=None),
) -> dict[str, Any]:
    tasks = _load_all_tasks()
    tasks = _filter_tasks_by_user(tasks, user_id)
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
        raise_api_error(
            status_code=409,
            code="ANALYSIS_FAILED",
            message=task["error"] or "视频分析失败。",
            hint="请检查拍摄角度、球场线是否清晰，或换一段稳定样例视频。",
        )
    if task["status"] != "completed" or not task.get("report"):
        raise_api_error(
            status_code=202,
            code="ANALYSIS_NOT_READY",
            message="视频仍在分析中，请稍后再试。",
        )
    return task["report"]


@app.get("/api/tasks/{task_id}/highlight")
def get_highlight(task_id: str) -> FileResponse:
    task = _get_task_or_404(task_id)
    report = task.get("report") or {}
    files = report.get("files") or {}
    highlight_url = files.get("highlight")
    highlight_path = _output_url_to_path(highlight_url)
    if highlight_path is None or not highlight_path.is_file():
        raise_api_error(
            status_code=404,
            code="HIGHLIGHT_NOT_AVAILABLE",
            message="精彩集锦暂不可用。",
            hint="请等待任务完成，或查看报告中的 highlight_error。",
        )
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
    with ANALYSIS_LOCK:
        try:
            manual_corners = corners is not None
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
                "always_process_court": True,
                "court_match_threshold": 0.55,
                "corners_coordinate_space": "video" if manual_corners else "template",
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
            detection_records = _count_detection_records(result.get("detections"))
            result["detection_records"] = detection_records
            if detection_records < MIN_DETECTION_RECORDS:
                raise RuntimeError(
                    "未检测到有效球场/球员数据。请检查视频是否完整拍到球场，"
                    "或在上传时手动填写四个球场角点。"
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


def _count_detection_records(path: str | os.PathLike[str] | None) -> int:
    if not path:
        return 0
    detection_path = Path(path)
    if not detection_path.is_absolute():
        detection_path = PROJECT_ROOT / detection_path
    if not detection_path.is_file():
        return 0

    count = 0
    with detection_path.open("r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                count += 1
                if count >= MIN_DETECTION_RECORDS:
                    return count
    return count


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
        "user_id": task.get("user_id", DEFAULT_USER_ID),
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


def _filter_tasks_by_user(tasks: list[dict[str, Any]], user_id: str | None) -> list[dict[str, Any]]:
    if not user_id:
        return tasks
    safe_id = _safe_user_id(user_id)
    return [task for task in tasks if task.get("user_id", DEFAULT_USER_ID) == safe_id]


def _safe_user_id(user_id: str | None) -> str:
    raw = (user_id or DEFAULT_USER_ID).strip()
    safe = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in raw)
    return safe[:64] or DEFAULT_USER_ID


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

    raise_api_error(
        status_code=404,
        code="TASK_NOT_FOUND",
        message="任务不存在。",
        hint="请检查 task_id 是否正确。",
    )


def _write_task_snapshot(task_id: str) -> None:
    with TASKS_LOCK:
        task = TASKS.get(task_id)
        if not task:
            return
        payload = dict(task)
    path = TASK_DIR / f"{task_id}.json"
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def _resolve_template(template_path: str | None) -> Path:
    if template_path:
        candidate = Path(template_path)
        if not candidate.is_absolute():
            candidate = PROJECT_ROOT / candidate
        if candidate.is_file():
            return candidate
        raise_api_error(
            status_code=400,
            code="TEMPLATE_NOT_FOUND",
            message=f"球场模板不存在: {template_path}",
            hint="template_path 可留空，默认使用 templates/badminton_template.png。",
        )
    return _default_template_path()


def _default_template_path() -> Path:
    for candidate in DEFAULT_TEMPLATE_CANDIDATES:
        if candidate.is_file():
            return candidate
    raise_api_error(
        status_code=500,
        code="DEFAULT_TEMPLATE_MISSING",
        message="服务器缺少默认球场模板。",
    )


def _parse_corners(corners_json: str | None) -> list[list[int]] | None:
    if not corners_json:
        return None
    try:
        corners = json.loads(corners_json)
    except json.JSONDecodeError as exc:
        raise_api_error(
            status_code=400,
            code="INVALID_CORNERS_JSON",
            message="corners_json 不是合法 JSON。",
            hint="可直接留空，由后端自动检测角点。",
        )
    if not isinstance(corners, list) or len(corners) != 4:
        raise_api_error(
            status_code=400,
            code="INVALID_CORNERS",
            message="corners_json 必须包含 4 个角点。",
        )
    parsed = []
    for point in corners:
        if not isinstance(point, list | tuple) or len(point) != 2:
            raise_api_error(
                status_code=400,
                code="INVALID_CORNERS",
                message="每个角点必须是 [x, y]。",
            )
        parsed.append([int(point[0]), int(point[1])])
    return parsed


def _safe_filename(filename: str) -> str:
    name = Path(filename).name
    return "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in name)


def _validate_uploaded_video(path: Path) -> None:
    size = path.stat().st_size
    if size <= 0:
        path.unlink(missing_ok=True)
        raise_api_error(
            status_code=400,
            code="VIDEO_EMPTY",
            message="上传的视频文件为空。",
        )
    if size > MAX_UPLOAD_BYTES:
        path.unlink(missing_ok=True)
        raise_api_error(
            status_code=413,
            code="VIDEO_TOO_LARGE",
            message="视频文件过大，请上传 500MB 以内的视频。",
            hint="建议先使用 30 秒到 3 分钟的横屏固定机位视频。",
        )

    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        path.unlink(missing_ok=True)
        raise_api_error(
            status_code=400,
            code="VIDEO_UNREADABLE",
            message="无法读取视频文件。",
            hint="请上传有效的 MP4/MOV 文件。",
        )
    fps = cap.get(cv2.CAP_PROP_FPS) or 0
    frames = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0
    cap.release()
    duration = frames / fps if fps > 0 else 0
    if duration < MIN_VIDEO_DURATION_SEC:
        path.unlink(missing_ok=True)
        raise_api_error(
            status_code=400,
            code="VIDEO_TOO_SHORT",
            message="视频太短，请上传至少 5 秒的视频。",
            hint="正式训练复盘建议上传 30 秒到 3 分钟的视频。",
        )
    if duration > MAX_VIDEO_DURATION_SEC:
        path.unlink(missing_ok=True)
        raise_api_error(
            status_code=400,
            code="VIDEO_TOO_LONG",
            message="视频太长，请上传 3 分钟以内的视频。",
            hint="当前服务器按短视频训练复盘优化，长视频请先裁剪。",
        )


def raise_api_error(
    *,
    status_code: int,
    code: str,
    message: str,
    hint: str | None = None,
) -> None:
    detail = {"code": code, "message": message}
    if hint:
        detail["hint"] = hint
    raise HTTPException(status_code=status_code, detail=detail)
