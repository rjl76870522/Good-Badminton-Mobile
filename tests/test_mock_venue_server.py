from fastapi.testclient import TestClient

from mock_venue_server.main import app


def test_virtual_venue_exposes_ten_courts_and_twenty_recordings():
    with TestClient(app) as client:
        courts = client.get("/courts")
        videos = client.get("/videos")
        operator = client.get("/operator")

    assert courts.status_code == 200
    assert videos.status_code == 200
    assert operator.status_code == 200
    assert len(courts.json()["items"]) == 10
    assert all(item["video_count"] == 2 for item in courts.json()["items"])
    assert len(videos.json()["items"]) == 20
    assert "视频运营台" in operator.text


def test_virtual_venue_can_filter_recordings_by_court():
    with TestClient(app) as client:
        response = client.get("/videos", params={"court": "3号场"})

    assert response.status_code == 200
    items = response.json()["items"]
    assert len(items) == 2
    assert {item["court"] for item in items} == {"3号场"}
