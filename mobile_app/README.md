# N Wallet Mobile App (Flutter + GetX)

## Run
```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
```

For physical devices, replace API URL with your VPS/public host.

## Implemented Screens
- Splash
- Login (email)
- OTP verification
- Permissions setup
- Face enrollment wizard (3 captures)
- Today sessions list
- Session detail
- Attendance flow (face capture + beacon scan + submit)
- History
- Support report issue
- Settings/logout
