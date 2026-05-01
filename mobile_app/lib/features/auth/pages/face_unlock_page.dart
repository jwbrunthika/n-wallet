import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide MultipartFile;
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/features/auth/controllers/student_auth_controller.dart';
import 'package:mobile_app/shared/utils/dio_error.dart';
import 'package:mobile_app/shared/utils/student_formatters.dart';
import 'package:mobile_app/shared/widgets/primary_action_button.dart';
import 'package:mobile_app/app/app_routes.dart';

class FaceUnlockPage extends StatefulWidget {
  const FaceUnlockPage({super.key});

  @override
  State<FaceUnlockPage> createState() => _FaceUnlockPageState();
}

class _FaceUnlockPageState extends State<FaceUnlockPage> {
  final auth = Get.find<StudentAuthController>();

  bool verifying = false;

  Future<void> _captureAndVerify() async {
    final result = await Get.toNamed(AppRoutes.identityCapture) as String?;
    if (result == null || result.isEmpty) return;

    setState(() => verifying = true);
    try {
      final frame = MultipartFile.fromFileSync(
        result,
        filename: result.split('/').last,
      );

      await auth.api.verifyStudentIdentity([frame]);
      auth.markFaceUnlockVerified();
      Get.offAllNamed(AppRoutes.home);
      Get.snackbar(
        'Identity verified',
        'Face recognition successful.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on DioException catch (error) {
      Get.snackbar(
        'Verification failed',
        extractDioError(error),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) {
        setState(() => verifying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: verifying ? null : auth.logout,
                  child: const Text('Log out'),
                ),
              ),
              const Spacer(),
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F3C9),
                  borderRadius: BorderRadius.circular(66),
                ),
                child: const Icon(
                  Icons.face,
                  color: AppColors.primary,
                  size: 64,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Verify Your Identity',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Welcome back${auth.email.value == null ? '' : ', ${nameFromEmail(auth.email.value)}'}. '
                'Use a quick face scan before entering your dashboard.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 17,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: AppColors.primary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This verifies that the enrolled student is the person opening the app. '
                        'Your stored face template is matched on the server using the same secure pipeline used for attendance.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryActionButton(
                text: 'Scan Face',
                busy: verifying,
                onPressed: verifying ? null : _captureAndVerify,
              ),
              const SizedBox(height: 12),
              const Text(
                'Use good lighting and keep your full face centered in the frame.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
