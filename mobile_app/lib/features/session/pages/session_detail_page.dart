import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/features/auth/controllers/student_auth_controller.dart';
import 'package:mobile_app/features/beacon/controllers/beacon_scan_controller.dart';
import 'package:mobile_app/shared/utils/beacon_ui_formatters.dart';
import 'package:mobile_app/shared/utils/date_time_formatters.dart';
import 'package:mobile_app/shared/utils/student_formatters.dart';
import 'package:mobile_app/shared/widgets/primary_action_button.dart';
import 'package:shared_dart/shared_dart.dart';
import 'package:mobile_app/app/app_routes.dart';

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key});

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  final auth = Get.find<StudentAuthController>();
  final scanner = Get.find<BeaconScanController>();

  late final StudentSessionDto session;
  List<BeaconScanTarget> expectedBeacons = const <BeaconScanTarget>[];
  BeaconScanResult? beaconPreview;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    session = Get.arguments as StudentSessionDto;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => loading = true);
    try {
      final detail = await auth.api.studentSession(session.id);
      expectedBeacons = beaconScanTargetsFromSessionDetail(detail);

      if (expectedBeacons.isNotEmpty) {
        final preview = await scanner.scanAnyEvidence(
          targets: expectedBeacons,
          scanSeconds: 4,
          rssiThreshold: kBeaconPreviewRssiThreshold,
          stabilitySeconds: kBeaconPreviewStabilitySeconds,
        );
        beaconPreview = preview;
      }
    } catch (_) {
      // Keep UI working even if session detail endpoint fails.
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final windowLabel = attendanceWindowLabel(session);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: Get.back,
                          icon: const Icon(
                            Icons.arrow_back_ios_new,
                            color: AppColors.primary,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Session Details',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDE8E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Mandatory Course',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      session.moduleName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 34,
                        height: 1.02,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${session.moduleCode} • ${displayLecturer(session.lecturerEmail)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5EC),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFF4D9BA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer,
                            color: AppColors.warning,
                            size: 26,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ATTENDANCE WINDOW',
                                style: TextStyle(
                                  color: Color(0xFFB83A07),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                windowLabel,
                                style: const TextStyle(
                                  color: Color(0xFF7D2908),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _detailTile(
                            icon: Icons.calendar_today,
                            title: 'Date',
                            value: formatDateReadable(session.sessionDate),
                          ),
                          const Divider(height: 1, color: AppColors.border),
                          _detailTile(
                            icon: Icons.schedule,
                            title: 'Time',
                            value:
                                '${formatTo12Hour(session.startTime)} - ${formatTo12Hour(session.endTime)}',
                          ),
                          const Divider(height: 1, color: AppColors.border),
                          _detailTile(
                            icon: Icons.location_on,
                            title: 'Location',
                            value: displayHall(
                              session.hallName,
                              session.hallId,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _beaconStatusCard(),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: [
                  PrimaryActionButton(
                    text: 'Start Attendance',
                    icon: Icons.face,
                    onPressed: () =>
                        Get.toNamed(AppRoutes.attendance, arguments: session),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _beaconStatusCard() {
    final hasMapping = expectedBeacons.isNotEmpty;
    final hasSignal = beaconPreview?.detected ?? false;
    final status = beaconPreview?.status;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F8F1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB7E8D2)),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: hasSignal
                  ? const Color(0xFF18C889)
                  : const Color(0xFF9DB0C4),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  previewBeaconTitle(hasMapping: hasMapping, status: status),
                  style: TextStyle(
                    color: hasSignal
                        ? const Color(0xFF0D6A43)
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 21,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewBeaconMessage(
                    hasMapping: hasMapping,
                    result: beaconPreview,
                  ),
                  style: TextStyle(
                    color: hasSignal
                        ? const Color(0xFF0D6A43)
                        : AppColors.textSecondary,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.bluetooth,
            color: hasSignal
                ? const Color(0xFF16A874)
                : const Color(0xFF9DAEC1),
            size: 30,
          ),
        ],
      ),
    );
  }

  Widget _detailTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1EE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
