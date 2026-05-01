import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/features/auth/controllers/student_auth_controller.dart';
import 'package:mobile_app/features/student/controllers/student_data_controller.dart';
import 'package:mobile_app/shared/utils/date_time_formatters.dart';
import 'package:mobile_app/shared/utils/student_formatters.dart';
import 'package:mobile_app/shared/widgets/primary_action_button.dart';
import 'package:shared_dart/shared_dart.dart';
import 'package:mobile_app/app/app_routes.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = Get.find<StudentDataController>();
    final auth = Get.find<StudentAuthController>();

    return Obx(() {
      final sessions = data.todaySessions.toList();
      final nowSession =
          _pickCurrentSession(sessions) ??
          (sessions.isNotEmpty ? sessions.first : null);
      final nextSessions = sessions
          .where((session) => nowSession == null || session.id != nowSession.id)
          .toList();

      return SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await data.fetchTodaySessions();
            await data.fetchHistory();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Row(
                children: [
                  const Text(
                    'N Wallet',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFBFD0D8),
                    child: Text(
                      initialsFromEmail(auth.email.value),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: 128,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCE8E1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFAAC1B2)),
                ),
                child: Text(
                  auth.enrollmentStatus.value,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Hello, ${nameFromEmail(auth.email.value)}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1.04,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Here is your schedule for today.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
              const SizedBox(height: 24),
              _dateChip(DateTime.now()),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text(
                    'CURRENT SESSION',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      fontSize: 22,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: Color(0xFF76D29B),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              nowSession == null
                  ? _emptyCard(
                      'No session for today. Pull to refresh after admin timetable import.',
                    )
                  : _CurrentSessionCard(session: nowSession),
              const SizedBox(height: 22),
              const Text(
                'UP NEXT',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 12),
              if (nextSessions.isEmpty)
                _emptyCard('No upcoming sessions today.')
              else
                ...nextSessions.map(
                  (session) => _UpcomingSessionCard(session: session),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _dateChip(DateTime now) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = weekdays[now.weekday - 1];
    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            weekday,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          Text(
            '${now.day}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }

  StudentSessionDto? _pickCurrentSession(List<StudentSessionDto> sessions) {
    final now = DateTime.now();
    for (final session in sessions) {
      final openTime = attendanceWindowOpensAt(session);
      final closeTime = attendanceWindowClosesAt(session);
      if (openTime == null ||
          closeTime == null ||
          !closeTime.isAfter(openTime)) {
        continue;
      }

      if (!now.isBefore(openTime) && !now.isAfter(closeTime)) {
        return session;
      }
    }
    return null;
  }
}

class _CurrentSessionCard extends StatelessWidget {
  const _CurrentSessionCard({required this.session});

  final StudentSessionDto session;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEFEF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'LIVE NOW',
                  style: TextStyle(
                    color: Color(0xFFE53935),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.calculate, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            session.moduleName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            displayLecturer(session.lecturerEmail),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.schedule, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(
                '${formatTo12Hour(session.startTime)} - ${formatTo12Hour(session.endTime)}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  displayHall(session.hallName, session.hallId),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 19,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          PrimaryActionButton(
            text: 'Mark Attendance',
            icon: Icons.face,
            onPressed: () => Get.toNamed(AppRoutes.session, arguments: session),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Requires Bluetooth & FaceID',
              style: TextStyle(color: Color(0xFF8B9CB6), fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingSessionCard extends StatelessWidget {
  const _UpcomingSessionCard({required this.session});

  final StudentSessionDto session;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Get.toNamed(AppRoutes.session, arguments: session),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 72,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F6F9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Text(
                    formatAmPmShort(session.startTime),
                    style: const TextStyle(
                      color: Color(0xFF91A2B8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatHourMinute(session.startTime),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.moduleName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${session.moduleCode} - ${displayLecturer(session.lecturerEmail)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFA4B3C7)),
          ],
        ),
      ),
    );
  }
}
