# N Wallet Source Code Handover (Beginner Guide)

This document explains the codebase as if you are a first-year Software Engineering student.
It is intentionally detailed and practical.

## 1) What This Project Is

N Wallet is a student attendance system with two checks:

1. Face verification check (student face vs stored template)
2. Beacon proximity check (student must be near the correct lecture hall iBeacon)

If both checks pass, attendance is marked `PRESENT`.
If one check fails, attendance is marked `REJECTED` with a reason code.

## 2) Big Picture Architecture

Think of the system as 5 parts:

1. `mobile_app` (Flutter + GetX)  
   Student app (login, enrollment, attendance, history, settings).
2. `admin_web` (Flutter + GetX)  
   Admin dashboard (courses, halls, sessions, students, settings).
3. `backend_api` (Laravel + MongoDB)  
   Main business logic and all API endpoints.
4. `face_service` (FastAPI + InsightFace)  
   Returns face embeddings from images.
5. `shared_dart`  
   Shared client models and API wrapper used by Flutter apps.

Simple request path:

`Mobile/Admin UI -> Laravel API -> MongoDB`  
`Mobile/Admin UI -> Laravel API -> Face Service` (for face processing only)

## 3) Monorepo Structure

At project root:

- `docker-compose.yml`  
  Runs backend, mongo, face service, admin web.
- `backend_api/`  
  Laravel source code.
- `face_service/`  
  FastAPI face embedding service.
- `mobile_app/`  
  Flutter student app.
- `admin_web/`  
  Flutter admin app.
- `shared_dart/`  
  Shared Dart models + API client.
- `docs/`  
  Handover documents.
- `scripts/bootstrap_backend.sh`  
  Migration + seeding helper.

## 4) Backend API Deep Dive (`backend_api/`)

### 4.1 Startup and Global API Behavior

Main bootstrap file: `backend_api/bootstrap/app.php`

What it sets:

- API routes from `backend_api/routes/api.php`
- middleware alias `token.type` -> `EnsureTokenType`
- standard JSON error envelope for common exceptions

Response envelope format:

- success: `{ "success": true, "data": ... }`
- error: `{ "success": false, "error": { "code", "message", "details" } }`

Base controller with `guarded(...)` helper:

- `backend_api/app/Http/Controllers/Api/V1/ApiController.php`

### 4.2 API Routes

Main routes file: `backend_api/routes/api.php`

Key groups:

- Public:
  - `GET /api/v1/health`
  - `POST /api/v1/auth/student/request-otp`
  - `POST /api/v1/auth/student/verify-otp`
  - `POST /api/v1/auth/admin/login`
- Student protected (`auth:student_api`, `token.type:student`)
  - profile, enrollment, sessions, attendance
- Admin protected (`auth:admin_api`, `token.type:admin`)
  - halls, beacons, modules, courses, timetable import, sessions, students, logs, settings, files

Important: support ticket endpoint was removed from backend.

### 4.3 Authentication and Authorization

Auth config: `backend_api/config/auth.php`

- Guard `student_api` uses JWT + `Student` model
- Guard `admin_api` uses JWT + `Admin` model

Token type protection:

- `backend_api/app/Http/Middleware/EnsureTokenType.php`
- Student/admin JWT tokens include `token_type`
- Middleware blocks token misuse across endpoint groups

### 4.4 OTP Flow (Student Login)

Core service: `backend_api/app/Services/OtpService.php`

Request OTP:

1. Validate email format
2. Throttle resend by cooldown
3. Generate 6-digit OTP
4. Hash OTP (`Hash::make`) before storage
5. Store `otp_requests` document with expiry and attempts
6. Send email (SMTP) or fallback to dev log mode

Verify OTP:

1. Load by `otpRequestId`
2. Check not expired, not used, attempts remaining
3. Check hash (`Hash::check`)
4. Mark request as verified
5. Student auto-created if first login
6. Return JWT token + student profile

Controller: `backend_api/app/Http/Controllers/Api/V1/StudentAuthController.php`

### 4.5 Face Enrollment Flow

Controller: `backend_api/app/Http/Controllers/Api/V1/StudentEnrollmentController.php`  
Service: `backend_api/app/Services/EnrollmentService.php`

Flow:

1. Validate exactly 3 images
2. Confirm student has academic profile (course/batch/studyMode)
3. Save images to local storage:
   - `storage/app/enrollments/{studentEmail}/{timestamp}_{index}.jpg`
4. Send each image to face service via `FaceEmbeddingClient`
5. Average 3 embeddings
6. Normalize vector (L2 normalization)
7. Encrypt vector with `EmbeddingCryptoService`
8. Save encrypted template in student document
9. Set `enrollmentStatus = ENROLLED`

No-face handling:

- Face service 422 `No face detected` is mapped to API code `FACE_NOT_DETECTED`
- Mobile app shows dedicated retake dialog for this code

### 4.6 Attendance Submit Flow

Controller: `backend_api/app/Http/Controllers/Api/V1/StudentAttendanceController.php`  
Service: `backend_api/app/Services/AttendanceDecisionService.php`  
Beacon validator: `backend_api/app/Services/Attendance/BeaconValidationService.php`

Flow:

1. Validate request:
   - `sessionId`
   - `faceFrames[]` (1..3 images)
   - `beaconEvidence` JSON string
2. Load student and session
3. Check student enrolled + session assigned to student profile
4. Check no duplicate attendance for same student + session
5. Check attendance time window
6. Compute best face score across frames (cosine similarity)
7. Validate beacon evidence against expected hall beacon:
   - exact UUID + major + minor
   - RSSI threshold
   - stability duration threshold
8. Store one record:
   - `PRESENT` if both pass
   - else `REJECTED` with reason code

Reason code examples:

- `NOT_ENROLLED`
- `OUTSIDE_WINDOW`
- `FACE_FAIL`
- `BEACON_MISMATCH`
- `BEACON_WEAK`
- `BEACON_UNSTABLE`
- `SESSION_NOT_ASSIGNED`
- `DUPLICATE_ATTENDANCE` (as error/409)

### 4.7 Academic Profile and Course-Aware Session Assignment

Service: `backend_api/app/Services/AcademicProfileService.php`

This service links students to timetable properly:

- Student must have `courseCode + batch + studyMode`
- Session must match student course
- Session batch must match student batch (if session has batch)
- Session delivery mode must match student study mode (or be `BOTH`)

This is why enrollment/attendance is blocked if admin has not assigned profile.

### 4.8 Admin Features (Code View)

Important controllers:

- `AdminCourseController`  
  Course CRUD, auto-generate course code (`CRS-0001`...), auto-create missing module codes.
- `TimetableImportController`  
  CSV parsing, flexible date/time parsing, per-row error collection, import summary.
- `AdminStudentController`  
  Student list/detail/edit/delete, academic profile assignment, enrollment reset, protected image listing.
- `AdminAuthController`  
  Admin login + audit log.
- `AdminSettingsController`  
  Threshold settings.

### 4.9 Security and Encryption in Backend

Face template encryption:

- File: `backend_api/app/Services/EmbeddingCryptoService.php`
- Process:
  - vector array -> JSON string
  - `Crypt::encryptString(...)`
  - base64 encode
- Stored metadata includes algorithm string:
  - `laravel_crypt_aes_256_cbc_base64`

Password hashing:

- Admin password hashes stored in `admins.passwordHash`
- Verified with `Hash::check`

OTP protection:

- OTP stored hashed in `otp_requests.otpHash`
- attempt limits and expiry enforced

### 4.10 MongoDB Models and Indexes

Models are in `backend_api/app/Models/`.

Main collections:

- `students`, `admins`, `otp_requests`
- `lecture_halls`, `beacons`, `modules`
- `courses`, `sessions`
- `attendance_records`
- `timetable_imports`, `audit_logs`, `settings`

Indexes are created in migrations:

- `backend_api/database/migrations/2026_02_22_000000_create_mongo_indexes.php`
- `backend_api/database/migrations/2026_02_23_000100_add_courses_and_academic_profile_indexes.php`

Most important index for correctness:

- unique index on `attendance_records(studentEmail, sessionId)`
  - prevents multiple attendance entries for same student/session

## 5) Face Service Deep Dive (`face_service/`)

### 5.1 Entry and Endpoint

File: `face_service/app/main.py`

- `GET /health`
- `POST /embedding/from-image-bytes` (multipart file field: `image`)

### 5.2 Engine Logic

File: `face_service/app/engine.py`

Flow:

1. Decode image bytes with OpenCV
2. Detect faces using InsightFace `FaceAnalysis`
3. Select largest detected face
4. Read normalized embedding
5. Validate embedding length is 512
6. Compute simple quality score from detection confidence + face area
7. Return embedding + quality + model version

The face service does not store images on disk.
It only returns computed data.

## 6) Shared Dart Package (`shared_dart/`)

This package avoids duplicating DTO/API code between mobile and admin apps.

Main exports:

- `shared_dart/lib/shared_dart.dart`

Core files:

- Models:
  - `src/models/student_session_dto.dart`
  - `src/models/beacon_evidence.dart`
  - `src/models/attendance_submit_dto.dart`
  - `src/models/api_envelope.dart`
  - `src/models/enums.dart`
- API client:
  - `src/services/nwallet_api.dart`

`NWalletApi` wraps `Dio` calls for both student and admin endpoints.

## 7) Mobile App Deep Dive (`mobile_app/`)

Important note: almost all app code is in one file:

- `mobile_app/lib/main.dart`

This works for student projects, but is technical debt for long-term scaling.

### 7.1 Startup and Dependency Injection

At app startup:

1. Initialize Flutter bindings
2. Initialize `GetStorage`
3. Detect available camera list
4. Register controllers with GetX:
   - `StudentAuthController`
   - `BeaconScanController`
   - `StudentDataController`

### 7.2 Routing

Defined with `GetPage` in `StudentApp`.

Main routes:

- `/splash`
- `/login`
- `/otp`
- `/permissions`
- `/enroll`
- `/home`
- `/session`
- `/attendance`
- `/capture`
- `/attendance-result`
- `/privacy`

### 7.3 Main Controllers

`StudentAuthController`:

- OTP request/verify
- token storage in `GetStorage`
- refresh current student profile
- logout

`StudentDataController`:

- fetch today sessions
- fetch attendance history
- warm session cache for history rendering

`BeaconScanController`:

- scans for expected iBeacon
- computes evidence summary:
  - `avgRssi` = average matched RSSI
  - `durationSec` = time between first and last matched sightings

### 7.4 Important Student Screens

- Login + OTP
- Permissions setup
- Face enrollment wizard (3 captures)
- Today sessions list
- Session detail
- Attendance flow
- Attendance result
- History
- Settings
- Privacy & Consent

Support ticket feature has been removed.

### 7.5 Enrollment UX Error Handling

In enrollment submit:

- backend error `FACE_NOT_DETECTED` shows dedicated dialog:
  - “No Face Detected”
  - asks user to retake in good lighting
- `ACADEMIC_PROFILE_REQUIRED` shows assignment-required dialog

## 8) Admin Web Deep Dive (`admin_web/`)

Similar to mobile, most code is in one file:

- `admin_web/lib/main.dart`

### 8.1 Main Structure

- `AuthController`:
  - admin login
  - token storage
  - fetch `/admin/me`
- `AdminDataController`:
  - central data loading and CRUD calls for all tabs

Dashboard navigation uses `NavigationRail` with tabs:

1. Dashboard
2. Halls
3. Beacons
4. Modules
5. Courses
6. Import CSV
7. Sessions
8. Students
9. Attendance
10. Settings

### 8.2 Student Management in Admin

From Students tab, admin can:

- view students
- edit email/name
- delete student
- assign/clear academic profile
- reset enrollment
- view enrollment image links

### 8.3 Timetable Import UX

Import page includes:

- required CSV header display
- sample row display
- import result feedback:
  - success
  - partial success
  - failure with first error summary

## 9) End-to-End Flows (How Data Moves)

### 9.1 Student Login Flow

1. Mobile sends email to `/auth/student/request-otp`
2. Backend stores hashed OTP request
3. Student enters OTP
4. Backend verifies OTP hash
5. Backend returns JWT token
6. Mobile stores token and uses it in `Authorization: Bearer ...`

### 9.2 Enrollment Flow

1. Student captures 3 photos
2. Mobile uploads multipart `images[]`
3. Backend stores files locally
4. Backend calls face service per image
5. Backend builds averaged normalized embedding
6. Backend encrypts template and saves to student document

### 9.3 Attendance Flow

1. Student opens session detail
2. Mobile scans beacon for ~10 seconds
3. Mobile captures 1..3 face frames
4. Mobile submits multipart request
5. Backend checks window + duplicate + profile
6. Backend computes face score + beacon checks
7. Backend stores final attendance record
8. Mobile shows result page

## 10) How to Work on This Codebase Safely

If you are a beginner, follow this order when making a change:

1. Update backend model/service/controller first
2. Update shared Dart DTO/API client second
3. Update mobile/admin UI last
4. Run local tests/analyzers
5. Test one full end-to-end scenario

### Example: Add a new student field

1. Add fillable/casts in `Student` model
2. Update controller responses where student object is returned
3. Add validation in update endpoints
4. Update admin UI forms
5. Update mobile UI only if needed

### Example: Add a new attendance reject reason

1. Add reason in `AttendanceDecisionService`
2. Ensure frontend mapping/labels include it
3. Test rejected flow in mobile history page

## 11) Debugging Guide

### If OTP email is not received

Check:

1. `.env.docker` mail settings
2. backend logs for SMTP errors
3. `OTP_DEV_MODE` value

### If enrollment fails with 500 or 422

Check:

1. backend logs (`FACE_NOT_DETECTED`, storage errors, profile errors)
2. face service logs
3. image size/format

### If admin login works but page actions fail

Check:

1. browser network tab
2. JWT token exists in local storage
3. API URL used in admin web build

### If attendance submits always reject

Check:

1. student has academic profile assigned
2. session belongs to student course/batch/mode
3. hall has enabled beacon mapping
4. face score threshold and beacon threshold settings

## 12) Testing Status and Gaps

Current backend tests are mostly unit-level:

- `EmbeddingCryptoServiceTest`
- `BeaconValidationServiceTest`

There are no complete API feature tests yet for all flows.
A recommended next step is adding feature tests for OTP, enrollment, attendance, and timetable import.

## 13) Current Technical Debt (Important for Next Team)

1. Both Flutter apps are single-file (`main.dart`) heavy codebases.
2. Better folder/module separation is needed:
   - `features/auth`, `features/enrollment`, `features/attendance`, etc.
3. HTTP-only deployment should be upgraded to HTTPS for production.
4. More automated tests are needed for backend APIs and Flutter UI logic.

## 14) Suggested Refactor Plan (Simple and Safe)

Phase 1:

- Split Flutter code by feature folders without changing UI behavior.

Phase 2:

- Move business logic from controllers/widgets into dedicated repositories/services.

Phase 3:

- Add backend feature tests for critical flows.

Phase 4:

- Add TLS reverse proxy and tighten server security.

## 15) Final Notes for New Developers

If you feel lost, start here in this exact order:

1. `backend_api/routes/api.php`
2. `backend_api/app/Http/Controllers/Api/V1/StudentAttendanceController.php`
3. `backend_api/app/Services/AttendanceDecisionService.php`
4. `shared_dart/lib/src/services/nwallet_api.dart`
5. `mobile_app/lib/main.dart` (search by route/page name)
6. `admin_web/lib/main.dart` (search by page class name)

If you understand these files, you understand most of the system.
