# N Wallet Server Handover

## 1) Server Identity
- Hostname: `vps-31f3f47c`
- Public IP: `51.255.201.31`
- OS: Ubuntu
- SSH user: `ubuntu`
- App root path: `/home/ubuntu/N-Wallet`

## 2) Live URLs (Current)
- Admin web: `http://51.255.201.31:18081/#/login`
- API base: `http://51.255.201.31:18082/api/v1`
- API health: `http://51.255.201.31:18082/api/v1/health`
- Face service external port: `http://51.255.201.31:8090/health`
- MongoDB port: `27017` (publicly exposed by current compose)

## 3) Runtime Stack
Orchestration:
- `docker compose`

Compose services:
- `backend_php` -> container `nwallet_backend_php` -> host `18082 -> 8000`
- `admin_web` -> container `nwallet_admin_web` -> host `18081 -> 80`
- `face_service` -> container `nwallet_face_service` -> host `8090 -> 8001`
- `mongo` -> container `nwallet_mongo` -> host `27017 -> 27017`

Docker volumes:
- `n-wallet_backend_storage` (Laravel local file storage)
- `n-wallet_mongo_data` (MongoDB data)

## 4) Environment and Config Files
Primary env files in `/home/ubuntu/N-Wallet`:
- `.env` (compose port overrides)
  - `BACKEND_PORT=18082`
  - `ADMIN_WEB_PORT=18081`
- `.env.docker` (Laravel runtime env, mounted into backend container)

Important config values currently in `.env.docker`:
- `MONGO_URI=mongodb://root:rootpass@mongo:27017`
- `MONGO_DATABASE=nwallet`
- `FACE_SERVICE_URL=http://face_service:8001`
- `MAIL_HOST=smtp.gmail.com`
- `MAIL_USERNAME=nwallet.2002@gmail.com`
- `OTP_DEV_MODE=false`

## 5) Standard Operations
Run from:
- `cd /home/ubuntu/N-Wallet`

Start/rebuild:
```bash
docker compose up -d --build
```

Bootstrap backend:
```bash
./scripts/bootstrap_backend.sh
```

Restart one service:
```bash
docker compose restart backend_php
docker compose restart admin_web
```

Check status:
```bash
docker compose ps
```

Health check:
```bash
curl http://localhost:18082/api/v1/health
```

## 6) Deploy Procedure (Current Practice)
Current deployment pattern used:
1. Build admin web locally:
```bash
cd admin_web
flutter build web --release --dart-define=API_BASE_URL=http://51.255.201.31:18082/api/v1
```
2. Copy changed source/build files to VPS.
3. Run on VPS:
```bash
cd /home/ubuntu/N-Wallet
docker compose up -d --build
./scripts/bootstrap_backend.sh
```

Notes:
- Backend and face service are built on VPS by compose.
- Admin web is static files served by nginx container from `admin_web/build/web`.

## 7) Backup and Restore Runbook
Create backup directory:
```bash
mkdir -p /home/ubuntu/N-Wallet/backups
```

Mongo backup:
```bash
docker compose exec -T mongo mongodump \
  --uri="mongodb://root:rootpass@localhost:27017" \
  --db nwallet \
  --archive > /home/ubuntu/N-Wallet/backups/nwallet_$(date +%F_%H%M).archive
```

Mongo restore:
```bash
cat /home/ubuntu/N-Wallet/backups/<file>.archive | \
docker compose exec -T mongo mongorestore \
  --uri="mongodb://root:rootpass@localhost:27017" \
  --archive --drop
```

File storage backup (`n-wallet_backend_storage`):
```bash
docker run --rm \
  -v n-wallet_backend_storage:/data \
  -v /home/ubuntu/N-Wallet/backups:/backup \
  alpine sh -c "cd /data && tar czf /backup/backend_storage_$(date +%F_%H%M).tar.gz ."
```

## 8) Logs and Troubleshooting
Service logs:
```bash
docker compose logs -f backend_php
docker compose logs -f admin_web
docker compose logs -f face_service
docker compose logs -f mongo
```

Common checks:
- Admin login fails:
  - Check API reachable at `:18082`
  - Check admin web points to correct API URL in built `main.dart.js`
- OTP not delivered:
  - Check SMTP values in `.env.docker`
  - Check backend logs for mail transport errors
- Enrollment/attendance failures:
  - Check backend logs and face service logs together

## 9) Security Actions Recommended Immediately
- Rotate:
  - SSH password
  - Admin seed password
  - Gmail app password
  - Mongo root password
  - `APP_KEY` and `JWT_SECRET`
- Restrict MongoDB public exposure (currently `27017` is open by compose).
- Add TLS reverse proxy for public traffic.

## 10) Server Handover Checklist
- SSH access validated.
- Compose services healthy.
- API health endpoint returns success.
- Admin web reachable.
- Backup/restore commands documented.
- Credentials rotation actions listed.
