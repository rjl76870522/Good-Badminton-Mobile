"""SQLite database layer for Good-Badminton mobile backend.

Replaces the JSON-file-based user registry and task storage with SQLAlchemy + SQLite.
"""

from __future__ import annotations

import json
import logging
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import (
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    create_engine,
    event,
    func,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, relationship, sessionmaker

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Engine & session factory
# ---------------------------------------------------------------------------

_engine = None
_SessionLocal = None


def init_db(db_path: str | Path = "mobile_backend_data/badminton.db") -> None:
    """Initialize the SQLite engine and create all tables.

    Call once at startup — idempotent (CREATE TABLE IF NOT EXISTS).
    """
    global _engine, _SessionLocal  # noqa: PLW0603

    db_path = Path(db_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)

    _engine = create_engine(
        f"sqlite:///{db_path}",
        echo=False,
        connect_args={"check_same_thread": False, "timeout": 30},
        json_serializer=lambda obj: json.dumps(obj, ensure_ascii=False),
    )

    # WAL permits concurrent readers; busy_timeout lets short writer bursts queue.
    @event.listens_for(_engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, _connection_record):  # noqa: ANN001
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA busy_timeout=30000")
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    Base.metadata.create_all(bind=_engine)

    _SessionLocal = sessionmaker(bind=_engine, autoflush=False, autocommit=False)

    logger.info("Database initialized at %s", db_path.resolve())


def get_session() -> Session:
    """Return a new SQLAlchemy Session."""
    if _SessionLocal is None:
        raise RuntimeError("Database not initialized — call init_db() first.")
    return _SessionLocal()


# ---------------------------------------------------------------------------
# ORM Base
# ---------------------------------------------------------------------------


class Base(DeclarativeBase):
    pass


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class User(Base):
    __tablename__ = "users"

    user_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    display_name: Mapped[str | None] = mapped_column(String(128), default=None)
    linked_user_ids: Mapped[str | None] = mapped_column(
        Text, default=None
    )  # JSON list of merged guest IDs
    created_at: Mapped[float] = mapped_column(Float, default=time.time)
    updated_at: Mapped[float] = mapped_column(Float, default=time.time, onupdate=time.time)

    tasks: Mapped[list[Task]] = relationship(
        "Task", back_populates="user", cascade="all, delete-orphan"
    )

    def to_dict(self) -> dict[str, Any]:
        return {
            "user_id": self.user_id,
            "display_name": self.display_name,
            "linked_user_ids": json.loads(self.linked_user_ids)
            if self.linked_user_ids
            else [],
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


class Task(Base):
    __tablename__ = "tasks"

    task_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), ForeignKey("users.user_id"), index=True)
    status: Mapped[str] = mapped_column(String(32), default="queued", index=True)
    progress: Mapped[float] = mapped_column(Float, default=0.0)
    stage: Mapped[str] = mapped_column(String(64), default="queued")
    error: Mapped[str | None] = mapped_column(Text, default=None)
    video_name: Mapped[str] = mapped_column(String(256))
    upload_path: Mapped[str] = mapped_column(String(1024))
    template_path: Mapped[str] = mapped_column(String(1024), default="")
    output_dir: Mapped[str | None] = mapped_column(String(1024), default=None)
    corners_json: Mapped[str | None] = mapped_column(Text, default=None)
    language: Mapped[str] = mapped_column(String(8), default="zh")
    pose_mode: Mapped[str] = mapped_column(String(32), default="balanced")
    keep_audio: Mapped[bool] = mapped_column(default=True)
    report_json: Mapped[str | None] = mapped_column(Text, default=None)
    created_at: Mapped[float] = mapped_column(Float, default=time.time)
    updated_at: Mapped[float] = mapped_column(Float, default=time.time, onupdate=time.time)

    user: Mapped[User] = relationship("User", back_populates="tasks")
    output_files: Mapped[list[OutputFile]] = relationship(
        "OutputFile", back_populates="task", cascade="all, delete-orphan"
    )

    def to_dict(self, include_report: bool = False) -> dict[str, Any]:
        data = {
            "task_id": self.task_id,
            "user_id": self.user_id,
            "status": self.status,
            "progress": self.progress,
            "stage": self.stage,
            "error": self.error,
            "video_name": self.video_name,
            "upload_path": self.upload_path,
            "template_path": self.template_path,
            "output_dir": self.output_dir,
            "corners_json": self.corners_json,
            "language": self.language,
            "pose_mode": self.pose_mode,
            "keep_audio": self.keep_audio,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }
        if include_report and self.report_json:
            try:
                data["report"] = json.loads(self.report_json)
            except json.JSONDecodeError:
                data["report"] = None
        else:
            data["report"] = None
        return data

    @property
    def report(self) -> dict[str, Any] | None:
        """Deserialize report_json back to a dict."""
        if not self.report_json:
            return None
        try:
            return json.loads(self.report_json)
        except json.JSONDecodeError:
            return None

    @report.setter
    def report(self, value: dict[str, Any] | None) -> None:
        """Serialize a report dict into report_json."""
        self.report_json = json.dumps(value, ensure_ascii=False) if value else None

    @property
    def corners(self) -> list[list[int]] | None:
        if not self.corners_json:
            return None
        try:
            return json.loads(self.corners_json)
        except json.JSONDecodeError:
            return None

    @corners.setter
    def corners(self, value: list[list[int]] | None) -> None:
        self.corners_json = json.dumps(value) if value else None


class OutputFile(Base):
    __tablename__ = "output_files"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    task_id: Mapped[str] = mapped_column(String(64), ForeignKey("tasks.task_id"), index=True)
    file_type: Mapped[str] = mapped_column(
        String(32)
    )  # analysis_video, highlight, metadata, detections, heatmap, trajectory
    url: Mapped[str] = mapped_column(String(1024))
    created_at: Mapped[float] = mapped_column(Float, default=time.time)

    task: Mapped[Task] = relationship("Task", back_populates="output_files")

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "task_id": self.task_id,
            "file_type": self.file_type,
            "url": self.url,
            "created_at": self.created_at,
        }


# ---------------------------------------------------------------------------
# Helper: dict-compatible task repr (backward compat with old code)
# ---------------------------------------------------------------------------


def task_to_legacy_dict(task: Task) -> dict[str, Any]:
    """Convert a Task ORM object back to the dict shape that
    _public_task / _history_item and the rest of backend_api expect."""
    report = task.report
    return {
        "task_id": task.task_id,
        "user_id": task.user_id,
        "status": task.status,
        "progress": task.progress,
        "stage": task.stage,
        "error": task.error,
        "video_name": task.video_name,
        "upload_path": task.upload_path,
        "template_path": task.template_path,
        "output_dir": task.output_dir,
        "corners_json": task.corners_json,
        "language": task.language,
        "pose_mode": task.pose_mode,
        "keep_audio": task.keep_audio,
        "report": report,
        "created_at": task.created_at,
        "updated_at": task.updated_at,
    }
