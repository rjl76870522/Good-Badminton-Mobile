import threading

from badminton_analysis.task_queue import DurableTaskWorker


def test_worker_runs_notified_tasks_in_claim_order():
    pending = [{"task_id": "first"}, {"task_id": "second"}]
    completed: list[str] = []
    done = threading.Event()

    def claim_next():
        return pending.pop(0) if pending else None

    def run_task(task):
        completed.append(task["task_id"])
        if len(completed) == 2:
            done.set()

    worker = DurableTaskWorker(
        claim_next=claim_next,
        run_task=run_task,
        fail_task=lambda _task_id, _exc: None,
        idle_wait_seconds=0.01,
    )
    worker.start()
    worker.notify()
    assert done.wait(1.0)
    worker.stop()

    assert completed == ["first", "second"]
    assert not worker.running


def test_worker_survives_transient_claim_failure():
    attempts = 0
    completed = threading.Event()

    def claim_next():
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise RuntimeError("database temporarily busy")
        if attempts == 2:
            return {"task_id": "recovered"}
        return None

    worker = DurableTaskWorker(
        claim_next=claim_next,
        run_task=lambda _task: completed.set(),
        fail_task=lambda _task_id, _exc: None,
        idle_wait_seconds=0.01,
    )
    worker.start()
    worker.notify()
    assert completed.wait(1.0)
    worker.stop()

    assert attempts >= 2


def test_worker_pool_runs_two_tasks_concurrently_without_duplicates():
    pending = [{"task_id": "first"}, {"task_id": "second"}]
    pending_lock = threading.Lock()
    completed: list[str] = []
    completed_lock = threading.Lock()
    both_started = threading.Event()
    release = threading.Event()
    active = 0
    peak_active = 0

    def claim_next():
        with pending_lock:
            return pending.pop(0) if pending else None

    def run_task(task):
        nonlocal active, peak_active
        with completed_lock:
            active += 1
            peak_active = max(peak_active, active)
            if active == 2:
                both_started.set()
        assert release.wait(1.0)
        with completed_lock:
            completed.append(task["task_id"])
            active -= 1

    worker = DurableTaskWorker(
        claim_next=claim_next,
        run_task=run_task,
        fail_task=lambda _task_id, _exc: None,
        worker_count=2,
        idle_wait_seconds=0.01,
    )
    worker.start()
    worker.notify()
    assert both_started.wait(1.0)
    assert worker.capacity == 2
    assert worker.active_workers == 2
    release.set()
    worker.stop()

    assert peak_active == 2
    assert sorted(completed) == ["first", "second"]
    assert not worker.running
