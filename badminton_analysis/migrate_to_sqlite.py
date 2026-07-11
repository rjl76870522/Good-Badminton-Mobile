"""One-shot migration from JSON files to SQLite.

Reads:
    mobile_backend_data/users.json
    mobile_backend_data/tasks/*.json

Writes to:
    mobile_backend_data/badminton.db

Safe to run multiple times — skips already-migrated records.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_PROJECT_ROOT))

from badminton_analysis.database import (
    OutputFile,
    Task,
    User,
    get_session,
    init_db,
)


def migrate(db_path: str | Path = "mobile_backend_data/badminton.db") -> dict[str, int]:
    """Run the migration. Returns counts: {users, tasks, output_files, skipped_users, skipped_tasks}."""
    init_db(db_path)
    session = get_session()

    counts = {
        "users": 0,
        "tasks": 0,
        "output_files": 0,
        "skipped_users": 0,
        "skipped_tasks": 0,
    }

    data_dir = _PROJECT_ROOT / "mobile_backend_data"

    # ── Migrate users ──────────────────────────────────────────
    users_path = data_dir / "users.json"
    if users_path.is_file():
        try:
            users_data = json.loads(users_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            users_data = {}
        users = users_data.get("users") if isinstance(users_data, dict) else {}
        if isinstance(users, dict):
            for user_id, user_info in users.items():
                if not isinstance(user_info, dict):
                    continue
                normalized_id = str(user_info.get("user_id") or user_id).strip().lower()
                if session.get(User, normalized_id):
                    counts["skipped_users"] += 1
                    continue
                session.add(
                    User(
                        user_id=normalized_id,
                        created_at=_to_float(user_info.get("created_at")),
                        updated_at=_to_float(user_info.get("updated_at")),
                    )
                )
                counts["users"] += 1

    # ── Ensure users are persisted before task migration ──────
    try:
        session.commit()
    except Exception:
        session.rollback()
        raise

    # ── Migrate tasks ──────────────────────────────────────────
    tasks_dir = data_dir / "tasks"
    if tasks_dir.is_dir():
        for task_file in sorted(tasks_dir.glob("*.json")):
            try:
                task_data = json.loads(task_file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            task_id = task_data.get("task_id")
            if not task_id:
                continue
            if session.get(Task, task_id):
                counts["skipped_tasks"] += 1
                continue

            user_id = str(task_data.get("user_id") or "guest").strip()
            user = session.get(User, user_id)
            if user is None:
                user = User(user_id=user_id, created_at=task_data.get("created_at", 0))
                session.add(user)

            task = Task(
                task_id=task_id,
                user_id=user_id,
                status=task_data.get("status", "completed"),
                progress=float(task_data.get("progress", 1.0)),
                stage=task_data.get("stage", "completed"),
                error=task_data.get("error"),
                video_name=task_data.get("video_name", ""),
                upload_path=task_data.get("upload_path", ""),
                template_path=task_data.get("template_path", ""),
                output_dir=task_data.get("output_dir"),
                language=task_data.get("language", "zh"),
                pose_mode=task_data.get("pose_mode", "balanced"),
                keep_audio=task_data.get("keep_audio", True),
                created_at=_to_float(task_data.get("created_at")),
                updated_at=_to_float(task_data.get("updated_at")),
            )
            report = task_data.get("report")
            if report:
                task.report = report

            session.add(task)
            counts["tasks"] += 1

            # ── Migrate output files from report ────────────────
            if isinstance(report, dict):
                files = report.get("files") or {}
                for file_type in [
                    "analysis_video",
                    "highlight",
                    "metadata",
                    "detections",
                    "heatmap",
                    "trajectory",
                ]:
                    url = files.get(file_type)
                    if url and isinstance(url, str):
                        session.add(
                            OutputFile(task_id=task_id, file_type=file_type, url=url)
                        )
                        counts["output_files"] += 1

                visualizations = files.get("visualizations") or []
                if isinstance(visualizations, list):
                    for vis in visualizations:
                        if vis and isinstance(vis, str):
                            session.add(
                                OutputFile(
                                    task_id=task_id,
                                    file_type="visualization",
                                    url=vis,
                                )
                            )
                            counts["output_files"] += 1

    session.commit()
    session.close()
    return counts


def _to_float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


if __name__ == "__main__":
    result = migrate()
    print("Migration complete:")
    print(f"  Users:          {result['users']} imported ({result['skipped_users']} skipped)")
    print(f"  Tasks:          {result['tasks']} imported ({result['skipped_tasks']} skipped)")
    print(f"  Output files:   {result['output_files']} imported")
    print(f"  Database:       mobile_backend_data/badminton.db")
