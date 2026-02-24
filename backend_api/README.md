# N Wallet Backend API (Laravel + MongoDB)

## Key Features
- Student OTP authentication (email + dev-log fallback)
- Admin JWT authentication
- Face enrollment image upload + encrypted face template storage
- Attendance submission with face score and beacon evidence checks
- Timetable CSV import and admin CRUD APIs
- Protected admin file endpoints for enrollment images

## Main API Prefix
`/api/v1`

## Setup inside container
```bash
php artisan key:generate --force
php artisan jwt:secret --force
php artisan migrate --seed --force
php artisan serve --host=0.0.0.0 --port=8000
```
