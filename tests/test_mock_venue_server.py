import subprocess
import threading
from concurrent.futures import ThreadPoolExecutor

from fastapi.testclient import TestClient

from mock_venue_server import main as venue_server

app = venue_server.app


def test_example_venue_exposes_ten_courts_and_one_recording_each():
    with TestClient(app) as client:
        courts = client.get("/courts")
        videos = client.get("/videos")
        operator = client.get("/operator")

    assert courts.status_code == 200
    assert videos.status_code == 200
    assert operator.status_code == 200
    assert len(courts.json()["items"]) == 10
    assert all(item["video_count"] == 1 for item in courts.json()["items"])
    assert len(videos.json()["items"]) == 10
    assert "视频运营台" in operator.text


def test_virtual_venue_can_filter_recordings_by_court():
    with TestClient(app) as client:
        response = client.get("/videos", params={"court": "3号场"})

    assert response.status_code == 200
    items = response.json()["items"]
    assert len(items) == 1
    assert {item["court"] for item in items} == {"3号场"}


def test_virtual_venue_exposes_inline_playback_stream():
    with TestClient(app) as client:
        response = client.get(
            "/videos/court1-full-recording/play",
            headers={"Range": "bytes=0-1023"},
        )

    assert response.status_code == 206
    assert response.headers["content-type"].startswith("video/mp4")
    assert response.headers["content-disposition"] == "inline"
    assert response.headers["accept-ranges"] == "bytes"


def test_default_courts_use_the_configured_recordings():
    recordings = venue_server._default_library()
    filenames = [item["filename"] for item in recordings]

    assert filenames == [
        "05.mp4",
        "04.mp4",
        "03.mp4",
        "01.mp4",
        "02.mp4",
        "05.mp4",
        "04.mp4",
        "03.mp4",
        "01.mp4",
        "02.mp4",
    ]
    assert [item["duration"] for item in recordings] == [
        "8 秒",
        "11 秒",
        "18 秒",
        "35 秒",
        "47 秒",
        "8 秒",
        "11 秒",
        "18 秒",
        "35 秒",
        "47 秒",
    ]
    assert all(item["revision"] for item in recordings)


def test_operator_can_add_multiple_recordings_at_different_times(
    monkeypatch,
    tmp_path,
):
    videos_dir = tmp_path / "videos"
    videos_dir.mkdir()
    library_path = tmp_path / "venue_library.json"
    monkeypatch.setattr(venue_server, "VIDEOS_DIR", videos_dir)
    monkeypatch.setattr(venue_server, "LIBRARY_PATH", library_path)
    monkeypatch.setattr(venue_server, "ALLOW_OPERATOR_UPLOADS", True)
    monkeypatch.setattr(venue_server, "_probe_duration_seconds", lambda _path: 15)

    with TestClient(app) as client:
        first = client.post(
            "/courts/1/videos",
            files={"file": ("morning.mp4", b"morning", "video/mp4")},
        )
        second = client.post(
            "/courts/1/videos",
            files={"file": ("evening.mp4", b"evening", "video/mp4")},
        )
        response = client.get("/videos", params={"court": "1号场"})

    assert first.status_code == 200
    assert second.status_code == 200
    assert len(response.json()["items"]) == 3


def test_same_clip_can_be_generated_concurrently(monkeypatch, tmp_path):
    source = tmp_path / "source.mp4"
    source.write_bytes(b"source")
    clips_dir = tmp_path / "clips"
    output_paths = []
    generation_barrier = threading.Barrier(2)

    monkeypatch.setattr(venue_server, "CLIPS_DIR", clips_dir)
    monkeypatch.setattr(venue_server, "_find_video", lambda _video_id: {})
    monkeypatch.setattr(venue_server, "_video_path", lambda _video: source)
    monkeypatch.setattr(venue_server, "_probe_duration_seconds", lambda _path: 30)

    def fake_run(command, **_kwargs):
        output_path = command[-1]
        output_paths.append(output_path)
        venue_server.Path(output_path).write_bytes(b"clip")
        generation_barrier.wait(timeout=2)
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(venue_server.subprocess, "run", fake_run)

    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(
            executor.map(
                lambda _: venue_server.download_clip(
                    "court1-full-recording",
                    start_ms=1000,
                    end_ms=6000,
                ),
                range(2),
            )
        )

    assert len(responses) == 2
    assert len(set(output_paths)) == 2
    assert all(path.endswith(".tmp.mp4") for path in output_paths)
    assert not list(clips_dir.glob("*.tmp.mp4"))
