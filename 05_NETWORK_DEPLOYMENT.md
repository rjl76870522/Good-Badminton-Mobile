# Good-Badminton Network Deployment

This project uses `backend_api.py` as the only competition/mobile backend.

## Stage 1: Same Wi-Fi

Start the backend:

```bat
D:\py\Good-Badminton\start_mobile_backend.bat
```

Use the computer WLAN IPv4 address as the frontend base URL:

```text
http://<computer-wlan-ip>:8001
```

Current local example:

```text
http://172.29.72.218:8001
```

Test from a phone browser:

```text
http://<computer-wlan-ip>:8001/api/health
```

## Stage 2: Temporary Public HTTPS Tunnel

This computer has `cloudflared` installed at:

```text
D:\tools\cloudflared\cloudflared.exe
```

Start the backend first, then start the tunnel:

```bat
D:\py\Good-Badminton\start_mobile_backend.bat
D:\py\Good-Badminton\start_public_tunnel.bat
```

The tunnel window prints a temporary URL like:

```text
https://example-words.trycloudflare.com
```

Use that full URL as the frontend/app `baseUrl`.

Important:

- The URL changes every time the tunnel restarts.
- Keep both the backend window and tunnel window open.
- Do not add `/api` to baseUrl. The app calls `/api/...` itself.
- Test with `https://...trycloudflare.com/api/health` before uploading video.

## Stage 3: Desktop Server

When the teacher gives a desktop computer as the backend server:

1. Put this project on the desktop computer.
2. Install/restore the `badminton` conda environment.
3. Start `backend_api.py` on port `8001`.
4. Use either same-Wi-Fi IP or a public HTTPS tunnel/domain.
5. Give frontend only one value: the final base URL.

## Frontend Contract

Frontend must support changing baseUrl without rebuilding the UI.

Examples:

```text
http://172.29.72.218:8001
https://example-words.trycloudflare.com
https://your-domain.example
```

Required endpoints stay the same:

```text
GET  /api/health
POST /api/videos/upload
GET  /api/tasks/{task_id}
GET  /api/tasks/{task_id}/report
GET  /api/history
GET  /api/tasks/{task_id}/highlight
```
