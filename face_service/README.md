# Face Service

FastAPI microservice for N Wallet face embeddings.

## Endpoint
- `POST /embedding/from-image-bytes` (multipart field: `image`)
  - Returns: `embedding[512]`, `qualityScore`, `modelVersion`

## Run locally
```bash
cd face_service
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8001
```
