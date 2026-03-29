import 'package:shared_dart/shared_dart.dart';
import 'package:test/test.dart';

void main() {
  test('BeaconEvidence json shape', () {
    final beacon = BeaconEvidence(
      uuid: 'u',
      major: 1,
      minor: 2,
      avgRssi: -66.5,
      durationSec: 10,
      distanceMeters: 4.25,
    );

    expect(beacon.toJson()['major'], 1);
    expect(beacon.toJson()['durationSec'], 10);
    expect(beacon.toJson()['distanceMeters'], 4.25);
  });
}
