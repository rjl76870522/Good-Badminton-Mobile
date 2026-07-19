"""Safe scheduled backup and retention cleanup for the mobile backend."""

from __future__ import annotations

import argparse
import shutil
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path

from badminton_analysis.database import Task, get_session, init_db


@dataclass(frozen=True)
class RetentionPolicy:
    failed_days: int = 7
    preview_hours: int = 24
    backup_days: int = 30


def run_maintenance(
    project_root: Path,
    backup_dir: Path,
    policy: RetentionPolicy = RetentionPolicy(),
    *,
    now: float | None = None,
    dry_run: bool = False,
) -> dict[str, int | float | bool]:
    root = project_root.resolve()
    db_path = root / "mobile_backend_data" / "badminton.db"
    uploads_dir = root / "mobile_backend_data" / "uploads"
    outputs_dir = root / "outputs"
    preview_dirs = (
        root / "mobile_backend_data" / "preview_uploads",
        root / "mobile_backend_data" / "preview_frames",
    )
    timestamp = now if now is not None else time.time()
    result: dict[str, int | float | bool] = {
        "backed_up": False,
        "uploads_deleted": 0,
        "tasks_deleted": 0,
        "preview_files_deleted": 0,
        "old_backups_deleted": 0,
    }

    if not dry_run:
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup_path = backup_dir / time.strftime(
            "badminton-%Y%m%d-%H%M%S.db",
            time.localtime(timestamp),
        )
        _backup_sqlite(db_path, backup_path)
        result["backed_up"] = True

    init_db(db_path)
    session = get_session()
    try:
        tasks = session.query(Task).all()
        for task in tasks:
            if task.status in {"queued", "processing", "completed"}:
                continue
            age = max(0.0, timestamp - task.updated_at)
            delete_task = task.status in {"failed", "cancelled"} and (
                age >= policy.failed_days * 86400
            )
            if delete_task:
                if not dry_run:
                    _delete_file(task.upload_path, uploads_dir)
                    _delete_tree(task.output_dir, outputs_dir)
                    session.delete(task)
                result["tasks_deleted"] = int(result["tasks_deleted"]) + 1
        if not dry_run:
            session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()

    preview_cutoff = timestamp - policy.preview_hours * 3600
    for directory in preview_dirs:
        if not directory.is_dir():
            continue
        for path in directory.iterdir():
            if path.is_file() and path.stat().st_mtime < preview_cutoff:
                if not dry_run:
                    path.unlink(missing_ok=True)
                result["preview_files_deleted"] = (
                    int(result["preview_files_deleted"]) + 1
                )

    backup_cutoff = timestamp - policy.backup_days * 86400
    if backup_dir.is_dir():
        for path in backup_dir.glob("badminton-*.db"):
            if path.is_file() and path.stat().st_mtime < backup_cutoff:
                if not dry_run:
                    path.unlink(missing_ok=True)
                result["old_backups_deleted"] = (
                    int(result["old_backups_deleted"]) + 1
                )

    usage = shutil.disk_usage(root)
    result["disk_used_percent"] = round(usage.used / usage.total * 100, 2)
    return result


def _backup_sqlite(source: Path, target: Path) -> None:
    with sqlite3.connect(source) as source_db, sqlite3.connect(target) as target_db:
        source_db.backup(target_db)


def _safe_path(value: str | None, root: Path) -> Path | None:
    if not value:
        return None
    path = Path(value)
    if not path.is_absolute():
        path = root.parent / path
    try:
        resolved = path.resolve()
        resolved.relative_to(root.resolve())
    except (OSError, ValueError):
        return None
    return resolved


def _delete_file(value: str | None, root: Path) -> None:
    path = _safe_path(value, root)
    if path is not None and path.is_file():
        path.unlink()


def _delete_tree(value: str | None, root: Path) -> None:
    path = _safe_path(value, root)
    if path is not None and path.is_dir():
        shutil.rmtree(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--backup-dir",
        type=Path,
        default=Path("/data/backups/good-badminton/daily"),
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    result = run_maintenance(
        args.project_root,
        args.backup_dir,
        dry_run=args.dry_run,
    )
    print(result)


if __name__ == "__main__":
    main()
