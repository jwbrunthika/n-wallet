import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_app/app/app_colors.dart';
import 'package:mobile_app/app/app_routes.dart';
import 'package:mobile_app/features/attendance/pages/attendance_flow_page.dart';
import 'package:mobile_app/features/attendance/pages/attendance_result_page.dart';
import 'package:mobile_app/features/auth/pages/face_unlock_page.dart';
import 'package:mobile_app/features/auth/pages/login_page.dart';
import 'package:mobile_app/features/auth/pages/otp_page.dart';
import 'package:mobile_app/features/auth/pages/permission_page.dart';
import 'package:mobile_app/features/auth/pages/splash_page.dart';
import 'package:mobile_app/features/camera/pages/capture_face_page.dart';
import 'package:mobile_app/features/camera/pages/identity_auto_capture_page.dart';
import 'package:mobile_app/features/dashboard/pages/home_page.dart';
import 'package:mobile_app/features/enrollment/pages/enrollment_auto_capture_page.dart';
import 'package:mobile_app/features/enrollment/pages/enrollment_wizard_page.dart';
import 'package:mobile_app/features/privacy/pages/privacy_consent_page.dart';
import 'package:mobile_app/features/session/pages/session_detail_page.dart';

class StudentApp extends StatelessWidget {
  const StudentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'N Wallet',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          surface: AppColors.surface,
          error: AppColors.danger,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
          ),
        ),
      ),
      initialRoute: AppRoutes.splash,
      getPages: [
        GetPage(name: AppRoutes.splash, page: () => const SplashPage()),
        GetPage(name: AppRoutes.login, page: () => const LoginPage()),
        GetPage(name: AppRoutes.otp, page: () => const OtpPage()),
        GetPage(
          name: AppRoutes.permissions,
          page: () => const PermissionPage(),
        ),
        GetPage(name: AppRoutes.faceUnlock, page: () => const FaceUnlockPage()),
        GetPage(
          name: AppRoutes.identityCapture,
          page: () => const IdentityAutoCapturePage(),
        ),
        GetPage(
          name: AppRoutes.enroll,
          page: () => const EnrollmentWizardPage(),
        ),
        GetPage(name: AppRoutes.home, page: () => const HomePage()),
        GetPage(name: AppRoutes.session, page: () => const SessionDetailPage()),
        GetPage(
          name: AppRoutes.attendance,
          page: () => const AttendanceFlowPage(),
        ),
        GetPage(
          name: AppRoutes.enrollmentCapture,
          page: () => const EnrollmentAutoCapturePage(),
        ),
        GetPage(name: AppRoutes.capture, page: () => const CaptureFacePage()),
        GetPage(
          name: AppRoutes.attendanceResult,
          page: () => const AttendanceResultPage(),
        ),
        GetPage(
          name: AppRoutes.privacy,
          page: () => const PrivacyConsentPage(),
        ),
      ],
    );
  }
}
