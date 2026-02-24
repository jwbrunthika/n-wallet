from __future__ import annotations

from fastapi import FastAPI, File, HTTPException, UploadFile

from app.engine import FaceEngine

app = FastAPI(title="N Wallet Face Service", version="1.0.0")
engine = FaceEngine()


@app.on_event("startup")
def startup_event() -> None:
    engine.load()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "face_service"}


@app.post("/embedding/from-image-bytes")
async def embedding_from_image_bytes(image: UploadFile = File(...)) -> dict[str, object]:
    try:
        content = await image.read()
        result = engine.extract_embedding(content)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:  # pragma: no cover - defensive safeguard
        raise HTTPException(status_code=500, detail="Face engine failure") from exc

    return {
        "embedding": result.embedding,
        "qualityScore": result.quality_score,
        "modelVersion": result.model_version,
    }
