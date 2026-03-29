#!/usr/bin/env sh
set -eu

echo "[nwallet] Rebuilding backend image..."
docker compose up -d --build backend_php

echo "[nwallet] Clearing Laravel caches..."
docker compose exec backend_php php artisan optimize:clear

echo "[nwallet] Running backend bootstrap..."
./scripts/bootstrap_backend.sh

echo "[nwallet] Backend rebuild complete."
