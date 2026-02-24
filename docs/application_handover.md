# N Wallet Application Handover

## 1) Document Control
- Project: `N Wallet (Student Attendance System)`
- Repository: `https://github.com/rameshwx/n-wallet`
- Handover date: `2026-02-24`
- Current branch: `main`

## 2) Application Scope
N Wallet is an attendance system that records attendance only when both checks pass:
- Face verification (server-side embedding match)
- Hall proximity verification using iBeacon evidence (UUID + Major + Minor + RSSI + duration)

The system has four main runtime components:
- `mobile_app` (Flutter + GetX): student app
- `admin_web` (Flutter + GetX): admin panel
- `backend_api` (Laravel + MongoDB): core API and business rules
- `face_service` (FastAPI): face embedding extraction

## 3) Business Rules Implemented
- OTP login for students by email.
- Admin login by email/password (JWT).
- Face enrollment requires exactly 3 photos.
- Attendance is gated by face score threshold and beacon evidence threshold.
- One attendance record per student/session (DB unique index).
- Course code is auto-generated internally (`CRS-0001`, `CRS-0002`, ...).
- In admin course create/update, module codes are auto-created if missing.
- Mobile app support ticket section is removed from UI.

## 4) Current User Flows
- Student:
  - Request OTP -> verify OTP -> permissions -> face enrollment -> view today sessions -> submit attendance.
- Admin:
  - Login -> manage halls/beacons/modules/courses -> import timetable CSV -> manage sessions/students -> view attendance logs/settings.
- Student management:
  - Assign/clear academic profile.
  - Reset enrollment.
  - Edit student details (`email`, `name`).
  - Delete student account.

## 5) Key API Areas
Base URL:
- `http://51.255.201.31:18082/api/v1`

Important groups:
- Student auth: `/auth/student/request-otp`, `/auth/student/verify-otp`
- Student attendance: `/student/attendance/submit`, `/student/attendance/history`
- Enrollment: `/student/enrollment/upload`, `/student/enrollment/status`
- Admin auth: `/auth/admin/login`, `/admin/me`
- Admin entities: `/admin/halls`, `/admin/beacons`, `/admin/modules`, `/admin/courses`
- Student admin operations:
  - `GET /admin/students`
  - `GET /admin/students/{email}`
  - `PATCH /admin/students/{email}`
  - `DELETE /admin/students/{email}`
  - `PATCH /admin/students/{email}/academic-profile`
  - `POST /admin/students/{email}/reset-enrollment`

## 6) Data and Storage
- Database: MongoDB database `nwallet`.
- Enrollment images: Laravel local disk volume mounted at `storage/app`.
- Enrollment image paths follow:
  - `enrollments/{studentEmail}/{timestamp}_{index}.jpg`

## 7) Authentication and Credentials (Current)
- Seed admin:
  - Email: `nwallet.2002@gmail.com`
  - Password: `Nodecmb@2k26`
- Student auth: OTP by email.
- SMTP currently configured for Gmail sender `nwallet.2002@gmail.com`.

Security note:
- Rotate admin credentials, SMTP app password, Mongo credentials, APP/JWT keys immediately after handover.

## 8) Build and Run (Developer)
- Backend stack:
  - `docker compose up -d --build`
  - `./scripts/bootstrap_backend.sh`
- Admin web local:
  - `cd admin_web`
  - `flutter pub get`
  - `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:18082/api/v1`
- Mobile app local:
  - `cd mobile_app`
  - `flutter pub get`
  - `flutter run --dart-define=API_BASE_URL=http://51.255.201.31:18082/api/v1`

## 9) Known Limitations
- HTTP-first deployment, no TLS reverse proxy in current setup.
- No refresh token flow for JWT.
- Mobile support ticket UI removed; backend endpoint still exists but is unused by current app UI.

## 10) Handover Checklist
- Repository access confirmed.
- Admin login confirmed.
- API health endpoint confirmed.
- Admin student edit/delete endpoints confirmed.
- Course create behavior confirmed (auto module creation, auto course code).
- Mobile UI updated to remove support section.
