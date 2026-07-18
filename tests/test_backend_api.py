from pathlib import Path
import time

import cv2
from fastapi.testclient import TestClient
import numpy as np

import backend_api


def _configure_data_dirs(monkeypatch, tmp_path: Path) -> None:
    for name in (
        "UPLOAD_DIR",
        "TASK_DIR",
        "PREVIEW_FRAME_DIR",
        "PREVIEW_UPLOAD_DIR",
        "OUTPUTS_DIR",
    ):
        directory = tmp_path / name.lower()
        directory.mkdir()
        monkeypatch.setattr(backend_api, name, directory)
    backend_api.init_db(tmp_path / "badminton.db")


def _fake_preview(video_path: Path, source_upload_id: str) -> dict:
    preview_path = backend_api.PREVIEW_FRAME_DIR / f"{source_upload_id}.jpg"
    preview_path.write_bytes(b"preview")
    return {
        "image_url": f"/preview-frames/{source_upload_id}.jpg",
        "frame_index": 15,
        "time_sec": 0.5,
        "selection_reason": "best_quality_sample",
        "auto_corners": [],
        "video": {
            "width": 1280,
            "height": 720,
            "duration_sec": 5.0,
            "fps": 30.0,
            "total_frames": 150,
        },
        "quality": {"score": 0.8},
    }


def _insert_queued_task(tmp_path: Path, task_id: str, created_at: float, user_id: str = "queue-user"):
    video_path = tmp_path / f"{task_id}.mp4"
    template_path = tmp_path / f"{task_id}.png"
    video_path.write_bytes(b"video")
    template_path.write_bytes(b"template")
    backend_api._set_task(
        task_id,
        {
            "task_id": task_id,
            "user_id": user_id,
            "status": "queued",
            "stage": "queued",
            "video_name": video_path.name,
            "upload_path": str(video_path),
            "template_path": str(template_path),
            "created_at": created_at,
            "updated_at": created_at,
        },
    )


def test_preview_then_source_upload_matches_flutter_contract(monkeypatch, tmp_path):
    _configure_data_dirs(monkeypatch, tmp_path)
    monkeypatch.setattr(backend_api, "_select_preview_frame", _fake_preview)
    monkeypatch.setattr(backend_api, "_validate_uploaded_video", lambda _path: None)
    monkeypatch.setattr(
        backend_api,
        "_validate_corners_for_video",
        lambda _corners, _path: None,
    )
    monkeypatch.setattr(backend_api, "_run_analysis_task", lambda **_kwargs: None)

    with TestClient(backend_api.app) as client:
        preview_response = client.post(
            "/api/videos/preview-frame",
            data={"user_id": "phone-user"},
            files={"file": ("training.mp4", b"video-bytes", "video/mp4")},
        )
        assert preview_response.status_code == 200
        preview = preview_response.json()
        assert preview["source_upload_id"]
        assert preview["image_url"].startswith("/preview-frames/")
        assert preview["video"]["width"] == 1280
        assert "image_path" not in preview

        upload_response = client.post(
            "/api/videos/upload",
            data={
                "source_upload_id": preview["source_upload_id"],
                "user_id": "phone-user",
                "language": "zh",
                "pose_mode": "balanced",
                "keep_audio": "true",
                "corners_json": "[[1,2],[3,4],[5,6],[7,8]]",
            },
        )
        assert upload_response.status_code == 200
        upload = upload_response.json()
        assert upload["status"] == "queued"
        assert upload["status_url"] == f"/api/tasks/{upload['task_id']}"

        status = client.get(upload["status_url"]).json()
        assert status["user_id"] == "phone-user"
        assert status["video_name"] == "training.mp4"
        task = backend_api._get_task_or_404(upload["task_id"])
        assert Path(task["upload_path"]).read_bytes() == b"video-bytes"
        assert not list(
            backend_api.PREVIEW_UPLOAD_DIR.glob(
                f"{preview['source_upload_id']}_*",
            ),
        )
        assert not (
            backend_api.PREVIEW_FRAME_DIR
            / f"{preview['source_upload_id']}.jpg"
        ).exists()

        own_history = client.get("/api/history", params={"user_id": "phone-user"}).json()
        other_history = client.get("/api/history", params={"user_id": "someone-else"}).json()
        assert own_history["total"] == 1
        assert other_history["total"] == 0


def test_upload_rejects_unsupported_video(monkeypatch, tmp_path):
    _configure_data_dirs(monkeypatch, tmp_path)
    with TestClient(backend_api.app) as client:
        response = client.post(
            "/api/videos/upload",
            files={"file": ("notes.txt", b"not-a-video", "text/plain")},
        )
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "VIDEO_UNREADABLE"


def test_legacy_direct_file_upload_still_works(monkeypatch, tmp_path):
    _configure_data_dirs(monkeypatch, tmp_path)
    monkeypatch.setattr(backend_api, "_validate_uploaded_video", lambda _path: None)
    monkeypatch.setattr(backend_api, "_run_analysis_task", lambda **_kwargs: None)

    with TestClient(backend_api.app) as client:
        response = client.post(
            "/api/videos/upload",
            data={"user_id": "legacy-user"},
            files={"file": ("match.MP4", b"video-bytes", "video/mp4")},
        )

    assert response.status_code == 200
    task = backend_api._get_task_or_404(response.json()["task_id"])
    assert task["video_name"] == "match.MP4"
    assert Path(task["upload_path"]).read_bytes() == b"video-bytes"


def test_output_path_converts_to_public_url(monkeypatch, tmp_path):
    _configure_data_dirs(monkeypatch, tmp_path)
    output = backend_api.OUTPUTS_DIR / "job"
    output.mkdir()
    expected = output / "detect_match.mp4"
    expected.write_bytes(b"x" * 2048)

    resolved = backend_api._path_to_output_url(expected)

    assert resolved == "/outputs/job/detect_match.mp4"


def test_durable_queue_claims_fifo_and_updates_positions(monkeypatch, tmp_path):
    _configure_data_dirs(monkeypatch, tmp_path)
    now = time.time()
    _insert_queued_task(tmp_path, "task-b", now + 1)
    _insert_queued_task(tmp_path, "task-a", now)
    _insert_queued_task(tmp_path, "task-c", now + 2)

    assert backend_api._public_task(backend_api._get_task_or_404("task-a"))["queue_position"] == 1
    assert backend_api._public_task(backend_api._get_task_or_404("task-b"))["queue_position"] == 2
    assert backend_api._public_task(backend_api._get_task_or_404("task-c"))["queue_position"] == 3

    claimed = backend_api._claim_next_task()

    assert claimed is not None
    assert claimed["task_id"] == "task-a"
    assert claimed["status"] == "processing"
    assert backend_api._public_task(backend_api._get_task_or_404("task-b"))["queue_position"] == 1


def test_gpu_capacity_recommendation_is_conservative():
    assert backend_api._recommend_analysis_workers(8_000, 7_000) == 1
    assert backend_api._recommend_analysis_workers(16_384, 10_000) == 2
    assert backend_api._recommend_analysis_workers(16_384, 14_000) == 4
    assert backend_api._recommend_analysis_workers(24_576, 17_000) == 3
    assert backend_api._recommend_analysis_workers(24_576, 20_000) == 4


def test_preview_score_warns_when_auto_corners_are_missing(monkeypatch):
    frame = np.full((240, 320, 3), 100, dtype=np.uint8)
    cv2.line(frame, (40, 60), (280, 60), (255, 255, 255), 3)
    cv2.line(frame, (40, 180), (280, 180), (255, 255, 255), 3)
    cv2.line(frame, (40, 60), (40, 180), (255, 255, 255), 3)
    cv2.line(frame, (280, 60), (280, 180), (255, 255, 255), 3)
    monkeypatch.setattr(backend_api, "auto_detect_preview", lambda *_args, **_kwargs: (None, None))

    scored = backend_api._score_preview_frame(frame, 30, 30.0, detect_court=True)

    assert scored["usable"] is True
    assert scored["auto_corners"] is None
    assert scored["scene_warning"] is not None
    assert "手动点选" in scored["scene_warning"]


def test_cancel_only_changes_queued_tasks(monkeypatch, tmp_path):
    _configure_data_dirs(monkeypatch, tmp_path)
    now = time.time()
    _insert_queued_task(tmp_path, "cancel-me", now)

    cancelled = backend_api.cancel_task("cancel-me", user_id="queue-user")

    assert cancelled["status"] == "cancelled"
    assert cancelled["stage"] == "cancelled"
    assert cancelled["queue_position"] is None


def test_recovery_requeues_interrupted_tasks_without_spawning_threads(monkeypatch, tmp_path):
    _configure_data_dirs(monkeypatch, tmp_path)
    _insert_queued_task(tmp_path, "interrupted", time.time())
    backend_api._update_task(
        "interrupted",
        status="processing",
        stage="analyzing_video",
        progress=0.5,
    )

    backend_api.recover_persisted_tasks()

    recovered = backend_api._get_task_or_404("interrupted")
    assert recovered["status"] == "queued"
    assert recovered["stage"] == "queued_after_restart"
    assert recovered["progress"] == 0.0
