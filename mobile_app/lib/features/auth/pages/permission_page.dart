import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/features/auth/controllers/student_auth_controller.dart';
import 'package:mobile_app/shared/widgets/primary_action_button.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mobile_app/app/app_routes.dart';

class PermissionPage extends StatefulWidget {
  const PermissionPage({super.key});

  @override
  State<PermissionPage> createState() => _PermissionPageState();
}

class _PermissionPageState extends State<PermissionPage> {
  final auth = Get.find<StudentAuthController>();

  bool cameraGranted = false;
  bool bluetoothGranted = false;
  bool locationGranted = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    cameraGranted = await Permission.camera.isGranted;
    bluetoothGranted =
        await Permission.bluetoothScan.isGranted ||
        await Permission.bluetooth.isGranted ||
        await Permission.bluetoothConnect.isGranted;
    locationGranted = await Permission.locationWhenInUse.isGranted;

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _requestCamera() async {
    await Permission.camera.request();
    await _check();
  }

  Future<void> _requestBluetooth() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    await _check();
  }

  Future<void> _requestLocation() async {
    await Permission.locationWhenInUse.request();
    await _check();
  }

  void _continue() {
    if (!cameraGranted || !bluetoothGranted || !locationGranted) {
      Get.snackbar(
        'Permissions required',
        'Please enable camera, bluetooth and location before continuing.',
      );
      return;
    }

    if (auth.enrollmentStatus.value == 'ENROLLED') {
      if (auth.requiresFaceUnlock.value) {
        Get.offAllNamed(AppRoutes.faceUnlock);
      } else {
        Get.offAllNamed(AppRoutes.home);
      }
    } else {
      Get.offAllNamed(AppRoutes.enroll);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _progressBarPiece(
                            active: true,
                            margin: const EdgeInsets.only(right: 8),
                          ),
                        ),
                        Expanded(
                          child: _progressBarPiece(
                            active: false,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                        ),
                        Expanded(
                          child: _progressBarPiece(
                            active: false,
                            margin: const EdgeInsets.only(left: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'STEP 1 OF 3',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Center(
                      child: Text(
                        'Set up your N Wallet',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'To mark your attendance automatically, we need access to a few device capabilities.',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _permissionCard(
                      title: 'Camera Access',
                      description:
                          'Used to verify your identity quickly via Face ID scanning.',
                      icon: Icons.face,
                      granted: cameraGranted,
                      onEnable: _requestCamera,
                    ),
                    const SizedBox(height: 14),
                    _permissionCard(
                      title: 'Bluetooth',
                      description:
                          'Detects classroom iBeacons to confirm your precise location.',
                      icon: Icons.bluetooth,
                      granted: bluetoothGranted,
                      onEnable: _requestBluetooth,
                    ),
                    const SizedBox(height: 14),
                    _permissionCard(
                      title: 'Location Services',
                      description:
                          'Ensures you are physically present on campus grounds.',
                      icon: Icons.location_on,
                      granted: locationGranted,
                      onEnable: _requestLocation,
                      highlight: true,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  PrimaryActionButton(text: 'Continue', onPressed: _continue),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Get.snackbar(
                        'Permission guide',
                        'Camera for face verification, Bluetooth and Location for iBeacon proximity checks.',
                      );
                    },
                    child: const Text(
                      'Why do we need this?',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBarPiece({
    required bool active,
    EdgeInsets margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.primary : const Color(0xFFD8DEE8),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  Widget _permissionCard({
    required String title,
    required String description,
    required IconData icon,
    required bool granted,
    required VoidCallback onEnable,
    bool highlight = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: highlight ? const Color(0xFFB8D2C4) : const Color(0xFFE2E7EE),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F3C9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(icon, color: const Color(0xFF79C600), size: 32),
              ),
              if (granted)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 17,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                granted
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Enabled',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : OutlinedButton(
                        onPressed: onEnable,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 8,
                          ),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: const Text(
                          'Enable',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
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
