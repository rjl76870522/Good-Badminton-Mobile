import os
import time
from pathlib import Path

from badminton_analysis.database import Task, User, get_session, init_db
from badminton_analysis.storage_maintenance import RetentionPolicy, run_maintenance


def _task(
    root: Path,
    task_id: str,
    *,
    age_days: int,
    retained: bool = False,
    status: str = "completed",
) -> None:
    upload = root / "mobile_backend_data" / "uploads" / f"{task_id}.mp4"
    output = root / "outputs" / task_id
    upload.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    upload.write_bytes(b"video")
    (output / "report.json").write_text("{}", encoding="utf-8")
    timestamp = time.time() - age_days * 86400
    session = get_session()
    session.merge(User(user_id="tester", created_at=timestamp, updated_at=timestamp))
    session.add(
        Task(
            task_id=task_id,
            user_id="tester",
            status=status,
            progress=1.0,
            stage=status,
            video_name=upload.name,
            upload_path=str(upload),
            template_path="",
            output_dir=str(output),
            retained=retained,
            created_at=timestamp,
            updated_at=timestamp,
        )
    )
    session.commit()
    session.close()


def test_maintenance_respects_retention_and_age_thresholds(tmp_path):
    db = tmp_path / "mobile_backend_data" / "badminton.db"
    init_db(db)
    _task(tmp_path, "upload-old", age_days=31)
    _task(tmp_path, "task-old", age_days=91)
    _task(tmp_path, "retained", age_days=120, retained=True)

    result = run_maintenance(
        tmp_path,
        tmp_path / "backups",
        RetentionPolicy(),
    )

    session = get_session()
    upload_old = session.get(Task, "upload-old")
    assert upload_old is not None
    assert upload_old.upload_deleted_at is not None
    assert not Path(upload_old.upload_path).exists()
    assert session.get(Task, "task-old") is None
    retained = session.get(Task, "retained")
    assert retained is not None
    assert Path(retained.upload_path).exists()
    session.close()
    assert result["uploads_deleted"] == 1
    assert result["tasks_deleted"] == 1
    assert result["backed_up"] is True


def test_maintenance_removes_stale_preview_cache(tmp_path):
    db = tmp_path / "mobile_backend_data" / "badminton.db"
    init_db(db)
    preview = tmp_path / "mobile_backend_data" / "preview_uploads" / "old.mp4"
    preview.parent.mkdir(parents=True)
    preview.write_bytes(b"preview")
    old = time.time() - 25 * 3600
    os.utime(preview, (old, old))

    result = run_maintenance(tmp_path, tmp_path / "backups")

    assert not preview.exists()
    assert result["preview_files_deleted"] == 1
