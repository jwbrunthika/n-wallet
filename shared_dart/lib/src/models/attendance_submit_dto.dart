import 'beacon_evidence.dart';

class AttendanceSubmitDto {
  AttendanceSubmitDto({required this.sessionId, required this.beaconEvidence});

  final String sessionId;
  final BeaconEvidence beaconEvidence;
}
