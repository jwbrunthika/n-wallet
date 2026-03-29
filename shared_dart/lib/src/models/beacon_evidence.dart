class BeaconEvidence {
  BeaconEvidence({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.avgRssi,
    required this.durationSec,
    this.pingCount = 0,
  });

  final String uuid;
  final int major;
  final int minor;
  final double avgRssi;
  final int durationSec;
  final int pingCount;

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'major': major,
      'minor': minor,
      'avgRssi': avgRssi,
      'durationSec': durationSec,
      'pingCount': pingCount,
    };
  }
}
