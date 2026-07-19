#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess


def nvidia_smi() -> dict:
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,driver_version,memory.total,memory.free",
                "--format=csv,noheader,nounits",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)}

    gpus = []
    for line in result.stdout.splitlines():
        parts = [part.strip() for part in line.split(",")]
        if len(parts) >= 4:
            gpus.append(
                {
                    "name": parts[0],
                    "driver_version": parts[1],
                    "memory_total_mb": int(float(parts[2])),
                    "memory_free_mb": int(float(parts[3])),
                }
            )
    return {"ok": True, "gpus": gpus}


def torch_cuda() -> dict:
    try:
        import torch
    except Exception as exc:  # noqa: BLE001
        return {"cuda_available": False, "error": str(exc)}

    return {
        "version": torch.__version__,
        "cuda_available": bool(torch.cuda.is_available()),
        "device": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
    }


print(json.dumps({"nvidia_smi": nvidia_smi(), "torch": torch_cuda()}, ensure_ascii=False, indent=2))
