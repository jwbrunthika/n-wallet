#!/usr/bin/env sh
set -eu

echo "[nwallet] Running backend bootstrap..."
docker compose exec backend_php php artisan migrate --seed --force
echo "[nwallet] Backend bootstrap complete."
