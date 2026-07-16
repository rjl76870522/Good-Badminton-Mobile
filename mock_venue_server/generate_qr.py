from __future__ import annotations

import json
import sys
from pathlib import Path

import qrcode


def main() -> None:
    computer_ip = sys.argv[1] if len(sys.argv) > 1 else "电脑IP"
    payload = {
        "type": "venue",
        "venue_id": "SZ_BADMINTON_001",
        "venue_name": "智慧羽毛球馆",
        "server_url": f"http://{computer_ip}:9000",
    }
    image = qrcode.make(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    output = Path(__file__).resolve().parent / "venue_qr.png"
    image.save(output)
    print(f"QR saved to: {output}")
    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
