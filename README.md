# N Wallet (Student Attendance System)

N Wallet is a student attendance system that accepts attendance **only** when:
1. Face identity verification passes (server-side embeddings)
2. The student is near the correct iBeacon (DX-CP33-V1.0) for the lecture hall

## Stack
- Mobile app: Flutter + GetX
- Admin web: Flutter + GetX
- Backend API: Laravel 12 (PHP 8.2+) + MongoDB
- Face service: Python FastAPI + InsightFace ArcFace ONNX Runtime
- Deployment: `docker-compose` (single VPS command)

## Monorepo Structure
- `docker-compose.yml`
- `.env.docker`
- `backend_api/` Laravel API
- `face_service/` FastAPI service
- `mobile_app/` Flutter student app
- `admin_web/` Flutter admin app
- `shared_dart/` shared API DTO/client package
- `sample-data/timetable_sample.csv`
- `scripts/bootstrap_backend.sh`

## Simple Deployment (VPS)
1. Start services:
```bash
docker compose up -d --build
```

2. Bootstrap Laravel (migrations + seed):
```bash
./scripts/bootstrap_backend.sh
```

3. API health check:
```bash
curl http://localhost:18082/api/v1/health
```

## Local Run Instructions (required)
1. Backend stack:
```bash
docker compose up -d --build
```

2. Run migrations/seed:
```bash
docker compose exec backend_php php artisan migrate --seed --force
```

3. Admin web:
```bash
cd admin_web
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:18082/api/v1
```

4. Mobile app:
```bash
cd mobile_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://51.255.201.31:18082/api/v1
```

## Credentials and Defaults
### Seed admin account
- Email: `nwallet.2002@gmail.com`
- Password: `Nodecmb@2k26`
- Role: `SUPER_ADMIN`

### Default settings
- `faceMatchThreshold = 0.55`
- `beaconRssiThreshold = -70`
- `beaconStabilitySeconds = 8`

### SMTP defaults in `.env.docker`
- Host: `smtp.gmail.com`
- Port: `587`
- Username: `nwallet.2002@gmail.com`
- Password: `orvuywcdwwmcktxw` (Gmail App Password)
- Encryption: `tls`

## Security Notes
- Passwords are hashed (`Hash::make`) for admins.
- Face template vectors are encrypted before MongoDB persistence:
  - vector JSON -> `Crypt::encryptString` -> base64 in `faceTemplate.encryptedVector`
- OTP supports dev logging mode (`OTP_DEV_MODE=true`) for demo environments.
- Attendance integrity is enforced by unique index `(studentEmail, sessionId)`.

## Important API Base URL
- `http://51.255.201.31:18082/api/v1`

## Optional HTTPS (demo out of scope)
Current setup is HTTP-first for student project simplicity. For production-like deployment, place API behind TLS reverse proxy and rotate credentials.

## Mobile Networking Notes
- Android emulator -> use `http://51.255.201.31:18082/api/v1`
- iOS simulator -> use `http://51.255.201.31:18082/api/v1`
- Physical devices -> use VPS/public IP URL.

## Sample Timetable CSV
Use `sample-data/timetable_sample.csv` with the import page in admin web.

## Course-Aware Enrollment Flow
1. In admin web, create modules in `Modules`.
2. In admin web, create courses in `Courses` with:
   - `courseName` (course code is auto-generated internally)
   - `batchCount` / `batchLabels`
   - `deliveryMode` (`WEEKDAY`, `WEEKEND`, `BOTH`)
   - `moduleCodes` assigned to that course
3. In admin web, open `Students` and assign each student an academic profile:
   - Course
   - `batch`
   - `studyMode` (`WEEKDAY` or `WEEKEND`)
   - Enrollment is blocked until this profile is assigned (`ACADEMIC_PROFILE_REQUIRED`).
4. Import timetable CSV with course-specific headers:
   - `session_date,start_time,end_time,course_name,module_code,module_name,hall_name,batch,delivery_mode,lecturer_email,attendance_open_minutes_before,attendance_close_minutes_after,notes`
   - `course_code` is still supported as a legacy optional column.
5. Student app automatically receives only sessions matching student `courseCode + batch + studyMode`.
