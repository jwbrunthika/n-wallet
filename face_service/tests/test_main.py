from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app


class FakeEngine:
    def load(self) -> None:
        return

    def extract_embedding(self, image_bytes: bytes):
        return type(
            "Result",
            (),
            {
                "embedding": [0.1] * 512,
                "quality_score": 0.8,
                "model_version": "arcface-onnx-1.0",
            },
        )()


class FakeFailEngine:
    def load(self) -> None:
        return

    def extract_embedding(self, image_bytes: bytes):
        raise ValueError("No face detected")


def test_embedding_success(monkeypatch):
    monkeypatch.setattr("app.main.engine", FakeEngine())
    client = TestClient(app)

    response = client.post(
        "/embedding/from-image-bytes",
        files={"image": ("face.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["embedding"]) == 512


def test_embedding_no_face(monkeypatch):
    monkeypatch.setattr("app.main.engine", FakeFailEngine())
    client = TestClient(app)

    response = client.post(
        "/embedding/from-image-bytes",
        files={"image": ("face.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert response.status_code == 422
