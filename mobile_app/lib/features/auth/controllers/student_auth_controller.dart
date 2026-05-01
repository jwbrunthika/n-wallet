import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:mobile_app/app/app_config.dart';
import 'package:shared_dart/shared_dart.dart';
import 'package:mobile_app/app/app_routes.dart';

class StudentAuthController extends GetxController {
  final GetStorage _storage = GetStorage();
  late final NWalletApi api;

  final RxnString token = RxnString();
  final RxnString email = RxnString();
  final RxString enrollmentStatus = 'NOT_ENROLLED'.obs;
  final RxnString courseCode = RxnString();
  final RxnString batch = RxnString();
  final RxnString studyMode = RxnString();
  final RxnString otpRequestId = RxnString();
  final Rxn<DateTime> otpExpiresAt = Rxn<DateTime>();
  final Rxn<DateTime> otpResendAvailableAt = Rxn<DateTime>();
  final RxBool loading = false.obs;
  final RxBool requiresFaceUnlock = false.obs;

  bool _restoredSession = false;

  bool get isLoggedIn => (token.value ?? '').isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    api = NWalletApi(baseUrl: kApiBaseUrl);

    final savedToken = _storage.read<String>('student_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      _restoredSession = true;
      token.value = savedToken;
      api.setToken(savedToken);
      email.value = _storage.read<String>('student_email');
      enrollmentStatus.value =
          _storage.read<String>('enrollment_status') ?? 'NOT_ENROLLED';
      courseCode.value = _storage.read<String>('student_course_code');
      batch.value = _storage.read<String>('student_batch');
      studyMode.value = _storage.read<String>('student_study_mode');
      requiresFaceUnlock.value = enrollmentStatus.value == 'ENROLLED';
    }
  }

  Future<void> requestOtp(String emailInput) async {
    loading.value = true;
    try {
      final normalizedEmail = emailInput.trim().toLowerCase();
      final response = await api.requestStudentOtp(normalizedEmail);
      otpRequestId.value = response['otpRequestId'] as String?;
      email.value = normalizedEmail;

      final expiresInSec = (response['expiresInSec'] as num?)?.toInt() ?? 300;
      otpExpiresAt.value = DateTime.now().add(Duration(seconds: expiresInSec));
      otpResendAvailableAt.value = DateTime.now().add(
        const Duration(seconds: 60),
      );

      Get.toNamed(AppRoutes.otp);
      Get.snackbar(
        'OTP sent',
        'Check your email inbox for the 6-digit OTP.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on DioException catch (error) {
      Get.snackbar('OTP request failed', _extractError(error));
    } finally {
      loading.value = false;
    }
  }

  Future<void> verifyOtp(String otp) async {
    final requestId = otpRequestId.value;
    if (requestId == null || requestId.isEmpty) {
      Get.snackbar('OTP error', 'OTP request ID is missing.');
      return;
    }

    loading.value = true;
    try {
      final response = await api.verifyStudentOtp(requestId, otp);
      final accessToken = response['accessToken'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('JWT token missing.');
      }

      final student = Map<String, dynamic>.from(
        response['student'] as Map? ?? {},
      );

      token.value = accessToken;
      api.setToken(accessToken);
      email.value = student['email'] as String?;
      enrollmentStatus.value =
          student['enrollmentStatus'] as String? ?? 'NOT_ENROLLED';
      courseCode.value = student['courseCode'] as String?;
      batch.value = student['batch'] as String?;
      studyMode.value = student['studyMode'] as String?;
      _restoredSession = false;
      requiresFaceUnlock.value = false;

      _storage.write('student_token', accessToken);
      _storage.write('student_email', email.value ?? '');
      _storage.write('enrollment_status', enrollmentStatus.value);
      _storage.write('student_course_code', courseCode.value);
      _storage.write('student_batch', batch.value);
      _storage.write('student_study_mode', studyMode.value);

      Get.offAllNamed(AppRoutes.permissions);
    } on DioException catch (error) {
      Get.snackbar('OTP verification failed', _extractError(error));
    } finally {
      loading.value = false;
    }
  }

  Future<void> refreshMe() async {
    if (!isLoggedIn) return;

    try {
      final me = await api.studentMe();
      email.value = me['email'] as String?;
      enrollmentStatus.value =
          me['enrollmentStatus'] as String? ?? 'NOT_ENROLLED';
      courseCode.value = me['courseCode'] as String?;
      batch.value = me['batch'] as String?;
      studyMode.value = me['studyMode'] as String?;
      requiresFaceUnlock.value =
          _restoredSession && enrollmentStatus.value == 'ENROLLED';
      _storage.write('student_email', email.value ?? '');
      _storage.write('enrollment_status', enrollmentStatus.value);
      _storage.write('student_course_code', courseCode.value);
      _storage.write('student_batch', batch.value);
      _storage.write('student_study_mode', studyMode.value);
    } catch (_) {
      logout();
    }
  }

  void setEnrollmentStatus(String status) {
    enrollmentStatus.value = status;
    _storage.write('enrollment_status', status);
  }

  void markFaceUnlockVerified() {
    _restoredSession = false;
    requiresFaceUnlock.value = false;
  }

  void logout() {
    _restoredSession = false;
    token.value = null;
    email.value = null;
    enrollmentStatus.value = 'NOT_ENROLLED';
    courseCode.value = null;
    batch.value = null;
    studyMode.value = null;
    otpRequestId.value = null;
    otpExpiresAt.value = null;
    otpResendAvailableAt.value = null;
    requiresFaceUnlock.value = false;
    api.setToken(null);

    _storage.remove('student_token');
    _storage.remove('student_email');
    _storage.remove('enrollment_status');
    _storage.remove('student_course_code');
    _storage.remove('student_batch');
    _storage.remove('student_study_mode');

    Get.offAllNamed(AppRoutes.login);
  }

  String _extractError(DioException error) {
    final payload = error.response?.data;
    if (payload is Map<String, dynamic>) {
      final err = payload['error'];
      if (err is Map<String, dynamic>) {
        return err['message'] as String? ?? error.message ?? 'Unknown error';
      }
    }
    return error.message ?? 'Unknown error';
  }
}
