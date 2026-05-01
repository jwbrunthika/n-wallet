import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/features/dashboard/pages/history_page.dart';
import 'package:mobile_app/features/dashboard/pages/student_settings_page.dart';
import 'package:mobile_app/features/dashboard/pages/today_page.dart';
import 'package:mobile_app/features/student/controllers/student_data_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final data = Get.find<StudentDataController>();

  late int tab;

  @override
  void initState() {
    super.initState();
    tab = (Get.arguments is int) ? (Get.arguments as int) : 0;
    data.fetchTodaySessions();
    data.fetchHistory();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const TodayPage(),
      const HistoryPage(),
      const StudentSettingsPage(),
    ];

    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _BottomTabItem(
                label: 'Today',
                icon: Icons.calendar_today,
                active: tab == 0,
                onTap: () => setState(() => tab = 0),
              ),
              _BottomTabItem(
                label: 'History',
                icon: Icons.history,
                active: tab == 1,
                onTap: () => setState(() => tab = 1),
              ),
              _BottomTabItem(
                label: 'Settings',
                icon: Icons.settings,
                active: tab == 2,
                onTap: () => setState(() => tab = 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTabItem extends StatelessWidget {
  const _BottomTabItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: active ? AppColors.primary : const Color(0xFF9BA8BC),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? AppColors.primary : const Color(0xFF9BA8BC),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
