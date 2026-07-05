from pathlib import Path

from fastapi.testclient import TestClient

import backend_api


def _configure_data_dirs(monkeypatch, tmp_path: Path) -> None:
    for name in ("UPLOAD_DIR", "TASK_DIR", "PREVIEW_DIR", "SOURCE_DIR", "OUTPUTS_DIR"):
        directory = tmp_path / name.lower()
        directory.mkdir()
        monkeypatch.setattr(backend_api, name, directory)
    backend_api.TASKS.clear()


def _fake_preview(video_path: Path, source_upload_id: str) -> dict:
    preview_path = backend_api.PREVIEW_DIR / f"{source_upload_id}.jpg"
    preview_path.write_bytes(b"preview")
    return {
        "source_upload_id": source_upload_id,
        "image_url": f"/api/videos/preview-images/{source_upload_id}",
        "image_path": str(preview_path),
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


def test_preview_then_source_upload_matches_flutter_contract(monkeypatch, tmp_path):
    _configure_data_dirs(monkeypatch, tmp_path)
    monkeypatch.setattr(backend_api, "_extract_preview_frame", _fake_preview)
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
        assert preview["image_url"].startswith("/api/videos/preview-images/")
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
    assert response.status_code == 415


def test_legacy_direct_file_upload_still_works(monkeypatch, tmp_path):
    _configure_data_dirs(monkeypatch, tmp_path)
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
