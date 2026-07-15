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
