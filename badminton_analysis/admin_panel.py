"""Local-only operational dashboard for the Good-Badminton server."""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import subprocess
import time
from collections import Counter
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DB_PATH = PROJECT_ROOT / "mobile_backend_data" / "badminton.db"
DATA_PATHS = {
    "原始视频": PROJECT_ROOT / "mobile_backend_data" / "uploads",
    "分析结果": PROJECT_ROOT / "outputs",
    "预览缓存": PROJECT_ROOT / "mobile_backend_data" / "preview_uploads",
}


def _directory_stats(path: Path) -> tuple[int, int, Counter[str]]:
    count = 0
    size = 0
    daily: Counter[str] = Counter()
    if not path.exists():
        return count, size, daily
    for item in path.rglob("*"):
        if not item.is_file():
            continue
        try:
            stat = item.stat()
        except OSError:
            continue
        count += 1
        size += stat.st_size
        daily[datetime.fromtimestamp(stat.st_mtime).strftime("%m-%d")] += stat.st_size
    return count, size, daily


def _gpu_status() -> dict[str, object]:
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.used,memory.total,utilization.gpu",
                "--format=csv,noheader,nounits",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=3,
        )
        name, used, total, utilization = [
            value.strip() for value in result.stdout.splitlines()[0].split(",")
        ]
        return {
            "available": True,
            "name": name,
            "memory_used_mb": int(float(used)),
            "memory_total_mb": int(float(total)),
            "utilization": int(float(utilization)),
        }
    except Exception as exc:
        return {"available": False, "message": str(exc)}


def collect_metrics() -> dict[str, object]:
    statuses: Counter[str] = Counter()
    users = 0
    tasks = 0
    daily_tasks: Counter[str] = Counter()
    if DB_PATH.is_file():
        with sqlite3.connect(DB_PATH) as connection:
            users = connection.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            rows = connection.execute(
                "SELECT status, created_at FROM tasks"
            ).fetchall()
        tasks = len(rows)
        for status, created_at in rows:
            statuses[str(status)] += 1
            daily_tasks[datetime.fromtimestamp(created_at).strftime("%m-%d")] += 1

    storage_rows = []
    daily_bytes: Counter[str] = Counter()
    for label, path in DATA_PATHS.items():
        count, size, growth = _directory_stats(path)
        storage_rows.append({"label": label, "files": count, "bytes": size})
        daily_bytes.update(growth)

    disk = shutil.disk_usage(PROJECT_ROOT)
    days = [
        (datetime.now() - timedelta(days=offset)).strftime("%m-%d")
        for offset in range(13, -1, -1)
    ]
    return {
        "generated_at": time.time(),
        "users": users,
        "tasks": tasks,
        "statuses": dict(statuses),
        "queue": {
            "queued": statuses["queued"],
            "processing": statuses["processing"],
            "capacity": 4,
        },
        "disk": {
            "used": disk.used,
            "total": disk.total,
            "percent": round(disk.used / disk.total * 100, 2),
        },
        "storage": storage_rows,
        "growth": [
            {
                "day": day,
                "tasks": daily_tasks[day],
                "bytes": daily_bytes[day],
            }
            for day in days
        ],
        "gpu": _gpu_status(),
    }


HTML = """<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Good Badminton 管理</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f4f7f4;color:#172019;font-family:system-ui,-apple-system,"Noto Sans CJK SC",sans-serif}
main{max-width:1120px;margin:auto;padding:28px 20px 50px}header{display:flex;justify-content:space-between;align-items:end;margin-bottom:22px}
h1{margin:0;font-size:28px}small,.muted{color:#657068}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
.card{background:white;border:1px solid #dce5dd;border-radius:8px;padding:18px}.value{font-size:28px;font-weight:750;margin-top:6px}
h2{font-size:17px;margin:26px 0 10px}.row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:10px 8px;border-bottom:1px solid #e6ece7;font-size:14px}
.bar{height:9px;background:#e2e9e3;border-radius:5px;overflow:hidden;margin-top:12px}.bar i{display:block;height:100%;background:#2f7140}
@media(max-width:760px){.grid{grid-template-columns:1fr 1fr}.row{grid-template-columns:1fr}header{align-items:start;flex-direction:column;gap:5px}}
</style></head><body><main>
<header><div><h1>Good Badminton 管理</h1><small>仅限本机访问</small></div><small id="time">正在读取</small></header>
<section class="grid">
<div class="card"><span class="muted">用户数</span><div class="value" id="users">-</div></div>
<div class="card"><span class="muted">任务总数</span><div class="value" id="tasks">-</div></div>
<div class="card"><span class="muted">GPU 正在处理</span><div class="value" id="processing">-</div></div>
<div class="card"><span class="muted">等待队列</span><div class="value" id="queued">-</div></div>
</section>
<section class="row">
<div><h2>磁盘与文件</h2><div class="card"><div id="disk">-</div><div class="bar"><i id="diskbar"></i></div><table><tbody id="storage"></tbody></table></div></div>
<div><h2>GPU</h2><div class="card" id="gpu">-</div><h2>任务状态</h2><div class="card"><table><tbody id="statuses"></tbody></table></div></div>
</section>
<h2>近 14 天新增</h2><div class="card"><table><thead><tr><th>日期</th><th>任务</th><th>新增文件</th></tr></thead><tbody id="growth"></tbody></table></div>
</main><script>
const size=n=>{if(n<1024)return n+" B";if(n<1048576)return(n/1024).toFixed(1)+" KB";if(n<1073741824)return(n/1048576).toFixed(1)+" MB";return(n/1073741824).toFixed(2)+" GB"}
async function load(){const d=await(await fetch("/api/metrics")).json();
time.textContent="更新于 "+new Date(d.generated_at*1000).toLocaleString();users.textContent=d.users;tasks.textContent=d.tasks;
processing.textContent=d.queue.processing+" / "+d.queue.capacity;queued.textContent=d.queue.queued;
disk.textContent=size(d.disk.used)+" / "+size(d.disk.total)+" · "+d.disk.percent+"%";diskbar.style.width=d.disk.percent+"%";
storage.innerHTML=d.storage.map(x=>`<tr><td>${x.label}</td><td>${x.files} 个文件</td><td>${size(x.bytes)}</td></tr>`).join("");
statuses.innerHTML=Object.entries(d.statuses).map(x=>`<tr><td>${x[0]}</td><td>${x[1]}</td></tr>`).join("");
gpu.innerHTML=d.gpu.available?`<b>${d.gpu.name}</b><p>显存 ${d.gpu.memory_used_mb} / ${d.gpu.memory_total_mb} MB</p><p>利用率 ${d.gpu.utilization}%</p>`:"GPU 状态暂不可读";
growth.innerHTML=d.growth.map(x=>`<tr><td>${x.day}</td><td>${x.tasks}</td><td>${size(x.bytes)}</td></tr>`).join("")}
load();setInterval(load,15000);
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/api/metrics":
            payload = json.dumps(collect_metrics(), ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
        elif path in {"/", "/admin/storage"}:
            payload = HTML.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
        else:
            payload = b"Not found"
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    args = parser.parse_args()
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
