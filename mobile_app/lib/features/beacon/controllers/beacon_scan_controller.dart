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
  }) async {
    BeaconScanResult emptyResult(BeaconScanStatus status) {
      return BeaconScanResult(
        status: status,
        evidence: BeaconEvidence(
          uuid: uuid,
          major: major,
          minor: minor,
          avgRssi: -999,
          durationSec: 0,
          distanceMeters: null,
        ),
      );
    }

    if (uuid.trim().isEmpty) {
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

    final region = Region(
      identifier: 'nwallet-${uuid.toLowerCase()}',
      proximityUUID: uuid,
    );
    final stream = flutterBeacon.ranging([region]);

    final rssiReadings = <int>[];
    DateTime? firstSeen;
    DateTime? lastSeen;
    StreamSubscription<RangingResult>? subscription;
    final completer = Completer<BeaconScanResult>();

    void safeComplete(BeaconScanResult result) {
      if (completer.isCompleted) {
        return;
      }
      scanning.value = false;
      completer.complete(result);
    }

    // Beacon evidence summary logic:
    // 1) only keep readings matching expected UUID/Major/Minor
    // 2) avgRssi = arithmetic mean of matched RSSI values
    // 3) durationSec = rounded matched dwell time using millisecond precision
    // 4) distanceMeters = best non-zero estimated distance observed during the scan
    scanning.value = true;
    distanceMeters.value = null;
    final distanceReadings = <double>[];
    try {
      subscription = stream.listen(
        (result) {
          for (final beacon in result.beacons) {
            final matches =
                beacon.proximityUUID.toLowerCase() == uuid.toLowerCase() &&
                beacon.major == major &&
                beacon.minor == minor;
            if (!matches) continue;

            final now = DateTime.now();
            firstSeen ??= now;
            lastSeen = now;
            rssiReadings.add(beacon.rssi);
            if (beacon.accuracy > 0) {
              distanceReadings.add(beacon.accuracy);
              final bestDistance = distanceReadings.reduce(math.min);
              distanceMeters.value = bestDistance;
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
      if (rssiReadings.isEmpty) {
        safeComplete(emptyResult(BeaconScanStatus.notFound));
        return;
      }

      final avgRssi =
          rssiReadings.reduce((a, b) => a + b) / rssiReadings.length;
      final duration = firstSeen != null && lastSeen != null
          ? math.max(
              1,
              (lastSeen!.difference(firstSeen!).inMilliseconds / 1000).round(),
            )
          : 0;
      final bestDistance = distanceReadings.isEmpty
          ? null
          : distanceReadings.reduce(math.min);

      final evidence = BeaconEvidence(
        uuid: uuid,
        major: major,
        minor: minor,
        avgRssi: avgRssi,
        durationSec: duration,
        distanceMeters: bestDistance,
      );

      final closeEnough =
          bestDistance != null &&
          bestDistance > 0 &&
          bestDistance <= maxDistanceMeters;
      final enoughPresence = duration >= stabilitySeconds || closeEnough;
      final status = avgRssi < rssiThreshold
          ? BeaconScanStatus.weak
          : !enoughPresence
          ? BeaconScanStatus.unstable
          : BeaconScanStatus.matched;

      safeComplete(BeaconScanResult(status: status, evidence: evidence));
    });

    return completer.future;
  }
}
