# shared_dart

Shared Dart package for N Wallet clients.

## Provides
- API DTOs (`StudentSessionDto`, `BeaconEvidence`, `AttendanceSubmitDto`)
- Enums (`EnrollmentStatus`, `Role`)
- Generic `NWalletApi` Dio client used by both Flutter apps

## Usage
Add path dependency:
```yaml
dependencies:
  shared_dart:
    path: ../shared_dart
```

Then initialize:
```dart
final api = NWalletApi(baseUrl: 'http://localhost:8080/api/v1');
api.setToken('jwt-token');
```
