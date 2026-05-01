import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/shared/utils/beacon_ui_formatters.dart';
import 'package:mobile_app/shared/utils/date_time_formatters.dart';
import 'package:mobile_app/shared/utils/student_formatters.dart';
import 'package:mobile_app/shared/widgets/primary_action_button.dart';
import 'package:shared_dart/shared_dart.dart';
import 'package:mobile_app/app/app_routes.dart';

class AttendanceResultPage extends StatelessWidget {
  const AttendanceResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Map<String, dynamic>.from(Get.arguments as Map? ?? {});
    final session = args['session'] as StudentSessionDto?;
    final status = (args['status'] as String? ?? 'REJECTED').toUpperCase();
    final faceScore = (args['faceScore'] as num?)?.toDouble() ?? 0;
    final reasonCode = args['reasonCode'] as String?;
    final timestamp = args['timestamp'] as String?;
    final success = status == 'PRESENT';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: Get.back,
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.primary,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Attendance Verified',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 42),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
                child: Column(
                  children: [
                    Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        success ? Icons.check : Icons.close,
                        color: success ? AppColors.primary : AppColors.danger,
                        size: 88,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      status,
                      style: TextStyle(
                        color: success ? AppColors.primary : AppColors.danger,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      success
                          ? 'Successfully recorded on N Wallet'
                          : attendanceRejectMessage(reasonCode),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        _resultPill(
                          icon: Icons.face,
                          label: 'FACE ID',
                          success: success,
                        ),
                        _resultPill(
                          icon: Icons.bluetooth,
                          label: 'iBEACON',
                          success: success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: const Border(
                                bottom: BorderSide(color: AppColors.border),
                              ),
                              color: const Color(0xFFF0F5F2),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Text(
                                  'SESSION DETAILS',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                Spacer(),
                                Icon(
                                  Icons.verified_user,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                          _resultDetail(
                            icon: Icons.school,
                            label: 'MODULE',
                            value: session?.moduleName ?? '-',
                          ),
                          _resultDetail(
                            icon: Icons.location_on,
                            label: 'LOCATION',
                            value: session == null
                                ? '-'
                                : displayHall(session.hallName, session.hallId),
                          ),
                          _resultDetail(
                            icon: Icons.schedule,
                            label: 'TIMESTAMP',
                            value: formatDateTimeFromIso(timestamp),
                          ),
                          _resultDetail(
                            icon: Icons.percent,
                            label: 'FACE SCORE',
                            value: faceScore.toStringAsFixed(3),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
              child: PrimaryActionButton(
                text: 'Done',
                icon: Icons.check,
                onPressed: () => Get.offAllNamed(AppRoutes.home),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'N WALLET SECURE',
                style: TextStyle(
                  color: Color(0xFFAAB6C8),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultPill({
    required IconData icon,
    required String label,
    required bool success,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFDDE9E3) : const Color(0xFFF8E4E4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: success ? const Color(0xFFBDD1C4) : const Color(0xFFF0C3C3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: success ? AppColors.primary : AppColors.danger),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: success ? AppColors.primary : AppColors.danger,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultDetail({
    required IconData icon,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFE8EDF3))),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEF4),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, color: const Color(0xFF6B7F9B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
