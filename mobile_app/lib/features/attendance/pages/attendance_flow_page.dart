import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide MultipartFile;
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/features/auth/controllers/student_auth_controller.dart';
import 'package:mobile_app/features/beacon/controllers/beacon_scan_controller.dart';
import 'package:mobile_app/shared/utils/beacon_ui_formatters.dart';
import 'package:mobile_app/shared/utils/dio_error.dart';
import 'package:mobile_app/shared/utils/student_formatters.dart';
import 'package:mobile_app/shared/widgets/primary_action_button.dart';
import 'package:shared_dart/shared_dart.dart';
import 'package:mobile_app/app/app_routes.dart';

class AttendanceFlowPage extends StatefulWidget {
  const AttendanceFlowPage({super.key});

  @override
  State<AttendanceFlowPage> createState() => _AttendanceFlowPageState();
}

class _AttendanceFlowPageState extends State<AttendanceFlowPage> {
  final auth = Get.find<StudentAuthController>();
  final beaconScanner = Get.find<BeaconScanController>();

  late final StudentSessionDto session;
  Map<String, dynamic>? expectedBeacon;

  BeaconScanResult? beaconResult;
  bool loadingDetail = true;
  bool submitting = false;
  int elapsedScanSec = 0;
  Timer? scanTimer;

  static const int beaconStabilityTargetSec = kBeaconUiStabilitySeconds;
  static const double beaconDistanceTargetMeters = kBeaconUiMaxDistanceMeters;

  @override
  void initState() {
    super.initState();
    session = Get.arguments as StudentSessionDto;
    _prepare();
  }

  @override
  void dispose() {
    scanTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      loadingDetail = true;
      beaconResult = null;
    });

    try {
      final detail = await auth.api.studentSession(session.id);
      final beacon = detail['expectedBeacon'];
      if (beacon is Map) {
        expectedBeacon = Map<String, dynamic>.from(beacon);
      }

      if (expectedBeacon == null) {
        Get.snackbar('Beacon', 'No beacon mapped for this hall.');
      } else {
        await _scanBeacon();
      }
    } on DioException catch (error) {
      Get.snackbar(
        'Session load failed',
        error.message ?? 'Unable to load session detail.',
      );
    } finally {
      if (mounted) {
        setState(() => loadingDetail = false);
      }
    }
  }

  Future<void> _scanBeacon() async {
    if (expectedBeacon == null) return;

    scanTimer?.cancel();
    setState(() {
      elapsedScanSec = 0;
      beaconResult = null;
    });

    scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (elapsedScanSec >= 10) {
        timer.cancel();
        return;
      }
      setState(() {
        elapsedScanSec += 1;
      });
    });

    final scanned = await beaconScanner.scanEvidence(
      uuid: (expectedBeacon!['uuid'] as String?) ?? '',
      major: (expectedBeacon!['major'] as num?)?.toInt() ?? 0,
      minor: (expectedBeacon!['minor'] as num?)?.toInt() ?? 0,
      scanSeconds: 10,
    );

    scanTimer?.cancel();
    if (!mounted) return;

    setState(() {
      beaconResult = scanned;
      elapsedScanSec = 10;
    });
  }

  Future<void> _captureAndSubmit() async {
    if (beaconResult == null || !beaconResult!.matched) {
      Get.snackbar(
        'Attendance',
        'A verified hall beacon is required before you continue.',
      );
      return;
    }

    final result = await Get.toNamed(AppRoutes.capture) as String?;
    if (result == null || result.isEmpty) return;

    await _submitAttendance(result);
  }

  Future<void> _submitAttendance(String framePath) async {
    setState(() => submitting = true);
    try {
      final frame = MultipartFile.fromFileSync(
        framePath,
        filename: framePath.split('/').last,
      );
      final payload = AttendanceSubmitDto(
        sessionId: session.id,
        beaconEvidence: beaconResult!.evidence,
      );

      final response = await auth.api.submitAttendance(
        attendance: payload,
        frames: [frame],
      );

      final status = response['status'] as String? ?? 'REJECTED';
      final faceScore = (response['faceScore'] as num?)?.toDouble() ?? 0;
      final reasonCode = response['reasonCode'] as String?;

      Get.offNamed(
        AppRoutes.attendanceResult,
        arguments: {
          'session': session,
          'status': status,
          'faceScore': faceScore,
          'reasonCode': reasonCode,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } on DioException catch (error) {
      Get.snackbar('Submit failed', extractDioError(error));
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final scanning = beaconScanner.scanning.value;
          final result = beaconResult;
          final hasMatchedBeacon = result?.matched ?? false;
          final hasDetectedSignal = result?.detected ?? false;
          final canConfirm = !scanning && hasMatchedBeacon && !submitting;
          final rssi = result?.evidence.avgRssi ?? -999;
          final stability =
              result?.evidence.durationSec ??
              math.min(elapsedScanSec, beaconStabilityTargetSec);
          final measuredDistance =
              result?.evidence.distanceMeters ??
              beaconScanner.distanceMeters.value;
          final displayDistance = measuredDistance == null
              ? '--'
              : measuredDistance.toStringAsFixed(1);
          final distanceLimitLabel = beaconDistanceTargetMeters.toStringAsFixed(
            0,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: Get.back,
                      icon: const Icon(Icons.arrow_back_ios_new),
                    ),
                    const Expanded(
                      child: Text(
                        'Proximity Check',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      onPressed: scanning || loadingDetail ? null : _scanBeacon,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      _radarStatus(scanning),
                      const SizedBox(height: 24),
                      Text(
                        attendanceBeaconTitle(
                          scanning: scanning,
                          result: result,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF798380),
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${displayHall(session.hallName, session.hallId)} • ${session.moduleName}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 20,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      _signalBars(rssi),
                      const SizedBox(height: 8),
                      Text(
                        hasDetectedSignal
                            ? '${rssi.toStringAsFixed(0)} dBm  ${beaconStrengthLabel(rssi).toUpperCase()}'
                            : 'Waiting for hall beacon signal',
                        style: TextStyle(
                          color: hasMatchedBeacon
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        attendanceBeaconMessage(
                          scanning: scanning,
                          result: result,
                        ),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Distance Check',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Need to be within $distanceLimitLabel m',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$displayDistance m',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 26,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${math.min(stability, beaconStabilityTargetSec)}/${beaconStabilityTargetSec}s stable',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: attendanceBeaconBadgeBackground(
                                      scanning: scanning,
                                      result: result,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    attendanceBeaconBadgeLabel(
                                      scanning: scanning,
                                      result: result,
                                    ),
                                    style: TextStyle(
                                      color: attendanceBeaconBadgeForeground(
                                        scanning: scanning,
                                        result: result,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      PrimaryActionButton(
                        text: 'Confirm Attendance',
                        busy: submitting,
                        disabledColor: const Color(0xFFB8C5D6),
                        onPressed: canConfirm ? _captureAndSubmit : null,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        attendanceBeaconFooter(
                          scanning: scanning,
                          result: result,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF90A0B8),
                          fontSize: 17,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (loadingDetail || scanning)
                        const Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _radarStatus(bool scanning) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEAF0ED),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: scanning ? 120 : 110,
            height: scanning ? 120 : 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFD5DFDA),
              border: Border.all(color: Colors.white, width: 8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.sensors,
              size: 44,
              color: scanning ? AppColors.primary : const Color(0xFF6A788F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _signalBars(double rssi) {
    final bars = rssiBars(rssi);
    return SizedBox(
      height: 90,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(bars.length, (index) {
          final active = bars[index] > 0;
          return Container(
            width: 16,
            height: 26 + (bars[index] * 58),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : const Color(0xFFD3DBE6),
              borderRadius: BorderRadius.circular(10),
            ),
          );
        }),
      ),
    );
  }
}
