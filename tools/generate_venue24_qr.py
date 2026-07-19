from pathlib import Path

import cv2


PAYLOAD = (
    '{"type":"venue","venue_id":"24","venue_name":"演示球馆",'
    '"server_url":"https://venue.example.com"}'
)
OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "frontend_flutter"
    / "assets"
    / "qr"
    / "venue24_demo_qr.png"
)


def main() -> None:
    qr = cv2.QRCodeEncoder_create().encode(PAYLOAD)
    qr = cv2.copyMakeBorder(
        qr,
        4,
        4,
        4,
        4,
        cv2.BORDER_CONSTANT,
        value=255,
    )
    qr = cv2.resize(qr, (1024, 1024), interpolation=cv2.INTER_NEAREST)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(OUTPUT), qr):
        raise RuntimeError(f"Failed to write {OUTPUT}")
    print(OUTPUT)


if __name__ == "__main__":
    main()
