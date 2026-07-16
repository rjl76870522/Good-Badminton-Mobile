"""Bounded worker-pool coordination for the durable SQLite task queue.

Task state stays in SQLite. The worker only provides wake-up and lifecycle
coordination, so queued work survives backend restarts.
"""

from __future__ import annotations

import logging
import threading
import time
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
        worker_count: int = 1,
        idle_wait_seconds: float = 5.0,
    ) -> None:
        self._claim_next = claim_next
        self._run_task = run_task
        self._fail_task = fail_task
        self._idle_wait_seconds = idle_wait_seconds
        self._worker_count = max(1, min(int(worker_count), 8))
        self._wake_event = threading.Event()
        self._stop_event = threading.Event()
        self._threads: list[threading.Thread] = []
        self._lifecycle_lock = threading.Lock()
        self._activity_lock = threading.Lock()
        self._active_workers = 0

    @property
    def running(self) -> bool:
        return any(thread.is_alive() for thread in self._threads)

    @property
    def capacity(self) -> int:
        return self._worker_count

    @property
    def active_workers(self) -> int:
        with self._activity_lock:
            return self._active_workers

    def start(self) -> None:
        with self._lifecycle_lock:
            if self.running:
                return
            self._stop_event.clear()
            self._threads = [
                threading.Thread(
                    target=self._run_loop,
                    args=(index,),
                    name=f"badminton-analysis-worker-{index + 1}",
                    daemon=True,
                )
                for index in range(self._worker_count)
            ]
            for thread in self._threads:
                thread.start()

    def stop(self, timeout: float = 10.0) -> None:
        with self._lifecycle_lock:
            threads = list(self._threads)
            if not threads:
                return
            self._stop_event.set()
            self._wake_event.set()
        deadline = time.monotonic() + timeout
        for thread in threads:
            thread.join(timeout=max(0.0, deadline - time.monotonic()))
        with self._lifecycle_lock:
            self._threads = [thread for thread in self._threads if thread.is_alive()]

    def notify(self) -> None:
        self._wake_event.set()

    def _run_loop(self, _worker_index: int) -> None:
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
            with self._activity_lock:
                self._active_workers += 1
            try:
                self._run_task(task)
            except Exception as exc:  # pragma: no cover - final worker safeguard
                logger.exception("Unhandled analysis worker failure for %s", task_id)
                self._fail_task(task_id, exc)
            finally:
                with self._activity_lock:
                    self._active_workers -= 1
