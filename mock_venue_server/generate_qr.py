from __future__ import annotations

import json
import sys
from pathlib import Path

import qrcode


def normalize_server_url(value: str) -> str:
    """Accept either a LAN IP address or a complete public tunnel URL."""
    value = value.strip().rstrip("/")
    if value.startswith(("http://", "https://")):
        return value
    return f"http://{value}:9000"


def main() -> None:
    address = sys.argv[1] if len(sys.argv) > 1 else "电脑IP"
    payload = {
        "type": "venue",
        "venue_id": "SZ_BADMINTON_001",
        "venue_name": "智慧羽毛球馆",
        "server_url": normalize_server_url(address),
    }
    image = qrcode.make(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    output = Path(__file__).resolve().parent / "venue_qr.png"
    image.save(output)
    print(f"QR saved to: {output}")
    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
