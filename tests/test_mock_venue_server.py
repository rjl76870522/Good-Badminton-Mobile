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
