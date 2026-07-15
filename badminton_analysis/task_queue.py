"""Single-worker durable task queue coordination.

Task state stays in SQLite. The worker only provides wake-up and lifecycle
coordination, so queued work survives backend restarts.
"""

from __future__ import annotations

import logging
import threading
from collections.abc import Callable
from typing import Any

logger = logging.getLogger(__name__)


class DurableTaskWorker:
    def __init__(
        self,
        claim_next: Callable[[], dict[str, Any] | None],
        run_task: Callable[[dict[str, Any]], None],
        fail_task: Callable[[str, Exception], None],
        *,
        idle_wait_seconds: float = 5.0,
    ) -> None:
        self._claim_next = claim_next
        self._run_task = run_task
        self._fail_task = fail_task
        self._idle_wait_seconds = idle_wait_seconds
        self._wake_event = threading.Event()
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._lifecycle_lock = threading.Lock()

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def start(self) -> None:
        with self._lifecycle_lock:
            if self.running:
                return
            self._stop_event.clear()
            self._thread = threading.Thread(
                target=self._run_loop,
                name="badminton-analysis-worker",
                daemon=True,
            )
            self._thread.start()

    def stop(self, timeout: float = 10.0) -> None:
        with self._lifecycle_lock:
            thread = self._thread
            if thread is None:
                return
            self._stop_event.set()
            self._wake_event.set()
        thread.join(timeout=timeout)
        with self._lifecycle_lock:
            if self._thread is thread and not thread.is_alive():
                self._thread = None

    def notify(self) -> None:
        self._wake_event.set()

    def _run_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                task = self._claim_next()
            except Exception:  # pragma: no cover - depends on transient DB failures
                logger.exception("Unable to claim the next queued analysis task")
                self._wake_event.wait(self._idle_wait_seconds)
                self._wake_event.clear()
                continue
            if task is None:
                self._wake_event.wait(self._idle_wait_seconds)
                self._wake_event.clear()
                continue

            task_id = str(task.get("task_id") or "")
            try:
                self._run_task(task)
            except Exception as exc:  # pragma: no cover - final worker safeguard
                logger.exception("Unhandled analysis worker failure for %s", task_id)
                self._fail_task(task_id, exc)
