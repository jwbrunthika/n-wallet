class BeaconEvidence {
  BeaconEvidence({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.avgRssi,
    required this.durationSec,
    this.distanceMeters,
  });

  final String uuid;
  final int major;
  final int minor;
  final double avgRssi;
  final int durationSec;
  final double? distanceMeters;

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'major': major,
      'minor': minor,
      'avgRssi': avgRssi,
      'durationSec': durationSec,
      'distanceMeters': distanceMeters,
    };
  }
}
