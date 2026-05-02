import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_dart/shared_dart.dart';

const double kBeaconUiRssiThreshold = -70;
const int kBeaconUiStabilitySeconds = 8;
const double kBeaconUiMaxDistanceMeters = 10;
const double kBeaconPreviewRssiThreshold = -90;
const int kBeaconPreviewStabilitySeconds = 1;

enum BeaconScanStatus {
  noMapping,
  bluetoothOff,
  locationPermissionDenied,
  locationServicesOff,
  scanFailed,
  notFound,
  weak,
  unstable,
  matched,
}

class BeaconScanTarget {
  const BeaconScanTarget({
    required this.uuid,
    required this.major,
    required this.minor,
  });

  factory BeaconScanTarget.fromMap(Map<dynamic, dynamic> map) {
    return BeaconScanTarget(
      uuid: (map['uuid'] as String?)?.trim() ?? '',
      major: (map['major'] as num?)?.toInt() ?? 0,
      minor: (map['minor'] as num?)?.toInt() ?? 0,
    );
  }

  final String uuid;
  final int major;
  final int minor;

  bool get hasIdentity => uuid.trim().isNotEmpty;
}

List<BeaconScanTarget> beaconScanTargetsFromSessionDetail(
  Map<String, dynamic> detail,
) {
  final beaconList = detail['expectedBeacons'];
  if (beaconList is List) {
    final targets = beaconList
        .whereType<Map<dynamic, dynamic>>()
        .map(BeaconScanTarget.fromMap)
        .where((target) => target.hasIdentity)
        .toList();
    if (targets.isNotEmpty) {
      return targets;
    }
  }

  final legacyBeacon = detail['expectedBeacon'];
  if (legacyBeacon is Map) {
    final target = BeaconScanTarget.fromMap(legacyBeacon);
    if (target.hasIdentity) {
      return [target];
    }
  }

  return const <BeaconScanTarget>[];
}

String _targetKey(String uuid, int major, int minor) {
  return '${uuid.toLowerCase()}|$major|$minor';
}

class BeaconScanResult {
  const BeaconScanResult({required this.status, required this.evidence});

  final BeaconScanStatus status;
  final BeaconEvidence evidence;

  bool get matched => status == BeaconScanStatus.matched;
  bool get detected => evidence.avgRssi > -999;
}

class BeaconScanController extends GetxController {
  final RxBool scanning = false.obs;
  final RxnDouble distanceMeters = RxnDouble();

  Future<BeaconScanResult> scanEvidence({
    required String uuid,
    required int major,
    required int minor,
    int scanSeconds = 10,
    double rssiThreshold = kBeaconUiRssiThreshold,
    int stabilitySeconds = kBeaconUiStabilitySeconds,
    double maxDistanceMeters = kBeaconUiMaxDistanceMeters,
  }) {
    return scanAnyEvidence(
      targets: [BeaconScanTarget(uuid: uuid, major: major, minor: minor)],
      scanSeconds: scanSeconds,
      rssiThreshold: rssiThreshold,
      stabilitySeconds: stabilitySeconds,
      maxDistanceMeters: maxDistanceMeters,
    );
  }

  Future<BeaconScanResult> scanAnyEvidence({
    required List<BeaconScanTarget> targets,
    int scanSeconds = 10,
    double rssiThreshold = kBeaconUiRssiThreshold,
    int stabilitySeconds = kBeaconUiStabilitySeconds,
    double maxDistanceMeters = kBeaconUiMaxDistanceMeters,
  }) async {
    final normalizedTargets = _dedupeTargets(targets);

    BeaconScanResult emptyResult(BeaconScanStatus status) {
      final target = normalizedTargets.isNotEmpty
          ? normalizedTargets.first
          : const BeaconScanTarget(uuid: '', major: 0, minor: 0);
      return BeaconScanResult(
        status: status,
        evidence: BeaconEvidence(
          uuid: target.uuid,
          major: target.major,
          minor: target.minor,
          avgRssi: -999,
          durationSec: 0,
          distanceMeters: null,
        ),
      );
    }

    if (normalizedTargets.isEmpty) {
      return emptyResult(BeaconScanStatus.noMapping);
    }

    try {
      final bluetoothState = await flutterBeacon.bluetoothState;
      if (bluetoothState != BluetoothState.stateOn) {
        return emptyResult(BeaconScanStatus.bluetoothOff);
      }

      final hasLocationPermission =
          await Permission.locationWhenInUse.isGranted;
      if (!hasLocationPermission) {
        return emptyResult(BeaconScanStatus.locationPermissionDenied);
      }

      final authorizationStatus = await flutterBeacon.authorizationStatus;
      final locationAuthorized = Platform.isIOS
          ? authorizationStatus == AuthorizationStatus.whenInUse ||
                authorizationStatus == AuthorizationStatus.always
          : authorizationStatus == AuthorizationStatus.allowed;
      if (!locationAuthorized) {
        return emptyResult(BeaconScanStatus.locationPermissionDenied);
      }

      final locationServicesEnabled =
          await flutterBeacon.checkLocationServicesIfEnabled;
      if (!locationServicesEnabled) {
        return emptyResult(BeaconScanStatus.locationServicesOff);
      }

      await flutterBeacon.initializeScanning;
    } catch (_) {
      return emptyResult(BeaconScanStatus.scanFailed);
    }

    final regions = _regionsForTargets(normalizedTargets);
    final stream = flutterBeacon.ranging(regions);
    final accumulators = {
      for (final target in normalizedTargets)
        _targetKey(target.uuid, target.major, target.minor):
            _BeaconReadingAccumulator(target),
    };

    StreamSubscription<RangingResult>? subscription;
    final completer = Completer<BeaconScanResult>();

    void safeComplete(BeaconScanResult result) {
      if (completer.isCompleted) {
        return;
      }
      scanning.value = false;
      completer.complete(result);
    }

    // Evidence summary logic:
    // 1) only keep readings matching one configured UUID/Major/Minor target
    // 2) avgRssi = arithmetic mean of matched RSSI values for the chosen target
    // 3) durationSec = rounded matched dwell time using millisecond precision
    // 4) distanceMeters = best non-zero estimated distance observed
    scanning.value = true;
    distanceMeters.value = null;
    try {
      subscription = stream.listen(
        (result) {
          for (final beacon in result.beacons) {
            final accumulator =
                accumulators[_targetKey(
                  beacon.proximityUUID,
                  beacon.major,
                  beacon.minor,
                )];
            if (accumulator == null) continue;

            accumulator.add(beacon);
            final bestDistance = accumulator.bestDistance;
            if (bestDistance != null) {
              final currentDistance = distanceMeters.value;
              if (currentDistance == null || bestDistance < currentDistance) {
                distanceMeters.value = bestDistance;
              }
            }
          }
        },
        onError: (_) async {
          await subscription?.cancel();
          safeComplete(emptyResult(BeaconScanStatus.scanFailed));
        },
      );
    } catch (_) {
      await subscription?.cancel();
      safeComplete(emptyResult(BeaconScanStatus.scanFailed));
    }

    Future<void>.delayed(Duration(seconds: scanSeconds), () async {
      await subscription?.cancel();
      final summaries = accumulators.values
          .where((accumulator) => accumulator.hasReadings)
          .map(
            (accumulator) => accumulator.summary(
              rssiThreshold: rssiThreshold,
              stabilitySeconds: stabilitySeconds,
              maxDistanceMeters: maxDistanceMeters,
            ),
          )
          .toList();

      if (summaries.isEmpty) {
        safeComplete(emptyResult(BeaconScanStatus.notFound));
        return;
      }

      final matched = summaries
          .where((summary) => summary.status == BeaconScanStatus.matched)
          .toList();
      final unstable = summaries
          .where((summary) => summary.status == BeaconScanStatus.unstable)
          .toList();
      final chosen = matched.isNotEmpty
          ? _strongestSummary(matched)
          : unstable.isNotEmpty
          ? _strongestSummary(unstable)
          : _strongestSummary(summaries);

      safeComplete(
        BeaconScanResult(status: chosen.status, evidence: chosen.evidence),
      );
    });

    return completer.future;
  }

  List<BeaconScanTarget> _dedupeTargets(List<BeaconScanTarget> targets) {
    final seenKeys = <String>{};
    final normalizedTargets = <BeaconScanTarget>[];

    for (final target in targets) {
      final normalized = BeaconScanTarget(
        uuid: target.uuid.trim(),
        major: target.major,
        minor: target.minor,
      );
      if (!normalized.hasIdentity) continue;

      final key = _targetKey(
        normalized.uuid,
        normalized.major,
        normalized.minor,
      );
      if (seenKeys.add(key)) {
        normalizedTargets.add(normalized);
      }
    }

    return normalizedTargets;
  }

  List<Region> _regionsForTargets(List<BeaconScanTarget> targets) {
    final uuidByLowercase = <String, String>{};
    for (final target in targets) {
      uuidByLowercase.putIfAbsent(target.uuid.toLowerCase(), () => target.uuid);
    }

    return uuidByLowercase.entries
        .map(
          (entry) => Region(
            identifier: 'nwallet-${entry.key}',
            proximityUUID: entry.value,
          ),
        )
        .toList();
  }

  _BeaconScanSummary _strongestSummary(List<_BeaconScanSummary> summaries) {
    summaries.sort(
      (left, right) => right.evidence.avgRssi.compareTo(left.evidence.avgRssi),
    );
    return summaries.first;
  }
}

class _BeaconReadingAccumulator {
  _BeaconReadingAccumulator(this.target);

  final BeaconScanTarget target;
  final List<int> rssiReadings = <int>[];
  final List<double> distanceReadings = <double>[];
  DateTime? firstSeen;
  DateTime? lastSeen;

  bool get hasReadings => rssiReadings.isNotEmpty;

  double? get bestDistance {
    if (distanceReadings.isEmpty) {
      return null;
    }
    return distanceReadings.reduce(math.min);
  }

  void add(Beacon beacon) {
    final now = DateTime.now();
    firstSeen ??= now;
    lastSeen = now;
    rssiReadings.add(beacon.rssi);
    if (beacon.accuracy > 0) {
      distanceReadings.add(beacon.accuracy);
    }
  }

  _BeaconScanSummary summary({
    required double rssiThreshold,
    required int stabilitySeconds,
    required double maxDistanceMeters,
  }) {
    final avgRssi = rssiReadings.reduce((a, b) => a + b) / rssiReadings.length;
    final duration = firstSeen != null && lastSeen != null
        ? math.max(
            1,
            (lastSeen!.difference(firstSeen!).inMilliseconds / 1000).round(),
          )
        : 0;
    final distance = bestDistance;
    final closeEnough =
        distance != null && distance > 0 && distance <= maxDistanceMeters;
    final enoughPresence = duration >= stabilitySeconds || closeEnough;
    final status = avgRssi < rssiThreshold
        ? BeaconScanStatus.weak
        : !enoughPresence
        ? BeaconScanStatus.unstable
        : BeaconScanStatus.matched;

    return _BeaconScanSummary(
      status: status,
      evidence: BeaconEvidence(
        uuid: target.uuid,
        major: target.major,
        minor: target.minor,
        avgRssi: avgRssi,
        durationSec: duration,
        distanceMeters: distance,
      ),
    );
  }
}

class _BeaconScanSummary {
  const _BeaconScanSummary({required this.status, required this.evidence});

  final BeaconScanStatus status;
  final BeaconEvidence evidence;
}
