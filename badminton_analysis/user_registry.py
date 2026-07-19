"""SQLite-backed user registry for the mobile demo backend.

Uses SQLAlchemy via the shared database module.
Falls back to in-memory dict if the database hasn't been initialized.
"""

from __future__ import annotations

import re
import time
from typing import Any

from badminton_analysis.database import User, get_session

USER_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_-]{2,31}$")


class UserRegistryError(ValueError):
    """Base class for user registry validation errors."""


class InvalidUserId(UserRegistryError):
    """Raised when a requested user id cannot be used."""


class UserAlreadyExists(UserRegistryError):
    """Raised when registering an already claimed user id."""


class UserNotFound(UserRegistryError):
    """Raised when a registered user cannot be found."""


def normalize_user_id(user_id: str | None) -> str:
    raw = (user_id or "").strip().lower()
    if not USER_ID_PATTERN.fullmatch(raw):
        raise InvalidUserId(
            "user_id must be 3-32 chars and use lowercase letters, numbers, '_' or '-'."
        )
    return raw


# ---------------------------------------------------------------------------
# Public API — these replace the old path-based functions
# ---------------------------------------------------------------------------


def register_user(*, user_id: str) -> dict[str, Any]:
    """Register a new user. Raises UserAlreadyExists if duplicate."""
    normalized_id = normalize_user_id(user_id)
    session = _session()
    try:
        if session.get(User, normalized_id):
            raise UserAlreadyExists(f"user_id already exists: {normalized_id}")

        now = time.time()
        user = User(user_id=normalized_id, created_at=now, updated_at=now)
        session.add(user)
        session.commit()
        return user.to_dict()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def get_user(user_id: str) -> dict[str, Any]:
    """Look up a user by ID. Raises UserNotFound if missing."""
    normalized_id = normalize_user_id(user_id)
    session = _session()
    try:
        user = session.get(User, normalized_id)
        if user is None:
            raise UserNotFound(f"user not found: {normalized_id}")
        return user.to_dict()
    finally:
        session.close()


def update_display_name(*, user_id: str, display_name: str) -> dict[str, Any]:
    """Set or change a user's display name. Names can be anything, duplicates allowed."""
    normalized_id = normalize_user_id(user_id)
    name = display_name.strip()[:128]
    session = _session()
    try:
        user = session.get(User, normalized_id)
        if user is None:
            raise UserNotFound(f"user not found: {normalized_id}")
        user.display_name = name if name else None
        user.updated_at = time.time()
        session.commit()
        return user.to_dict()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def search_users_by_display_name(display_name: str, limit: int = 20) -> list[dict[str, Any]]:
    """Search users by display name (fuzzy LIKE match). Returns list of matches."""
    from badminton_analysis.database import User as UserModel

    search = f"%{display_name.strip()[:64]}%"
    session = _session()
    try:
        users = (
            session.query(UserModel)
            .filter(UserModel.display_name.ilike(search))
            .limit(limit)
            .all()
        )
        return [u.to_dict() for u in users]
    finally:
        session.close()


def link_user_ids(*, primary_user_id: str, linked_user_id: str) -> dict[str, Any]:
    """Merge linked_user_id into primary_user_id so all their tasks appear under primary."""
    import json

    primary_id = normalize_user_id(primary_user_id)
    linked_id = normalize_user_id(linked_user_id)
    if primary_id == linked_id:
        raise InvalidUserId("Cannot link a user to itself.")

    session = _session()
    try:
        primary = session.get(User, primary_id)
        if primary is None:
            raise UserNotFound(f"user not found: {primary_id}")
        linked = session.get(User, linked_id)
        if linked is None:
            raise UserNotFound(f"user not found: {linked_id}")

        # Collect existing linked IDs
        existing = (
            json.loads(primary.linked_user_ids) if primary.linked_user_ids else []
        )
        if linked_id not in existing:
            existing.append(linked_id)
        primary.linked_user_ids = json.dumps(existing)
        primary.updated_at = time.time()
        session.commit()
        return primary.to_dict()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _session() -> Any:
    """Return a SQLAlchemy session. Raises RuntimeError if DB not init."""
    try:
        return get_session()
    except RuntimeError:
        raise RuntimeError(
            "Database not initialized. Call init_db() before using user_registry."
        )
