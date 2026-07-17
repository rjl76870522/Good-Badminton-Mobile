"""FastAPI backend for a mobile Good-Badminton demo loop.

Run from the project root:

    uvicorn backend_api:app --host 0.0.0.0 --port 8001
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
import uuid
import gc
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from sqlalchemy import or_
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from badminton_analysis.database import (
    OutputFile,
    Task,
    User,
    get_session,
    init_db,
    task_to_legacy_dict,
)
from badminton_analysis.highlight import generate_highlight
from badminton_analysis.task_queue import DurableTaskWorker
from badminton_analysis.mobile_report import build_mobile_report, load_advice_knowledge
from badminton_analysis.court.mapper import auto_detect_preview
from badminton_analysis.user_registry import (
    InvalidUserId,
    UserAlreadyExists,
    UserNotFound,
    get_user as registry_get_user,
    register_user as registry_register_user,
    search_users_by_display_name,
    update_display_name,
)
from webui.pipeline import prepare_court, run_analysis


PROJECT_ROOT = Path(__file__).resolve().parent
UPLOAD_DIR = PROJECT_ROOT / "mobile_backend_data" / "uploads"
PREVIEW_UPLOAD_DIR = PROJECT_ROOT / "mobile_backend_data" / "preview_uploads"
PREVIEW_FRAME_DIR = PROJECT_ROOT / "mobile_backend_data" / "preview_frames"
TASK_DIR = PROJECT_ROOT / "mobile_backend_data" / "tasks"
USER_REGISTRY_PATH = PROJECT_ROOT / "mobile_backend_data" / "users.json"
OUTPUTS_DIR = PROJECT_ROOT / "outputs"
FRONTEND_DIR = PROJECT_ROOT / "mobile_frontend"
DEFAULT_USER_ID = "guest"
USER_ID_RULE_MESSAGE = "用户 ID 需要 3-32 位，只能使用小写英文字母、数字、下划线或短横线，且必须以字母或数字开头。"
MAX_UPLOAD_BYTES = 200 * 1024 * 1024
MIN_VIDEO_DURATION_SEC = 5.0
MAX_VIDEO_DURATION_SEC = 180.0
MIN_DETECTION_RECORDS = 3
PREVIEW_COURT_DETECT_CANDIDATES = 3
MIN_PREVIEW_BRIGHTNESS = 40.0
MIN_PREVIEW_NONBLACK_RATIO = 0.42
MIN_PREVIEW_CENTER_NONBLACK_RATIO = 0.35
MAX_PREVIEW_DARK_RATIO = 0.65
MIN_PREVIEW_SHARPNESS = 12.0
MIN_PREVIEW_COURT_AREA_RATIO = 0.025
MAX_PREVIEW_COURT_AREA_RATIO = 0.92
DEFAULT_TEMPLATE_CANDIDATES = [
    PROJECT_ROOT / "templates" / "badminton_template.png",
    PROJECT_ROOT / "templates" / "my_template.png",
    PROJECT_ROOT / "templates" / "demo.png",
]


def _recommend_analysis_workers(total_memory_mb: int, free_memory_mb: int) -> int:
    """Choose conservative GPU concurrency with room for codec and UI peaks."""
    if total_memory_mb >= 24_000:
        if free_memory_mb >= 18_000:
            return 4
        if free_memory_mb >= 12_000:
            return 3
    if total_memory_mb >= 16_000:
        if free_memory_mb >= 12_000:
            return 4
        if free_memory_mb >= 8_000:
            return 2
    if total_memory_mb >= 12_000 and free_memory_mb >= 8_000:
        return 2
    return 1


def _analysis_capacity() -> tuple[int, dict[str, Any]]:
    override = os.getenv("ANALYSIS_WORKERS", "auto").strip().lower()
    if override not in {"", "auto"}:
        try:
            configured = max(1, min(int(override), 4))
            return configured, {"source": "environment", "configured": configured}
        except ValueError:
            pass
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.total,memory.free",
                "--format=csv,noheader,nounits",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        name, total, free = [part.strip() for part in result.stdout.splitlines()[0].split(",")]
        total_mb = int(float(total))
        free_mb = int(float(free))
        workers = _recommend_analysis_workers(total_mb, free_mb)
        return workers, {
            "source": "gpu_auto",
            "gpu": name,
            "memory_total_mb": total_mb,
            "memory_free_at_start_mb": free_mb,
            "configured": workers,
        }
    except Exception as exc:
        return 1, {"source": "safe_default", "configured": 1, "reason": str(exc)}


ANALYSIS_WORKER_COUNT, ANALYSIS_CAPACITY_INFO = _analysis_capacity()

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
PREVIEW_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
PREVIEW_FRAME_DIR.mkdir(parents=True, exist_ok=True)
TASK_DIR.mkdir(parents=True, exist_ok=True)
OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)

@asynccontextmanager
async def lifespan(_app: FastAPI):
    recover_persisted_tasks()
    TASK_WORKER.start()
    TASK_WORKER.notify()
    try:
        yield
    finally:
        TASK_WORKER.stop()


# Initialize SQLite database (replaces JSON file storage)
init_db(PROJECT_ROOT / "mobile_backend_data" / "badminton.db")

app = FastAPI(title="Good-Badminton Mobile Backend", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/outputs", StaticFiles(directory=str(OUTPUTS_DIR)), name="outputs")
app.mount("/preview-frames", StaticFiles(directory=str(PREVIEW_FRAME_DIR)), name="preview_frames")
if FRONTEND_DIR.is_dir():
    app.mount("/app", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="mobile_frontend")

USER_REGISTRY_LOCK = threading.Lock()
STARTUP_RECOVERY_LOCK = threading.Lock()


class RegisterUserRequest(BaseModel):
    user_id: str


@app.get("/api/health")
def health() -> dict[str, Any]:
    queue = _queue_summary()
    return {
        "ok": True,
        "project_root": str(PROJECT_ROOT),
        "default_template": str(_default_template_path()),
        "queue": queue,
    }


def recover_persisted_tasks() -> None:
    """Validate pending work and return interrupted tasks to the durable queue."""
    with STARTUP_RECOVERY_LOCK:
        pending = [
            task
            for task in _load_all_tasks()
            if task.get("status") in {"queued", "processing"}
        ]
        for task in pending:
            upload_path = Path(str(task.get("upload_path") or ""))
            template_path = Path(str(task.get("template_path") or ""))
            if not upload_path.is_file() or not template_path.is_file():
                _update_task(
                    task["task_id"],
                    status="failed",
                    stage="failed",
                    progress=1.0,
                    error=(
                        "服务器重启后无法恢复任务：上传视频或球场模板文件已不存在。"
                        "请重新上传视频。"
                    ),
                )
                continue
            _update_task(
                task["task_id"],
                status="queued",
                stage="queued_after_restart",
                progress=0.0,
                error=None,
            )


@app.get("/api/diagnostics")
def diagnostics() -> dict[str, Any]:
    return _diagnostics()


@app.get("/", include_in_schema=False)
def index() -> RedirectResponse:
    return RedirectResponse(url="/app/")


@app.post("/api/users/register")
def register_mobile_user(payload: RegisterUserRequest) -> dict[str, Any]:
    with USER_REGISTRY_LOCK:
        try:
            user = registry_register_user(user_id=payload.user_id)
        except InvalidUserId:
            raise_api_error(
                status_code=400,
                code="INVALID_USER_ID",
                message="这个用户 ID 格式不能使用。",
                hint=USER_ID_RULE_MESSAGE,
            )
        except UserAlreadyExists:
            raise_api_error(
                status_code=409,
                code="USER_ID_TAKEN",
                message="这个用户 ID 已经被注册。",
                hint="请换一个 ID，或使用本机已保存的游客身份继续查看历史记录。",
            )
    return {"user": user}


@app.get("/api/users/{user_id}")
def get_mobile_user(user_id: str) -> dict[str, Any]:
    try:
        user = registry_get_user(user_id)
    except InvalidUserId:
        raise_api_error(
            status_code=400,
            code="INVALID_USER_ID",
            message="这个用户 ID 格式不能使用。",
            hint=USER_ID_RULE_MESSAGE,
        )
    except UserNotFound:
        raise_api_error(
            status_code=404,
            code="USER_NOT_FOUND",
            message="用户不存在。",
            hint="请先注册这个用户 ID，或继续使用游客模式。",
        )
    return {"user": user}


class UpdateDisplayNameRequest(BaseModel):
    display_name: str


@app.put("/api/users/{user_id}/display-name")
def set_display_name(user_id: str, payload: UpdateDisplayNameRequest) -> dict[str, Any]:
    """Set or change a user's display name. Names can be anything, duplicates allowed."""
    try:
        user = update_display_name(user_id=user_id, display_name=payload.display_name)
    except InvalidUserId:
        raise_api_error(
            status_code=400,
            code="INVALID_USER_ID",
            message="这个用户 ID 格式不能使用。",
            hint=USER_ID_RULE_MESSAGE,
        )
    except UserNotFound:
        raise_api_error(
            status_code=404,
            code="USER_NOT_FOUND",
            message="用户不存在，请先注册。",
        )
    return {"user": user}


@app.get("/api/users/search")
def search_users(
    name: str = Query(default="", min_length=1, max_length=128),
    limit: int = Query(default=20, ge=1, le=50),
) -> dict[str, Any]:
    """Search users by display name (fuzzy match)."""
    users = search_users_by_display_name(name, limit=limit)
    return {"users": users, "count": len(users)}


@app.post("/api/videos/upload")
def upload_video(
    file: UploadFile | None = File(default=None),
    user_id: str = Form(default=DEFAULT_USER_ID),
    source_upload_id: str | None = Form(default=None),
    template_path: str | None = Form(default=None),
    corners_json: str | None = Form(default=None),
    language: str = Form(default="zh"),
    pose_mode: str = Form(default="balanced"),
    keep_audio: bool = Form(default=True),
) -> dict[str, Any]:
    if file is None and not source_upload_id:
        raise_api_error(
            status_code=400,
            code="MISSING_VIDEO",
            message="请选择要上传的视频文件。",
        )

    user_id = _safe_user_id(user_id)
    task_id = uuid.uuid4().hex
    if source_upload_id:
        source_path, source_name = _resolve_preview_upload(source_upload_id)
        safe_name = source_name
    else:
        if file is None or not file.filename:
            raise_api_error(
                status_code=400,
                code="MISSING_VIDEO",
                message="请选择要上传的视频文件。",
            )
        source_path = None
        safe_name = _safe_filename(file.filename)
    upload_path = UPLOAD_DIR / f"{task_id}_{safe_name}"

    if source_upload_id:
        shutil.copyfile(source_path, upload_path)
    else:
        with upload_path.open("wb") as out:
            shutil.copyfileobj(file.file, out)
    _validate_uploaded_video(upload_path)

    template = _resolve_template(template_path)
    corners = _parse_corners(corners_json)
    if corners:
        _validate_corners_for_video(corners, upload_path)
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
        "corners_json": json.dumps(corners) if corners else None,
        "language": language,
        "pose_mode": pose_mode,
        "keep_audio": keep_audio,
        "created_at": time.time(),
        "updated_at": time.time(),
        "report": None,
    }
    _set_task(task_id, task)
    TASK_WORKER.notify()

    return {
        "task_id": task_id,
        "status": "queued",
        "status_url": f"/api/tasks/{task_id}",
        "report_url": f"/api/tasks/{task_id}/report",
    }


@app.post("/api/videos/preview-frame")
def create_preview_frame(
    file: UploadFile = File(...),
    user_id: str = Form(default=DEFAULT_USER_ID),
) -> dict[str, Any]:
    if not file.filename:
        raise_api_error(
            status_code=400,
            code="MISSING_VIDEO",
            message="请选择要上传的视频文件。",
        )

    user_id = _safe_user_id(user_id)
    source_upload_id = uuid.uuid4().hex
    safe_name = _safe_filename(file.filename)
    source_path = PREVIEW_UPLOAD_DIR / f"{source_upload_id}_{safe_name}"
    with source_path.open("wb") as out:
        shutil.copyfileobj(file.file, out)
    _validate_uploaded_video(source_path)

    preview = _select_preview_frame(source_path, source_upload_id)
    preview.update(
        {
            "source_upload_id": source_upload_id,
            "user_id": user_id,
            "video_name": safe_name,
        }
    )
    return preview


@app.get("/api/tasks")
def list_tasks(user_id: str | None = Query(default=None)) -> dict[str, Any]:
    tasks = _load_all_tasks()
    tasks = _filter_tasks_by_user(tasks, user_id)
    tasks.sort(key=lambda item: item["created_at"], reverse=True)
    return {"tasks": [_public_task(t) for t in tasks]}


@app.get("/api/queue")
def get_queue_status() -> dict[str, Any]:
    return _queue_summary()


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


@app.post("/api/tasks/{task_id}/cancel")
def cancel_task(
    task_id: str,
    user_id: str | None = Query(default=None),
) -> dict[str, Any]:
    task = _get_task_or_404(task_id)
    if user_id and task.get("user_id", DEFAULT_USER_ID) != _safe_user_id(user_id):
        raise_api_error(
            status_code=404,
            code="TASK_NOT_FOUND",
            message="任务不存在。",
            hint="请确认当前 user_id 和 task_id 是否匹配。",
        )
    if task["status"] == "cancelled":
        return _public_task(task)
    if task["status"] != "queued":
        raise_api_error(
            status_code=409,
            code="TASK_CANNOT_CANCEL",
            message="任务已经开始分析，当前不能取消。",
            hint="只有仍在排队的任务可以取消。",
        )

    session = get_session()
    try:
        changed = (
            session.query(Task)
            .filter(Task.task_id == task_id, Task.status == "queued")
            .update(
                {
                    Task.status: "cancelled",
                    Task.stage: "cancelled",
                    Task.error: None,
                    Task.updated_at: time.time(),
                },
                synchronize_session=False,
            )
        )
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
    if not changed:
        raise_api_error(
            status_code=409,
            code="TASK_CANNOT_CANCEL",
            message="任务刚刚开始分析，当前不能取消。",
        )
    return _public_task(_get_task_or_404(task_id))


@app.delete("/api/tasks/{task_id}")
def delete_task(
    task_id: str,
    user_id: str | None = Query(default=None),
) -> dict[str, Any]:
    task = _get_task_or_404(task_id)
    if user_id and task.get("user_id", DEFAULT_USER_ID) != _safe_user_id(user_id):
        raise_api_error(
            status_code=404,
            code="TASK_NOT_FOUND",
            message="任务不存在。",
            hint="请确认当前 user_id 和 task_id 是否匹配。",
        )

    deleted_paths = _delete_task_artifacts(task)
    session = get_session()
    try:
        db_task = session.get(Task, task_id)
        if db_task:
            session.delete(db_task)
            session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()

    return {
        "ok": True,
        "task_id": task_id,
        "deleted_paths": deleted_paths,
    }


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
    if task["status"] == "cancelled":
        raise_api_error(
            status_code=409,
            code="TASK_CANCELLED",
            message="任务已取消。",
            hint="请重新选择视频并创建分析任务。",
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
    highlight_segments = _decorate_highlight_segments(result.get("highlight_segments", []))
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
            "highlight_segments": highlight_segments,
            "highlight_error": result.get("highlight_error"),
        }
    )
    return report


def _decorate_highlight_segments(segments: Any) -> list[dict[str, Any]]:
    if not isinstance(segments, list):
        return []
    decorated: list[dict[str, Any]] = []
    for item in segments:
        if not isinstance(item, dict):
            continue
        segment = dict(item)
        metrics = segment.get("metrics") if isinstance(segment.get("metrics"), dict) else {}
        reason = str(segment.get("reason") or "")
        segment["reason_zh"] = _highlight_reason_zh(reason, metrics)
        segment["tags"] = _highlight_tags(reason, metrics)
        segment["display_metrics"] = {
            "player_peak_mps": _round_float(metrics.get("player_peak_mps")),
            "player_distance_m": _round_float(metrics.get("player_distance_m")),
            "shuttle_peak_px_s": _round_float(metrics.get("shuttle_peak_px_s")),
        }
        decorated.append(segment)
    return decorated


def _highlight_reason_zh(reason: str, metrics: dict[str, Any]) -> str:
    player_peak = _to_float(metrics.get("player_peak_mps"))
    player_distance = _to_float(metrics.get("player_distance_m"))
    shuttle_peak = _to_float(metrics.get("shuttle_peak_px_s"))
    parts: list[str] = []
    if player_peak >= 5.0:
        parts.append("球员出现快速启动或冲刺")
    if player_distance >= 12.0:
        parts.append("片段内移动距离较大")
    if shuttle_peak >= 1000.0:
        parts.append("球速变化明显")
    if not parts:
        if "fast" in reason.lower():
            parts.append("速度指标较高")
        else:
            parts.append("该片段综合运动强度较高")
    return "，".join(parts) + "，因此被选入精彩集锦。"


def _highlight_tags(reason: str, metrics: dict[str, Any]) -> list[str]:
    tags: list[str] = []
    player_peak = _to_float(metrics.get("player_peak_mps"))
    player_distance = _to_float(metrics.get("player_distance_m"))
    shuttle_peak = _to_float(metrics.get("shuttle_peak_px_s"))
    if player_peak >= 5.0 or "fast player" in reason.lower():
        tags.append("快速启动")
    if player_distance >= 12.0:
        tags.append("高强度跑动")
    if player_distance >= 18.0:
        tags.append("覆盖范围大")
    if shuttle_peak >= 1000.0:
        tags.append("高速来球")
    return tags or ["精彩回合"]


def _round_float(value: Any) -> float:
    return round(_to_float(value), 2)


def _to_float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


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


def _resolve_preview_upload(source_upload_id: str) -> tuple[Path, str]:
    source_id = (source_upload_id or "").strip()
    if not source_id or any(ch not in "0123456789abcdef" for ch in source_id.lower()):
        raise_api_error(
            status_code=400,
            code="INVALID_SOURCE_UPLOAD",
            message="预览视频来源无效，请重新选择视频。",
        )

    matches = list(PREVIEW_UPLOAD_DIR.glob(f"{source_id}_*"))
    if not matches:
        raise_api_error(
            status_code=404,
            code="SOURCE_UPLOAD_NOT_FOUND",
            message="预览视频已失效，请重新选择视频。",
        )
    source_path = matches[0]
    source_name = source_path.name.removeprefix(f"{source_id}_")
    return source_path, source_name


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


def _select_preview_frame(video_path: Path, source_upload_id: str) -> dict[str, Any]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise_api_error(
            status_code=400,
            code="VIDEO_UNREADABLE",
            message="无法读取视频文件。",
        )

    fps = cap.get(cv2.CAP_PROP_FPS) or 0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
    duration_sec = total_frames / fps if fps > 0 else 0.0
    if total_frames <= 0 or width <= 0 or height <= 0:
        cap.release()
        raise_api_error(
            status_code=400,
            code="VIDEO_UNREADABLE",
            message="无法读取视频尺寸或帧数。",
        )

    sample_indices = _preview_sample_indices(total_frames)
    candidates: list[dict[str, Any]] = []
    for frame_index in sample_indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = cap.read()
        if not ok or frame is None:
            continue
        scored = _score_preview_frame(frame, frame_index, fps, detect_court=False)
        if not scored["usable"]:
            continue
        candidates.append(scored)
    cap.release()

    best: dict[str, Any] | None = None
    for candidate in sorted(candidates, key=lambda item: item["score"], reverse=True)[
        :PREVIEW_COURT_DETECT_CANDIDATES
    ]:
        scored = _score_preview_frame(
            candidate["frame"],
            candidate["frame_index"],
            fps,
            detect_court=True,
        )
        if not scored["usable"]:
            continue
        if best is None or scored["score"] > best["score"]:
            best = scored

    if best is None and candidates:
        best = max(candidates, key=lambda item: item["score"])
        best["reason"] = "visual_quality_fallback"

    if best is None:
        raise_api_error(
            status_code=400,
            code="PREVIEW_FRAME_FAILED",
            message="无法从视频中提取有效球场预览帧。",
            hint=(
                "可能是上传网络波动导致视频文件不完整，也可能是原视频黑屏、过暗或没有完整球场。"
                "请重新提交视频，必要时换一段开头稳定、能看到完整球场的视频。"
            ),
        )

    image_path = PREVIEW_FRAME_DIR / f"{source_upload_id}.jpg"
    ok, encoded = cv2.imencode(".jpg", best["frame"], [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    if not ok:
        raise_api_error(
            status_code=500,
            code="PREVIEW_ENCODE_FAILED",
            message="预览帧编码失败。",
        )
    encoded.tofile(str(image_path))

    return {
        "image_url": f"/preview-frames/{source_upload_id}.jpg",
        "frame_index": best["frame_index"],
        "time_sec": round(float(best["time_sec"]), 2),
        "score": round(float(best["score"]), 3),
        "selection_reason": best["reason"],
        "scene_ok": best["usable"],
        "scene_warning": best.get("scene_warning"),
        "quality": best.get("quality"),
        "auto_corners": best["auto_corners"],
        "video": {
            "width": width,
            "height": height,
            "duration_sec": round(duration_sec, 2),
            "fps": round(float(fps), 2),
            "total_frames": total_frames,
        },
    }


def _preview_sample_indices(total_frames: int) -> list[int]:
    fractions = [0.10, 0.16, 0.22, 0.30, 0.38, 0.46, 0.54, 0.62, 0.70, 0.78, 0.86]
    indices = {
        min(total_frames - 1, max(0, int(total_frames * fraction)))
        for fraction in fractions
    }
    if total_frames > 90:
        indices.add(min(total_frames - 1, 30))
    return sorted(indices)


def _score_preview_frame(
    frame: Any,
    frame_index: int,
    fps: float,
    *,
    detect_court: bool = True,
) -> dict[str, Any]:
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    brightness = float(gray.mean())
    dark_ratio = float(np.mean(gray < 22))
    nonblack_ratio = float(np.mean(gray > 32))
    center = gray[
        gray.shape[0] // 5 : gray.shape[0] * 4 // 5,
        gray.shape[1] // 5 : gray.shape[1] * 4 // 5,
    ]
    center_nonblack_ratio = float(np.mean(center > 32)) if center.size else nonblack_ratio
    sharpness = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    edges = cv2.Canny(gray, 80, 180)
    edge_density = float(cv2.countNonZero(edges)) / max(edges.size, 1)

    raw_auto_corners = None
    if detect_court:
        raw_auto_corners, _preview = auto_detect_preview(frame)
    h, w = frame.shape[:2]
    auto_corners = None
    area_ratio = 0.0
    if raw_auto_corners:
        pts_np = np.array(raw_auto_corners, dtype=np.float32)
        area_ratio = float(cv2.contourArea(pts_np)) / max(float(w * h), 1.0)
        points_inside = all(0 <= x < w and 0 <= y < h for x, y in raw_auto_corners)
        if (
            points_inside
            and MIN_PREVIEW_COURT_AREA_RATIO <= area_ratio <= MAX_PREVIEW_COURT_AREA_RATIO
        ):
            auto_corners = raw_auto_corners

    brightness_score = max(0.0, 1.0 - abs(brightness - 125.0) / 125.0)
    sharpness_score = min(sharpness / 600.0, 1.0)
    edge_score = min(edge_density / 0.08, 1.0)
    area_score = min(area_ratio / 0.18, 1.0)
    content_score = min((nonblack_ratio + center_nonblack_ratio) / 1.4, 1.0)
    dark_penalty = max(0.0, (dark_ratio - 0.35) * 2.0)
    court_bonus = 2.5 if auto_corners else 0.0
    usable = (
        brightness >= MIN_PREVIEW_BRIGHTNESS
        and nonblack_ratio >= MIN_PREVIEW_NONBLACK_RATIO
        and center_nonblack_ratio >= MIN_PREVIEW_CENTER_NONBLACK_RATIO
        and dark_ratio <= MAX_PREVIEW_DARK_RATIO
        and sharpness >= MIN_PREVIEW_SHARPNESS
    )
    score = (
        court_bonus
        + brightness_score * 0.8
        + sharpness_score * 0.8
        + edge_score * 0.5
        + area_score * 1.4
        + content_score * 1.0
        - dark_penalty
    )

    reason = "auto_court_detected" if auto_corners else "visual_quality_fallback"
    scene_warning = None
    if not usable:
        reason = "rejected_dark_or_low_content"
        scene_warning = "未检测到有效球场场景，请重新提交视频或换一段画面更稳定的视频。"
    elif raw_auto_corners and not auto_corners:
        reason = "rejected_invalid_auto_corners"
        scene_warning = "自动角点质量较低，建议放大画面后手动点选四个外侧角点。"
    return {
        "frame": frame,
        "frame_index": frame_index,
        "time_sec": frame_index / fps if fps > 0 else 0.0,
        "score": score,
        "reason": reason,
        "auto_corners": [[int(x), int(y)] for x, y in auto_corners] if auto_corners else None,
        "usable": usable,
        "scene_warning": scene_warning,
        "quality": {
            "brightness": round(brightness, 2),
            "dark_ratio": round(dark_ratio, 3),
            "nonblack_ratio": round(nonblack_ratio, 3),
            "center_nonblack_ratio": round(center_nonblack_ratio, 3),
            "sharpness": round(sharpness, 2),
            "edge_density": round(edge_density, 4),
        },
    }


def _validate_corners_for_video(corners: list[list[int]], video_path: Path) -> None:
    cap = cv2.VideoCapture(str(video_path))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
    cap.release()
    if width <= 0 or height <= 0:
        return

    for x, y in corners:
        if x < 0 or y < 0 or x >= width or y >= height:
            raise_api_error(
                status_code=400,
                code="INVALID_CORNERS",
                message="手动角点超出视频画面范围。",
                hint=f"视频尺寸为 {width}x{height}，请重新点选角点。",
            )

    area = float(cv2.contourArea(np.array(corners, dtype=np.float32)))
    if area < width * height * 0.02:
        raise_api_error(
            status_code=400,
            code="INVALID_CORNERS",
            message="手动角点围成的球场区域过小。",
            hint="请按左上、右上、右下、左下重新点选四个外侧角点。",
        )


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
    failure = _failure_info(task.get("error"))
    queue_position = _queue_position(task) if task.get("status") == "queued" else None
    return {
        "task_id": task["task_id"],
        "user_id": task.get("user_id", DEFAULT_USER_ID),
        "status": task["status"],
        "progress": task["progress"],
        "stage": task["stage"],
        "error": task["error"],
        "failure_code": failure["code"] if task["status"] == "failed" else None,
        "failure_title": failure["title"] if task["status"] == "failed" else None,
        "failure_hint": failure["hint"] if task["status"] == "failed" else None,
        "video_name": task["video_name"],
        "created_at": task["created_at"],
        "updated_at": task["updated_at"],
        "report_url": f"/api/tasks/{task['task_id']}/report",
        "queue_position": queue_position,
    }


def _history_item(task: dict[str, Any]) -> dict[str, Any]:
    public = _public_task(task)
    report = task.get("report") or {}
    files = report.get("files") or {}
    public.update(
        {
            "summary": report.get("summary"),
            "report_summary": report.get("report_summary"),
            "highlight_segments": report.get("highlight_segments") or [],
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


def _filter_tasks_by_user(tasks: list[dict[str, Any]], user_id: str | None) -> list[dict[str, Any]]:
    if not user_id:
        return tasks
    safe_id = _safe_user_id(user_id)
    return [task for task in tasks if task.get("user_id", DEFAULT_USER_ID) == safe_id]


def _delete_task_artifacts(task: dict[str, Any]) -> list[str]:
    deleted: list[str] = []
    upload_path = task.get("upload_path")
    if _delete_file_under(upload_path, UPLOAD_DIR):
        deleted.append(str(upload_path))

    output_dir = task.get("output_dir")
    if not output_dir:
        report = task.get("report") or {}
        files = report.get("files") if isinstance(report, dict) else {}
        first_output_url = None
        if isinstance(files, dict):
            first_output_url = (
                files.get("analysis_video")
                or files.get("highlight")
                or files.get("heatmap")
                or files.get("trajectory")
            )
        output_path = _output_url_to_path(first_output_url)
        if output_path is not None:
            output_dir = str(output_path.parent)

    if _delete_tree_under(output_dir, OUTPUTS_DIR):
        deleted.append(str(output_dir))
    return deleted


def _delete_file_under(path_value: Any, allowed_root: Path) -> bool:
    path = _safe_path_under(path_value, allowed_root)
    if path is None or not path.is_file():
        return False
    try:
        path.unlink()
        return True
    except OSError:
        return False


def _delete_tree_under(path_value: Any, allowed_root: Path) -> bool:
    path = _safe_path_under(path_value, allowed_root)
    if path is None or not path.is_dir():
        return False
    try:
        shutil.rmtree(path)
        return True
    except OSError:
        return False


def _safe_path_under(path_value: Any, allowed_root: Path) -> Path | None:
    if not path_value:
        return None
    path = Path(str(path_value))
    if not path.is_absolute():
        path = PROJECT_ROOT / path
    try:
        resolved = path.resolve()
        root = allowed_root.resolve()
    except OSError:
        return None
    if resolved == root or root not in resolved.parents:
        return None
    return resolved


def _task_corners(task: dict[str, Any]) -> list[list[int]] | None:
    raw = task.get("corners_json")
    if not raw:
        return None
    try:
        corners = json.loads(str(raw))
    except json.JSONDecodeError:
        return None
    if not isinstance(corners, list) or len(corners) != 4:
        return None
    parsed: list[list[int]] = []
    for point in corners:
        if not isinstance(point, list | tuple) or len(point) != 2:
            return None
        parsed.append([int(point[0]), int(point[1])])
    return parsed


def _failure_info(error: Any) -> dict[str, str]:
    message = str(error or "")
    lower = message.lower()
    if "cuda" in lower or "out of memory" in lower or "显存" in message:
        return {
            "code": "GPU_OUT_OF_MEMORY",
            "title": "服务器显存不足",
            "hint": "请换更短或更低分辨率的视频，或等待当前分析结束后重试。",
        }
    if "model" in lower or "weights/" in lower or "no such file" in lower or "模型" in message:
        return {
            "code": "MODEL_MISSING",
            "title": "服务器模型文件缺失",
            "hint": "请在服务器上检查 weights/yolo11n-pose.pt 和 weights/yolo11s-ball.pt 是否存在。",
        }
    if "未检测到有效球场" in message or "球员数据" in message or "court" in lower:
        return {
            "code": "DETECTION_FAILED",
            "title": "没有识别到有效比赛画面",
            "hint": "请确认视频完整拍到球场，或重新上传并手动标记四个球场角点。",
        }
    if "timeout" in lower or "timed out" in lower or "超时" in message:
        return {
            "code": "ANALYSIS_TIMEOUT",
            "title": "分析超时",
            "hint": "请换更短的视频重试；服务器忙时也可以稍后再试。",
        }
    if "服务器重启" in message:
        return {
            "code": "SERVER_RESTARTED",
            "title": "服务器重启后任务无法恢复",
            "hint": "请重新上传视频。后续任务参数会持久化，重启后会自动恢复可恢复的任务。",
        }
    return {
        "code": "ANALYSIS_ERROR",
        "title": "本次分析未完成",
        "hint": "请检查视频格式、拍摄角度和服务器状态后重试。",
    }


def _diagnostics() -> dict[str, Any]:
    disk = shutil.disk_usage(PROJECT_ROOT)
    checks: dict[str, Any] = {
        "ok": True,
        "project_root": str(PROJECT_ROOT),
        "disk": {
            "total_gb": round(disk.total / 1024**3, 2),
            "free_gb": round(disk.free / 1024**3, 2),
            "used_percent": round(disk.used / disk.total * 100, 2),
        },
        "models": {
            "pose": _model_status(PROJECT_ROOT / "weights" / "yolo11n-pose.pt"),
            "ball": _model_status(PROJECT_ROOT / "weights" / "yolo11s-ball.pt"),
        },
        "gpu": _gpu_status(),
        "database": str((PROJECT_ROOT / "mobile_backend_data" / "badminton.db").resolve()),
    }
    checks["ok"] = (
        checks["disk"]["free_gb"] > 5
        and checks["models"]["pose"]["exists"]
        and checks["models"]["ball"]["exists"]
    )
    return checks


def _model_status(path: Path) -> dict[str, Any]:
    return {
        "path": str(path),
        "exists": path.is_file(),
        "size_mb": round(path.stat().st_size / 1024**2, 2) if path.is_file() else 0,
    }


def _gpu_status() -> dict[str, Any]:
    status: dict[str, Any] = {"nvidia_smi": None, "torch": None}
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,driver_version,memory.total,memory.free",
                "--format=csv,noheader,nounits",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        rows = []
        for line in result.stdout.splitlines():
            parts = [part.strip() for part in line.split(",")]
            if len(parts) >= 4:
                rows.append(
                    {
                        "name": parts[0],
                        "driver_version": parts[1],
                        "memory_total_mb": int(float(parts[2])),
                        "memory_free_mb": int(float(parts[3])),
                    }
                )
        status["nvidia_smi"] = {"ok": True, "gpus": rows}
    except Exception as exc:  # noqa: BLE001 - diagnostic endpoint should not fail hard
        status["nvidia_smi"] = {"ok": False, "error": str(exc)}

    try:
        import torch

        status["torch"] = {
            "version": torch.__version__,
            "cuda_available": bool(torch.cuda.is_available()),
            "device": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
        }
    except Exception as exc:  # noqa: BLE001
        status["torch"] = {"cuda_available": False, "error": str(exc)}
    return status


def _safe_user_id(user_id: str | None) -> str:
    raw = (user_id or DEFAULT_USER_ID).strip()
    safe = "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in raw)
    return safe[:64] or DEFAULT_USER_ID


def _mock_demo_report() -> dict[str, Any]:
    coaching = {
        "strengths": [
            {
                "id": "fast_start_strength",
                "title": "爆发启动明显",
                "detail": "本次检测到较高峰值移动速度，说明抢点、启动和短距离冲刺能力有表现。",
                "basis": "检测最高移动速度 4.8 m/s。",
                "training_focus": "继续保持分腿垫步后再启动的节奏，避免只靠大步硬追导致下一拍回位慢。",
                "source_ids": ["bwf-coach-l1"],
            },
            {
                "id": "work_rate_strength",
                "title": "连续跑动强度较高",
                "detail": "单位时间移动距离和训练强度较高，说明这段训练包含较多连续移动或攻防转换。",
                "basis": "训练强度分 82。",
                "training_focus": "后续训练可以把快速移动和稳定回中连起来，不只看单次速度。",
                "source_ids": ["bwf-coach-l1", "badmintonskills-footwork-drills"],
            },
        ],
        "weaknesses": [
            {
                "id": "low_continuity_weakness",
                "title": "连续移动和回位衔接偏弱",
                "detail": "峰值速度不低，但平均速度或单位时间移动量偏低，可能是爆发后停顿较多，回中衔接不够连续。",
                "basis": "最高速度 4.8 m/s，平均速度 1.6 m/s。",
                "training_focus": "重点练启动、到位、回中、再启动的连续链条。",
                "source_ids": ["bwf-coach-l1"],
            }
        ],
        "improvements": [
            {
                "id": "split_step_recovery_drill",
                "title": "分腿垫步 + 回中衔接",
                "detail": "分腿垫步能把上一拍恢复和下一拍启动连接起来，帮助更快改变方向。",
                "basis": "用于把爆发速度转化成连续回合能力。",
                "training_focus": "做六点影子步：每次到点后回中，30 秒训练、30 秒休息，4 组；保持低重心，启动前做分腿垫步。",
                "source_ids": ["bwf-coach-l1", "badmintonskills-footwork-drills"],
            },
            {
                "id": "multi_directional_drill",
                "title": "多方向连续移动",
                "detail": "比赛移动通常是多个方向连续切换，训练应把启动、到位、回中和再次启动连成循环。",
                "basis": "提高连续多拍下的移动质量。",
                "training_focus": "做多方向抛球/喂球：30-60 秒连续移动，休息 60-90 秒，4 组；每拍后都回到合理中区。",
                "source_ids": ["bwf-coach-l1", "badmintonskills-footwork-drills"],
            },
        ],
    }
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
            "active_time_sec": 60.0,
            "distance_per_min": 438.0,
            "coverage_area_m2": 31.5,
            "court_span_x_m": 5.0,
            "court_span_y_m": 6.3,
            "shuttlecock_ratio": 0.53,
        },
        "players": [],
        "coaching": coaching,
        "advice": [
            "当前优点：爆发启动明显。本次检测到较高峰值移动速度，说明抢点、启动和短距离冲刺能力有表现。",
            "目前缺点：连续移动和回位衔接偏弱。峰值速度不低，但平均速度或单位时间移动量偏低，可能是爆发后停顿较多。",
            "改进建议：分腿垫步 + 回中衔接。做六点影子步：每次到点后回中，30 秒训练、30 秒休息，4 组。",
        ],
        "advice_sources": load_advice_knowledge()["sources"],
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


# ---------------------------------------------------------------------------
# Task storage (SQLite via SQLAlchemy)
# ---------------------------------------------------------------------------


def _set_task(task_id: str, task_data: dict[str, Any]) -> None:
    """Insert a new task row into the database."""
    session = get_session()
    try:
        user_id = task_data.get("user_id", DEFAULT_USER_ID)
        now = time.time()
        session.execute(
            sqlite_insert(User)
            .values(user_id=user_id, created_at=now, updated_at=now)
            .on_conflict_do_nothing(index_elements=[User.user_id])
        )
        task = Task(
            task_id=task_id,
            user_id=user_id,
            status=task_data.get("status", "queued"),
            progress=float(task_data.get("progress", 0.0)),
            stage=task_data.get("stage", "queued"),
            error=task_data.get("error"),
            video_name=task_data.get("video_name", ""),
            upload_path=task_data.get("upload_path", ""),
            template_path=task_data.get("template_path", ""),
            output_dir=task_data.get("output_dir"),
            corners_json=task_data.get("corners_json"),
            language=task_data.get("language", "zh"),
            pose_mode=task_data.get("pose_mode", "balanced"),
            keep_audio=bool(task_data.get("keep_audio", True)),
            created_at=task_data.get("created_at", time.time()),
            updated_at=task_data.get("updated_at", time.time()),
        )
        session.add(task)
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def _update_task(task_id: str, **changes: Any) -> None:
    """Update fields on an existing task row."""
    session = get_session()
    try:
        task = session.get(Task, task_id)
        if task is None:
            return
        if "report" in changes:
            task.report = changes.pop("report")
        for key, value in changes.items():
            if hasattr(task, key):
                setattr(task, key, value)
        task.updated_at = time.time()
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def _get_task_or_404(task_id: str) -> dict[str, Any]:
    """Fetch a task dict, raising 404-style HTTPException if missing."""
    session = get_session()
    try:
        task = session.get(Task, task_id)
        if task is None:
            raise_api_error(
                status_code=404,
                code="TASK_NOT_FOUND",
                message="任务不存在。",
                hint="请检查 task_id 是否正确。",
            )
        return task_to_legacy_dict(task)
    finally:
        session.close()


def _load_all_tasks() -> list[dict[str, Any]]:
    """Return all tasks as legacy dicts."""
    session = get_session()
    try:
        return [task_to_legacy_dict(t) for t in session.query(Task).all()]
    finally:
        session.close()


def _claim_next_task() -> dict[str, Any] | None:
    """Atomically claim the oldest queued task across worker processes."""
    while True:
        session = get_session()
        try:
            candidate = (
                session.query(Task.task_id)
                .filter(Task.status == "queued")
                .order_by(Task.created_at.asc(), Task.task_id.asc())
                .first()
            )
            if candidate is None:
                return None
            now = time.time()
            changed = (
                session.query(Task)
                .filter(Task.task_id == candidate[0], Task.status == "queued")
                .update(
                    {
                        Task.status: "processing",
                        Task.stage: "starting_worker",
                        Task.progress: 0.01,
                        Task.error: None,
                        Task.updated_at: now,
                    },
                    synchronize_session=False,
                )
            )
            session.commit()
            if changed:
                claimed = session.get(Task, candidate[0])
                return task_to_legacy_dict(claimed) if claimed is not None else None
        except Exception:
            session.rollback()
            raise
        finally:
            session.close()


def _run_claimed_task(task: dict[str, Any]) -> None:
    try:
        _run_analysis_task(
            task_id=task["task_id"],
            video_path=str(task.get("upload_path") or ""),
            template_path=str(task.get("template_path") or ""),
            corners=_task_corners(task),
            language=str(task.get("language") or "zh"),
            pose_mode=str(task.get("pose_mode") or "balanced"),
            keep_audio=bool(task.get("keep_audio", True)),
        )
    finally:
        gc.collect()
        try:
            import torch

            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except Exception:
            pass


def _fail_unhandled_task(task_id: str, exc: Exception) -> None:
    _update_task(
        task_id,
        status="failed",
        stage="failed",
        progress=1.0,
        error=f"Analysis worker failed unexpectedly: {exc}",
    )


def _queue_position(task: dict[str, Any]) -> int | None:
    created_at = task.get("created_at")
    task_id = task.get("task_id")
    if created_at is None or not task_id:
        return None
    session = get_session()
    try:
        ahead = (
            session.query(Task)
            .filter(
                Task.status == "queued",
                or_(
                    Task.created_at < float(created_at),
                    (Task.created_at == float(created_at)) & (Task.task_id < str(task_id)),
                ),
            )
            .count()
        )
        return ahead + 1
    finally:
        session.close()


def _queue_summary() -> dict[str, Any]:
    session = get_session()
    try:
        queued = session.query(Task).filter(Task.status == "queued").count()
        processing = session.query(Task).filter(Task.status == "processing").count()
        return {
            "queued": queued,
            "processing": processing,
            "worker_running": TASK_WORKER.running,
            "capacity": TASK_WORKER.capacity,
            "active_workers": TASK_WORKER.active_workers,
            "capacity_reason": ANALYSIS_CAPACITY_INFO,
        }
    finally:
        session.close()



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
            message="视频文件过大，请上传 200MB 以内的视频。",
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


TASK_WORKER = DurableTaskWorker(
    claim_next=_claim_next_task,
    run_task=_run_claimed_task,
    fail_task=_fail_unhandled_task,
    worker_count=ANALYSIS_WORKER_COUNT,
)
