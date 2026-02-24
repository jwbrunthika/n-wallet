class BeaconEvidence {
  BeaconEvidence({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.avgRssi,
    required this.durationSec,
  });

  final String uuid;
  final int major;
  final int minor;
  final double avgRssi;
  final int durationSec;

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'major': major,
      'minor': minor,
      'avgRssi': avgRssi,
      'durationSec': durationSec,
    };
  }
}
