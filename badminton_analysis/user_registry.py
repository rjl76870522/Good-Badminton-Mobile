"""Small JSON-backed user registry for the mobile demo backend."""

from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any


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


def load_users(path: Path) -> dict[str, dict[str, Any]]:
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    users = data.get("users") if isinstance(data, dict) else None
    if not isinstance(users, dict):
        return {}
    cleaned: dict[str, dict[str, Any]] = {}
    for user_id, user in users.items():
        if not isinstance(user, dict):
            continue
        try:
            normalized_id = normalize_user_id(str(user.get("user_id") or user_id))
        except InvalidUserId:
            continue
        cleaned[normalized_id] = {
            "user_id": normalized_id,
            "created_at": _to_float(user.get("created_at")),
            "updated_at": _to_float(user.get("updated_at")),
        }
    return cleaned


def save_users(path: Path, users: dict[str, dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": "user-registry-v1",
        "users": users,
    }
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    tmp_path.replace(path)


def register_user(
    path: Path,
    *,
    user_id: str,
) -> dict[str, Any]:
    normalized_id = normalize_user_id(user_id)
    users = load_users(path)
    if normalized_id in users:
        raise UserAlreadyExists(f"user_id already exists: {normalized_id}")

    now = time.time()
    user = {
        "user_id": normalized_id,
        "created_at": now,
        "updated_at": now,
    }
    users[normalized_id] = user
    save_users(path, users)
    return user


def get_user(path: Path, user_id: str) -> dict[str, Any]:
    normalized_id = normalize_user_id(user_id)
    users = load_users(path)
    user = users.get(normalized_id)
    if user is None:
        raise UserNotFound(f"user not found: {normalized_id}")
    return user


def _to_float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0
