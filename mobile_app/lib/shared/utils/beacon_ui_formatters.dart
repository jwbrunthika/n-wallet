import 'package:flutter/material.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/features/beacon/controllers/beacon_scan_controller.dart';

String previewBeaconTitle({
  required bool hasMapping,
  required BeaconScanStatus? status,
}) {
  if (!hasMapping || status == BeaconScanStatus.noMapping) {
    return 'No Beacon Mapping';
  }

  switch (status) {
    case BeaconScanStatus.bluetoothOff:
      return 'Bluetooth Off';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Location Permission Required';
    case BeaconScanStatus.locationServicesOff:
      return 'Location Services Off';
    case BeaconScanStatus.scanFailed:
      return 'Beacon Scan Failed';
    case BeaconScanStatus.notFound:
      return 'Hall Beacon Not Detected';
    case BeaconScanStatus.weak:
    case BeaconScanStatus.unstable:
    case BeaconScanStatus.matched:
      return 'Hall Beacon Detected';
    case BeaconScanStatus.noMapping:
    case null:
      return 'Hall Beacon Mapped';
  }
}

String previewBeaconMessage({
  required bool hasMapping,
  required BeaconScanResult? result,
}) {
  if (!hasMapping) {
    return 'Admin has not mapped an active beacon for this hall.';
  }

  final status = result?.status;
  switch (status) {
    case BeaconScanStatus.bluetoothOff:
      return 'Turn on Bluetooth to detect the hall beacon.';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Allow location access so the app can range iBeacons.';
    case BeaconScanStatus.locationServicesOff:
      return 'Turn on location services to scan for the hall beacon.';
    case BeaconScanStatus.scanFailed:
      return 'Unable to read the hall beacon right now. Please try again.';
    case BeaconScanStatus.notFound:
      return 'Move closer to the lecture hall beacon and refresh.';
    case BeaconScanStatus.weak:
      return 'Signal strength is ${beaconStrengthLabel(result!.evidence.avgRssi)}. Move closer for attendance.';
    case BeaconScanStatus.unstable:
      return 'Beacon detected. Hold the device steady for a moment.';
    case BeaconScanStatus.matched:
      return 'Signal Strength: ${beaconStrengthLabel(result!.evidence.avgRssi)}';
    case BeaconScanStatus.noMapping:
    case null:
      return 'Scanning for the mapped hall beacon.';
  }
}

String attendanceBeaconTitle({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) return 'Searching for Beacon...';

  switch (result?.status) {
    case BeaconScanStatus.noMapping:
      return 'No Beacon Mapping';
    case BeaconScanStatus.bluetoothOff:
      return 'Bluetooth Off';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Location Permission Needed';
    case BeaconScanStatus.locationServicesOff:
      return 'Location Services Off';
    case BeaconScanStatus.scanFailed:
      return 'Scan Failed';
    case BeaconScanStatus.notFound:
      return 'No Beacon Found';
    case BeaconScanStatus.weak:
      return 'Beacon Signal Too Weak';
    case BeaconScanStatus.unstable:
      return 'Hold Steady Near Beacon';
    case BeaconScanStatus.matched:
      return 'Beacon Verified';
    case null:
      return 'Waiting for Beacon Scan';
  }
}

String attendanceBeaconMessage({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) {
    return 'Looking for the exact hall beacon using UUID, major and minor.';
  }

  switch (result?.status) {
    case BeaconScanStatus.noMapping:
      return 'No active beacon is mapped to this lecture hall yet.';
    case BeaconScanStatus.bluetoothOff:
      return 'Turn on Bluetooth, then scan again.';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Allow location access for iBeacon proximity checks.';
    case BeaconScanStatus.locationServicesOff:
      return 'Turn on location services, then retry the beacon scan.';
    case BeaconScanStatus.scanFailed:
      return 'The beacon scan failed. Retry once you are near the lecture hall.';
    case BeaconScanStatus.notFound:
      return 'The expected hall beacon was not detected during this scan.';
    case BeaconScanStatus.weak:
      return 'The correct beacon was found, but the signal is too weak right now.';
    case BeaconScanStatus.unstable:
      return 'The correct beacon was found, but you are still too far away from it.';
    case BeaconScanStatus.matched:
      return 'Hall beacon identity and proximity checks passed.';
    case null:
      return 'Start a scan while standing inside the lecture hall.';
  }
}

String attendanceBeaconBadgeLabel({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) return 'Scanning';

  switch (result?.status) {
    case BeaconScanStatus.matched:
      return 'Verified';
    case BeaconScanStatus.weak:
      return 'Weak signal';
    case BeaconScanStatus.unstable:
      return 'Move closer';
    case BeaconScanStatus.notFound:
      return 'Not found';
    case BeaconScanStatus.bluetoothOff:
      return 'Bluetooth off';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Permission needed';
    case BeaconScanStatus.locationServicesOff:
      return 'Location off';
    case BeaconScanStatus.scanFailed:
      return 'Retry';
    case BeaconScanStatus.noMapping:
      return 'No mapping';
    case null:
      return 'Waiting';
  }
}

Color attendanceBeaconBadgeBackground({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) {
    return const Color(0xFFE3ECF7);
  }

  switch (result?.status) {
    case BeaconScanStatus.matched:
      return const Color(0xFFD3F7E4);
    case BeaconScanStatus.weak:
    case BeaconScanStatus.unstable:
      return const Color(0xFFFFEDD5);
    case BeaconScanStatus.notFound:
    case BeaconScanStatus.bluetoothOff:
    case BeaconScanStatus.locationPermissionDenied:
    case BeaconScanStatus.locationServicesOff:
    case BeaconScanStatus.scanFailed:
    case BeaconScanStatus.noMapping:
    case null:
      return const Color(0xFFE7EDF5);
  }
}

Color attendanceBeaconBadgeForeground({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) {
    return const Color(0xFF5E718F);
  }

  switch (result?.status) {
    case BeaconScanStatus.matched:
      return AppColors.success;
    case BeaconScanStatus.weak:
    case BeaconScanStatus.unstable:
      return AppColors.warning;
    case BeaconScanStatus.notFound:
    case BeaconScanStatus.bluetoothOff:
    case BeaconScanStatus.locationPermissionDenied:
    case BeaconScanStatus.locationServicesOff:
    case BeaconScanStatus.scanFailed:
    case BeaconScanStatus.noMapping:
    case null:
      return AppColors.textSecondary;
  }
}

String attendanceBeaconFooter({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) {
    return 'Stay inside the lecture hall until the beacon scan completes.';
  }

  switch (result?.status) {
    case BeaconScanStatus.matched:
      return 'Beacon verification passed. You can continue to face capture.';
    case BeaconScanStatus.weak:
      return 'Move closer to the hall beacon and scan again.';
    case BeaconScanStatus.unstable:
      return 'Move to within 10 meters of the hall beacon, then scan again.';
    case BeaconScanStatus.notFound:
      return 'Please stand inside the lecture hall and retry the scan.';
    case BeaconScanStatus.bluetoothOff:
      return 'Enable Bluetooth before retrying the hall beacon scan.';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Grant location permission before retrying the hall beacon scan.';
    case BeaconScanStatus.locationServicesOff:
      return 'Turn on location services before retrying the hall beacon scan.';
    case BeaconScanStatus.scanFailed:
      return 'Retry the beacon scan while standing near the lecture hall beacon.';
    case BeaconScanStatus.noMapping:
      return 'Ask an admin to map an active beacon to this lecture hall.';
    case null:
      return 'Please stay within the lecture hall for successful verification.';
  }
}

String attendanceRejectMessage(String? reasonCode) {
  switch ((reasonCode ?? '').toUpperCase()) {
    case 'BEACON_MISMATCH':
      return 'The detected beacon does not match this lecture hall.';
    case 'BEACON_WEAK':
      return 'The correct hall beacon was found, but the signal was too weak.';
    case 'BEACON_UNSTABLE':
      return 'The correct hall beacon was found, but you were not close enough to it.';
    case 'FACE_FAIL':
      return 'Face verification did not pass.';
    case 'OUTSIDE_WINDOW':
      return 'Attendance is closed for this session.';
    case 'SESSION_NOT_ASSIGNED':
      return 'This session is not assigned to your academic profile.';
    case 'NOT_ENROLLED':
      return 'Face enrollment is required before attendance can be submitted.';
  }

  return reasonCode ?? 'Attendance rejected.';
}

String beaconStrengthLabel(double rssi) {
  if (rssi >= -65) return 'Strong';
  if (rssi >= -75) return 'Medium';
  if (rssi >= -90) return 'Weak';
  return 'No signal';
}

List<double> rssiBars(double rssi) {
  if (rssi < -120) {
    return const [0, 0, 0, 0, 0];
  }

  if (rssi >= -60) {
    return const [0.45, 0.65, 0.9, 0.55, 0.35];
  }
  if (rssi >= -70) {
    return const [0.35, 0.55, 0.78, 0.42, 0.2];
  }
  if (rssi >= -80) {
    return const [0.2, 0.35, 0.55, 0.2, 0.1];
  }
  if (rssi >= -90) {
    return const [0.1, 0.22, 0.35, 0.08, 0];
  }
  return const [0, 0, 0, 0, 0];
}
