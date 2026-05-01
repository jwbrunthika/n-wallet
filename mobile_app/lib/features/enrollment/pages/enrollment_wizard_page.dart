import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide MultipartFile;
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/features/auth/controllers/student_auth_controller.dart';
import 'package:mobile_app/shared/utils/dio_error.dart';
import 'package:mobile_app/shared/widgets/primary_action_button.dart';
import 'package:mobile_app/app/app_routes.dart';

class EnrollmentWizardPage extends StatefulWidget {
  const EnrollmentWizardPage({super.key});

  @override
  State<EnrollmentWizardPage> createState() => _EnrollmentWizardPageState();
}

class _EnrollmentWizardPageState extends State<EnrollmentWizardPage> {
  final auth = Get.find<StudentAuthController>();

  final List<String?> imagePaths = <String?>[null, null, null];
  final List<String> stepNames = <String>[
    'LOOK FORWARD',
    'TURN ONE SIDE',
    'TURN OTHER SIDE',
  ];

  int activeStep = 0;
  bool submitting = false;

  Future<void> _startGuidedCapture() async {
    final result = await Get.toNamed(AppRoutes.enrollmentCapture);
    if (result is! List) return;

    final paths = result.whereType<String>().toList();
    if (paths.length != 3) return;

    setState(() {
      for (var i = 0; i < imagePaths.length; i++) {
        imagePaths[i] = paths[i];
      }
      activeStep = 0;
    });
  }

  String? _extractApiErrorCode(DioException error) {
    final payload = error.response?.data;
    if (payload is Map<String, dynamic>) {
      final apiError = payload['error'];
      if (apiError is Map<String, dynamic>) {
        final code = apiError['code'];
        if (code is String && code.trim().isNotEmpty) {
          return code.trim();
        }
      }
    }
    return null;
  }

  void _resetEnrollmentCaptures() {
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < imagePaths.length; i++) {
        imagePaths[i] = null;
      }
      activeStep = 0;
    });
  }

  Future<void> _showNoFaceDetectedDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.face_retouching_off,
                        color: AppColors.warning,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'No Face Detected',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Retake photos in good lighting and keep your full face centered inside the guide.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _resetEnrollmentCaptures();
                        },
                        child: const Text('Retake Photos'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAcademicProfileRequiredDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Academic Profile Required'),
          content: const Text(
            'Your course, batch, and study mode are not assigned yet. '
            'Please contact the admin before submitting enrollment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit() async {
    if (imagePaths.any((path) => path == null)) {
      Get.snackbar('Enrollment', 'Complete the guided face scan first.');
      return;
    }

    setState(() {
      submitting = true;
    });

    try {
      final files = imagePaths
          .whereType<String>()
          .map(
            (path) => MultipartFile.fromFileSync(
              path,
              filename: path.split('/').last,
            ),
          )
          .toList();

      final response = await auth.api.uploadEnrollment(files);
      final status = response['enrollmentStatus'] as String? ?? 'FAILED';
      auth.setEnrollmentStatus(status);

      if (status == 'ENROLLED') {
        Get.offAllNamed(AppRoutes.home);
      } else {
        Get.snackbar('Enrollment failed', 'Please retry with better lighting.');
      }
    } on DioException catch (error) {
      final errorCode = _extractApiErrorCode(error);
      if (errorCode == 'FACE_NOT_DETECTED') {
        await _showNoFaceDetectedDialog();
      } else if (errorCode == 'ACADEMIC_PROFILE_REQUIRED') {
        await _showAcademicProfileRequiredDialog();
      } else {
        Get.snackbar('Enrollment failed', extractDioError(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capturedCount = imagePaths.whereType<String>().length;
    final progress = capturedCount / 3;
    final currentImagePath = imagePaths[activeStep];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: Get.back,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const Expanded(
                        child: Text(
                          'Face Enrollment',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Step ${activeStep + 1} of 3',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        stepNames[activeStep],
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      color: AppColors.primary,
                      backgroundColor: const Color(0xFFD6E1DA),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Start one guided scan. The app will detect your face and capture three angles automatically.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 17,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: _EnrollmentPreview(imagePath: currentImagePath),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(3, (index) {
                      final selected = activeStep == index;
                      final done = imagePaths[index] != null;
                      return GestureDetector(
                        onTap: () => setState(() => activeStep = index),
                        child: Container(
                          width: 34,
                          height: 34,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(
                              color: selected
                                  ? AppColors.primary
                                  : const Color(0xFFD2DAE5),
                            ),
                          ),
                          child: Center(
                            child: done
                                ? const Icon(
                                    Icons.check_circle,
                                    color: AppColors.primary,
                                    size: 20,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  PrimaryActionButton(
                    text: capturedCount == 3
                        ? 'Retake Guided Scan'
                        : 'Start Guided Scan',
                    icon: Icons.videocam_rounded,
                    onPressed: submitting ? null : _startGuidedCapture,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Look forward first, then slowly turn to one side and the other when prompted.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock, size: 16, color: Color(0xFF8B9CB6)),
                      SizedBox(width: 6),
                      Text(
                        'Biometric data is encrypted & stored locally',
                        style: TextStyle(
                          color: Color(0xFF8B9CB6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  PrimaryActionButton(
                    text: 'Submit Enrollment',
                    busy: submitting,
                    onPressed: capturedCount == 3 && !submitting
                        ? _submit
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnrollmentPreview extends StatelessWidget {
  const _EnrollmentPreview({required this.imagePath});

  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imagePath != null)
              Image.file(File(imagePath!), fit: BoxFit.cover)
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3A3A3A), Color(0xFF1F1F1F)],
                  ),
                ),
              ),
            Container(color: Colors.black.withValues(alpha: 0.2)),
            Center(
              child: Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 3,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Good Lighting',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(44),
                child: CustomPaint(painter: _CornerFramePainter()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0E8A4A)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final radius = 18.0;
    final line = 34.0;

    final path = Path()
      ..moveTo(0, line)
      ..lineTo(0, radius)
      ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
      ..moveTo(size.width - line, 0)
      ..lineTo(size.width - radius, 0)
      ..arcToPoint(Offset(size.width, radius), radius: Radius.circular(radius))
      ..moveTo(size.width, size.height - line)
      ..lineTo(size.width, size.height - radius)
      ..arcToPoint(
        Offset(size.width - radius, size.height),
        radius: Radius.circular(radius),
      )
      ..moveTo(line, size.height)
      ..lineTo(radius, size.height)
      ..arcToPoint(
        Offset(0, size.height - radius),
        radius: Radius.circular(radius),
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
