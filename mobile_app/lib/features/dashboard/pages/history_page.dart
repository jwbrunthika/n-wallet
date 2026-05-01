import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/features/student/controllers/student_data_controller.dart';
import 'package:mobile_app/shared/utils/date_time_formatters.dart';
import 'package:mobile_app/shared/utils/student_formatters.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final data = Get.find<StudentDataController>();
  String filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Obx(() {
        var rows = data.history.toList();
        if (filter != 'ALL') {
          rows = rows.where((row) => '${row['status']}' == filter).toList();
        }

        rows.sort((a, b) {
          final aDate = DateTime.tryParse('${a['createdAt'] ?? ''}');
          final bDate = DateTime.tryParse('${b['createdAt'] ?? ''}');
          if (aDate == null || bDate == null) return 0;
          return bDate.compareTo(aDate);
        });

        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final row in rows) {
          final key = monthGroupLabel(row['createdAt'] as String?);
          grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
        }

        return RefreshIndicator(
          onRefresh: data.fetchHistory,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            children: [
              const Text(
                'History',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _historyChip(
                      'All',
                      filter == 'ALL',
                      () => setState(() => filter = 'ALL'),
                    ),
                    const SizedBox(width: 10),
                    _historyChip(
                      'Present',
                      filter == 'PRESENT',
                      () => setState(() => filter = 'PRESENT'),
                    ),
                    const SizedBox(width: 10),
                    _historyChip(
                      'Rejected',
                      filter == 'REJECTED',
                      () => setState(() => filter = 'REJECTED'),
                    ),
                    const SizedBox(width: 10),
                    _historyChip(
                      'Date Range',
                      false,
                      null,
                      icon: Icons.calendar_month,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (rows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'No attendance records found for the selected filter.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...grouped.entries.expand((entry) {
                  return [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: Color(0xFF8196B2),
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    ...entry.value.map((row) => _historyCard(row)),
                    const SizedBox(height: 6),
                  ];
                }),
            ],
          ),
        );
      }),
    );
  }

  Widget _historyChip(
    String text,
    bool active,
    VoidCallback? onTap, {
    IconData? icon,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : const Color(0xFFF1F5FA),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD1DCE8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  icon,
                  size: 16,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            Text(
              text,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF3D536F),
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> row) {
    final status = '${row['status'] ?? 'REJECTED'}'.toUpperCase();
    final rejected = status == 'REJECTED';
    final sessionId = row['sessionId'] as String? ?? '-';
    final session = data.sessionCache[sessionId];

    final title = session?.moduleName ?? 'Session $sessionId';
    final subtitle = session == null
        ? 'Session ID: $sessionId'
        : displayHall(session.hallName, session.hallId);
    final createdAt = formatDateTimeShort(row['createdAt'] as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (rejected)
            Container(
              width: 4,
              height: 152,
              decoration: const BoxDecoration(
                color: Color(0xFFF05252),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: rejected
                          ? const Color(0xFFF8EEEE)
                          : const Color(0xFFEDF2F8),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Icon(
                      rejected ? Icons.calculate : Icons.code,
                      color: rejected
                          ? const Color(0xFFD64949)
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _statusBadge(status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        if (rejected) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${row['reasonCode'] ?? 'Rejected'}',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 16,
                              color: Color(0xFF8DA0BA),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              createdAt,
                              style: const TextStyle(
                                color: Color(0xFF8DA0BA),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final rejected = status == 'REJECTED';
    final bg = rejected ? const Color(0xFFFDECEC) : const Color(0xFFE8F6ED);
    final color = rejected ? AppColors.danger : AppColors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            rejected ? Icons.cancel : Icons.check_circle,
            color: color,
            size: 15,
          ),
          const SizedBox(width: 4),
          Text(
            rejected ? 'Rejected' : 'Present',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
