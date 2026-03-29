from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass
class EmbeddingResult:
    embedding: list[float]
    quality_score: float
    model_version: str


class FaceEngine:
    def __init__(self) -> None:
        self.model_name = os.getenv("FACE_MODEL_NAME", "buffalo_l")
        self.model_version = os.getenv("FACE_MODEL_VERSION", "arcface-onnx-1.0")
        self.face_app = None

    def load(self) -> None:
        from insightface.app import FaceAnalysis

        self.face_app = FaceAnalysis(name=self.model_name, providers=["CPUExecutionProvider"])
        self.face_app.prepare(ctx_id=-1, det_size=(640, 640))

    def extract_embedding(self, image_bytes: bytes) -> EmbeddingResult:
        import cv2
        import numpy as np

        if self.face_app is None:
            self.load()

        array = np.frombuffer(image_bytes, dtype=np.uint8)
        frame = cv2.imdecode(array, cv2.IMREAD_COLOR)
        if frame is None:
            raise ValueError("Invalid image bytes")

        faces = self.face_app.get(frame)
        if not faces:
            raise ValueError("No face detected")

        selected = max(faces, key=lambda face: (face.bbox[2] - face.bbox[0]) * (face.bbox[3] - face.bbox[1]))

        embedding = selected.normed_embedding.astype(np.float32)
        if embedding.shape[0] != 512:
            raise ValueError("Embedding dimension is not 512")

        bbox = selected.bbox
        width = max(1.0, float(bbox[2] - bbox[0]))
        height = max(1.0, float(bbox[3] - bbox[1]))
        area_ratio = (width * height) / float(frame.shape[0] * frame.shape[1])
        det_score = float(getattr(selected, "det_score", 0.5))

        quality_score = max(0.0, min(1.0, det_score * min(1.0, area_ratio * 6.0)))

        return EmbeddingResult(
            embedding=embedding.tolist(),
            quality_score=quality_score,
            model_version=self.model_version,
        )
