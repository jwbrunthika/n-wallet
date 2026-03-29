import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:camera_android/camera_android.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:get/get.dart' hide MultipartFile;
import 'package:get_storage/get_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_dart/shared_dart.dart';

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://51.255.201.31:18082/api/v1',
);

List<CameraDescription> gCameras = <CameraDescription>[];
String? gCameraLoadError;

class AppColors {
  static const Color primary = Color(0xFF14522D);
  static const Color background = Color(0xFFF4F7F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF0C1732);
  static const Color textSecondary = Color(0xFF5E718F);
  static const Color border = Color(0xFFDDE4ED);
  static const Color success = Color(0xFF22A35A);
  static const Color danger = Color(0xFFE53E3E);
  static const Color warning = Color(0xFFEA580C);
  static const Color muted = Color(0xFFE8EEEA);
}

Future<String?> _ensureCamerasLoaded() async {
  if (gCameras.isNotEmpty) {
    return null;
  }

  try {
    gCameras = await availableCameras();
    gCameraLoadError = null;
  } catch (e) {
    gCameraLoadError = '$e';
    return 'Unable to load camera: $e';
  }

  if (gCameras.isEmpty) {
    return gCameraLoadError == null
        ? 'No camera found on this device.'
        : 'No camera found on this device. Last error: $gCameraLoadError';
  }

  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  if (Platform.isAndroid) {
    AndroidCamera.registerWith();
  }
  await GetStorage.init();
  try {
    gCameras = await availableCameras();
    gCameraLoadError = null;
  } catch (e) {
    gCameras = <CameraDescription>[];
    gCameraLoadError = '$e';
  }

  Get.put(StudentAuthController());
  Get.put(BeaconScanController());
  Get.put(StudentDataController());

  runApp(const StudentApp());
}

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
      initialRoute: '/splash',
      getPages: [
        GetPage(name: '/splash', page: () => const SplashPage()),
        GetPage(name: '/login', page: () => const LoginPage()),
        GetPage(name: '/otp', page: () => const OtpPage()),
        GetPage(name: '/permissions', page: () => const PermissionPage()),
        GetPage(name: '/face-unlock', page: () => const FaceUnlockPage()),
        GetPage(
          name: '/identity-capture',
          page: () => const IdentityAutoCapturePage(),
        ),
        GetPage(name: '/enroll', page: () => const EnrollmentWizardPage()),
        GetPage(name: '/home', page: () => const HomePage()),
        GetPage(name: '/session', page: () => const SessionDetailPage()),
        GetPage(name: '/attendance', page: () => const AttendanceFlowPage()),
        GetPage(
          name: '/enrollment-capture',
          page: () => const EnrollmentAutoCapturePage(),
        ),
        GetPage(name: '/capture', page: () => const CaptureFacePage()),
        GetPage(
          name: '/attendance-result',
          page: () => const AttendanceResultPage(),
        ),
        GetPage(name: '/privacy', page: () => const PrivacyConsentPage()),
      ],
    );
  }
}

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

      Get.toNamed('/otp');
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

      Get.offAllNamed('/permissions');
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

    Get.offAllNamed('/login');
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

class StudentDataController extends GetxController {
  final StudentAuthController auth = Get.find<StudentAuthController>();

  final RxList<StudentSessionDto> todaySessions = <StudentSessionDto>[].obs;
  final RxList<Map<String, dynamic>> history = <Map<String, dynamic>>[].obs;
  final RxMap<String, StudentSessionDto> sessionCache =
      <String, StudentSessionDto>{}.obs;

  final RxBool loadingSessions = false.obs;
  final RxBool loadingHistory = false.obs;

  Future<void> fetchTodaySessions() async {
    if (!auth.isLoggedIn) return;

    loadingSessions.value = true;
    try {
      final date = DateTime.now().toIso8601String().split('T').first;
      final sessions = await auth.api.studentSessionsToday(date);
      todaySessions.assignAll(sessions);
      for (final session in sessions) {
        sessionCache[session.id] = session;
      }
    } on DioException catch (error) {
      Get.snackbar('Sessions error', _extractDioError(error));
    } finally {
      loadingSessions.value = false;
    }
  }

  Future<void> fetchHistory() async {
    if (!auth.isLoggedIn) return;

    loadingHistory.value = true;
    final now = DateTime.now();
    final from = now
        .subtract(const Duration(days: 30))
        .toIso8601String()
        .split('T')
        .first;
    final to = now.toIso8601String().split('T').first;

    try {
      final rows = await auth.api.studentAttendanceHistory(from: from, to: to);
      history.assignAll(rows);
      unawaited(_warmSessionCache(rows));
    } on DioException catch (error) {
      Get.snackbar('History error', _extractDioError(error));
    } finally {
      loadingHistory.value = false;
    }
  }

  Future<void> _warmSessionCache(List<Map<String, dynamic>> rows) async {
    final ids = rows
        .map((row) => row['sessionId'] as String?)
        .whereType<String>()
        .toSet()
        .where((id) => !sessionCache.containsKey(id))
        .take(12)
        .toList();

    for (final id in ids) {
      try {
        final detail = await auth.api.studentSession(id);
        final dto = StudentSessionDto.fromJson(detail);
        sessionCache[id] = dto;
      } catch (_) {
        // History can still render with sessionId when session detail is unavailable.
      }
    }
  }
}

const double kBeaconUiRssiThreshold = -70;
const int kBeaconUiStabilitySeconds = 8;
const int kBeaconUiMinPingCount = 5;
const double kBeaconPreviewRssiThreshold = -90;
const int kBeaconPreviewStabilitySeconds = 1;

enum BeaconScanStatus {
  noMapping,
  bluetoothOff,
  locationPermissionDenied,
  locationServicesOff,
  scanFailed,
  notFound,
  weak,
  unstable,
  matched,
}

class BeaconScanResult {
  const BeaconScanResult({required this.status, required this.evidence});

  final BeaconScanStatus status;
  final BeaconEvidence evidence;

  bool get matched => status == BeaconScanStatus.matched;
  bool get detected => evidence.avgRssi > -999;
}

class BeaconScanController extends GetxController {
  final RxBool scanning = false.obs;
  final RxInt pingCount = 0.obs;

  Future<BeaconScanResult> scanEvidence({
    required String uuid,
    required int major,
    required int minor,
    int scanSeconds = 10,
    double rssiThreshold = kBeaconUiRssiThreshold,
    int stabilitySeconds = kBeaconUiStabilitySeconds,
    int minPingCount = kBeaconUiMinPingCount,
  }) async {
    BeaconScanResult emptyResult(BeaconScanStatus status) {
      return BeaconScanResult(
        status: status,
        evidence: BeaconEvidence(
          uuid: uuid,
          major: major,
          minor: minor,
          avgRssi: -999,
          durationSec: 0,
          pingCount: 0,
        ),
      );
    }

    if (uuid.trim().isEmpty) {
      return emptyResult(BeaconScanStatus.noMapping);
    }

    try {
      final bluetoothState = await flutterBeacon.bluetoothState;
      if (bluetoothState != BluetoothState.stateOn) {
        return emptyResult(BeaconScanStatus.bluetoothOff);
      }

      final hasLocationPermission =
          await Permission.locationWhenInUse.isGranted;
      if (!hasLocationPermission) {
        return emptyResult(BeaconScanStatus.locationPermissionDenied);
      }

      final authorizationStatus = await flutterBeacon.authorizationStatus;
      final locationAuthorized = Platform.isIOS
          ? authorizationStatus == AuthorizationStatus.whenInUse ||
                authorizationStatus == AuthorizationStatus.always
          : authorizationStatus == AuthorizationStatus.allowed;
      if (!locationAuthorized) {
        return emptyResult(BeaconScanStatus.locationPermissionDenied);
      }

      final locationServicesEnabled =
          await flutterBeacon.checkLocationServicesIfEnabled;
      if (!locationServicesEnabled) {
        return emptyResult(BeaconScanStatus.locationServicesOff);
      }

      await flutterBeacon.initializeScanning;
    } catch (_) {
      return emptyResult(BeaconScanStatus.scanFailed);
    }

    final region = Region(
      identifier: 'nwallet-${uuid.toLowerCase()}',
      proximityUUID: uuid,
    );
    final stream = flutterBeacon.ranging([region]);

    final rssiReadings = <int>[];
    DateTime? firstSeen;
    DateTime? lastSeen;
    StreamSubscription<RangingResult>? subscription;
    final completer = Completer<BeaconScanResult>();

    void safeComplete(BeaconScanResult result) {
      if (completer.isCompleted) {
        return;
      }
      scanning.value = false;
      completer.complete(result);
    }

    // Beacon evidence summary logic:
    // 1) only keep readings matching expected UUID/Major/Minor
    // 2) avgRssi = arithmetic mean of matched RSSI values
    // 3) durationSec = rounded matched dwell time using millisecond precision
    // 4) pingCount = number of matching beacon callbacks observed
    scanning.value = true;
    pingCount.value = 0;
    try {
      subscription = stream.listen(
        (result) {
          for (final beacon in result.beacons) {
            final matches =
                beacon.proximityUUID.toLowerCase() == uuid.toLowerCase() &&
                beacon.major == major &&
                beacon.minor == minor;
            if (!matches) continue;

            final now = DateTime.now();
            firstSeen ??= now;
            lastSeen = now;
            rssiReadings.add(beacon.rssi);
            pingCount.value = rssiReadings.length;
          }
        },
        onError: (_) async {
          await subscription?.cancel();
          safeComplete(emptyResult(BeaconScanStatus.scanFailed));
        },
      );
    } catch (_) {
      await subscription?.cancel();
      safeComplete(emptyResult(BeaconScanStatus.scanFailed));
    }

    Future<void>.delayed(Duration(seconds: scanSeconds), () async {
      await subscription?.cancel();
      if (rssiReadings.isEmpty) {
        safeComplete(emptyResult(BeaconScanStatus.notFound));
        return;
      }

      final avgRssi =
          rssiReadings.reduce((a, b) => a + b) / rssiReadings.length;
      final pingTotal = rssiReadings.length;
      final duration = firstSeen != null && lastSeen != null
          ? math.max(
              1,
              (lastSeen!.difference(firstSeen!).inMilliseconds / 1000).round(),
            )
          : 0;

      final evidence = BeaconEvidence(
        uuid: uuid,
        major: major,
        minor: minor,
        avgRssi: avgRssi,
        durationSec: duration,
        pingCount: pingTotal,
      );

      final enoughPresence =
          duration >= stabilitySeconds || pingTotal >= minPingCount;
      final status = avgRssi < rssiThreshold
          ? BeaconScanStatus.weak
          : !enoughPresence
          ? BeaconScanStatus.unstable
          : BeaconScanStatus.matched;

      safeComplete(BeaconScanResult(status: status, evidence: evidence));
    });

    return completer.future;
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final auth = Get.find<StudentAuthController>();
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    if (!auth.isLoggedIn) {
      if (mounted) Get.offAllNamed('/login');
      return;
    }

    await auth.refreshMe();
    if (!mounted) return;
    Get.offAllNamed('/permissions');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.08,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 10,
                ),
                itemBuilder: (_, __) => const Center(
                  child: Icon(Icons.add, size: 14, color: AppColors.primary),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.verified_user,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'N Wallet',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'NSBM GREEN UNIVERSITY ATTENDANCE',
                      style: TextStyle(
                        color: Color(0xFF7AA38B),
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 80),
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9F0EA),
                        borderRadius: BorderRadius.circular(36),
                      ),
                      child: const Icon(
                        Icons.face,
                        color: Color(0xFF5C8A72),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Verifying Identity',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please look at your screen',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(
                        minHeight: 6,
                        value: null,
                        color: AppColors.primary,
                        backgroundColor: Color(0xFFD8E2DB),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final auth = Get.find<StudentAuthController>();
  final emailController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 34),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.account_balance,
                        size: 48,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Welcome to N Wallet',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Verify your identity to access campus services',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Student Email',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(
                        hintText: 'e.g. name@university.edu',
                        prefixIcon: Icon(Icons.badge_outlined),
                        contentPadding: EdgeInsets.symmetric(vertical: 20),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FA),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFD6E4F6)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.info,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'We\'ll send a 6-digit code to your registered university email.',
                              style: TextStyle(
                                fontSize: 17,
                                height: 1.4,
                                color: Color(0xFF374D68),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    Obx(
                      () => PrimaryActionButton(
                        text: 'Send OTP',
                        icon: Icons.arrow_forward,
                        busy: auth.loading.value,
                        onPressed: auth.loading.value
                            ? null
                            : () => auth.requestOtp(emailController.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class OtpPage extends StatefulWidget {
  const OtpPage({super.key});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final auth = Get.find<StudentAuthController>();
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  Timer? _timer;
  int _resendLeftSec = 0;

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      6,
      (_) => TextEditingController(),
    );
    _focusNodes = List<FocusNode>.generate(6, (_) => FocusNode());
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    final availableAt = auth.otpResendAvailableAt.value;
    if (availableAt == null) {
      _resendLeftSec = 0;
      return;
    }

    final left = availableAt.difference(DateTime.now()).inSeconds;
    _resendLeftSec = math.max(0, left);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _resendLeftSec = math.max(0, _resendLeftSec - 1);
      });
      if (_resendLeftSec == 0) {
        timer.cancel();
      }
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      _controllers[index].text = value.substring(value.length - 1);
      _controllers[index].selection = const TextSelection.collapsed(offset: 1);
    }

    if (_controllers[index].text.isNotEmpty && index < _focusNodes.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    setState(() {});
  }

  Future<void> _resendOtp() async {
    final email = auth.email.value;
    if (email == null || email.isEmpty) return;

    await auth.requestOtp(email);
    if (!mounted) return;
    _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    final targetEmail = _maskEmail(auth.email.value ?? 'student@example.com');

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: Get.back,
                icon: const Icon(Icons.arrow_back_ios_new),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7EFEA),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(
                        Icons.mark_email_read,
                        color: AppColors.primary,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Check your email',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Please enter the code sent to',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      targetEmail,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List<Widget>.generate(6, (index) {
                        return SizedBox(
                          width: 52,
                          height: 66,
                          child: TextField(
                            controller: _controllers[index],
                            focusNode: _focusNodes[index],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: EdgeInsets.zero,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) => _onOtpChanged(index, value),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 26),
                    _resendLeftSec > 0
                        ? Text(
                            'Resend code in ${_formatCountdown(_resendLeftSec)}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                          )
                        : TextButton(
                            onPressed: _resendOtp,
                            child: const Text(
                              'Resend code',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                    const SizedBox(height: 26),
                    Obx(
                      () => PrimaryActionButton(
                        text: 'Verify & Continue',
                        icon: Icons.arrow_forward,
                        busy: auth.loading.value,
                        onPressed: auth.loading.value || _otp.length != 6
                            ? null
                            : () => auth.verifyOtp(_otp),
                      ),
                    ),
                    const SizedBox(height: 80),
                    const Text(
                      'N WALLET SECURE VERIFICATION',
                      style: TextStyle(
                        letterSpacing: 3,
                        color: Color(0xFFCAD3DF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 140,
              height: 8,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFD6DEE8),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        Get.offAllNamed('/face-unlock');
      } else {
        Get.offAllNamed('/home');
      }
    } else {
      Get.offAllNamed('/enroll');
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

class FaceUnlockPage extends StatefulWidget {
  const FaceUnlockPage({super.key});

  @override
  State<FaceUnlockPage> createState() => _FaceUnlockPageState();
}

class _FaceUnlockPageState extends State<FaceUnlockPage> {
  final auth = Get.find<StudentAuthController>();

  bool verifying = false;

  Future<void> _captureAndVerify() async {
    final result = await Get.toNamed('/identity-capture') as String?;
    if (result == null || result.isEmpty) return;

    setState(() => verifying = true);
    try {
      final frame = MultipartFile.fromFileSync(
        result,
        filename: result.split('/').last,
      );

      await auth.api.verifyStudentIdentity([frame]);
      auth.markFaceUnlockVerified();
      Get.offAllNamed('/home');
      Get.snackbar(
        'Identity verified',
        'Face recognition successful.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on DioException catch (error) {
      Get.snackbar(
        'Verification failed',
        _extractDioError(error),
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
                'Welcome back${auth.email.value == null ? '' : ', ${_nameFromEmail(auth.email.value)}'}. '
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
    final result = await Get.toNamed('/enrollment-capture');
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
        Get.offAllNamed('/home');
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
        Get.snackbar('Enrollment failed', _extractDioError(error));
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
                      _initialsFromEmail(auth.email.value),
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
                'Hello, ${_nameFromEmail(auth.email.value)}',
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
      final start = _buildSessionTime(session.sessionDate, session.startTime);
      final end = _buildSessionTime(session.sessionDate, session.endTime);
      if (start == null || end == null) continue;

      final openTime = start.subtract(
        Duration(minutes: session.attendanceOpenMinutesBefore),
      );
      final closeTime = end.add(
        Duration(minutes: session.attendanceCloseMinutesAfter),
      );

      if (now.isAfter(openTime) && now.isBefore(closeTime)) {
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
            _displayLecturer(session.lecturerEmail),
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
                '${_formatTo12Hour(session.startTime)} - ${_formatTo12Hour(session.endTime)}',
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
                  _displayHall(session.hallName, session.hallId),
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
            onPressed: () => Get.toNamed('/session', arguments: session),
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
      onTap: () => Get.toNamed('/session', arguments: session),
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
                    _formatAmPmShort(session.startTime),
                    style: const TextStyle(
                      color: Color(0xFF91A2B8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _formatHourMinute(session.startTime),
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
                    '${session.moduleCode} - ${_displayLecturer(session.lecturerEmail)}',
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

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key});

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  final auth = Get.find<StudentAuthController>();
  final scanner = Get.find<BeaconScanController>();

  late final StudentSessionDto session;
  Map<String, dynamic>? expectedBeacon;
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
      final beacon = detail['expectedBeacon'];
      if (beacon is Map) {
        expectedBeacon = Map<String, dynamic>.from(beacon);
      }

      if (expectedBeacon != null) {
        final preview = await scanner.scanEvidence(
          uuid: (expectedBeacon!['uuid'] as String?) ?? '',
          major: (expectedBeacon!['major'] as num?)?.toInt() ?? 0,
          minor: (expectedBeacon!['minor'] as num?)?.toInt() ?? 0,
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
    final closeLabel = _attendanceWindowLabel(session);

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
                      '${session.moduleCode} • ${_displayLecturer(session.lecturerEmail)}',
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
                                closeLabel,
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
                            value: _formatDateReadable(session.sessionDate),
                          ),
                          const Divider(height: 1, color: AppColors.border),
                          _detailTile(
                            icon: Icons.schedule,
                            title: 'Time',
                            value:
                                '${_formatTo12Hour(session.startTime)} - ${_formatTo12Hour(session.endTime)}',
                          ),
                          const Divider(height: 1, color: AppColors.border),
                          _detailTile(
                            icon: Icons.location_on,
                            title: 'Location',
                            value: _displayHall(
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
                        Get.toNamed('/attendance', arguments: session),
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
    final hasMapping = expectedBeacon != null;
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
                  _previewBeaconTitle(hasMapping: hasMapping, status: status),
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
                  _previewBeaconMessage(
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

class AttendanceFlowPage extends StatefulWidget {
  const AttendanceFlowPage({super.key});

  @override
  State<AttendanceFlowPage> createState() => _AttendanceFlowPageState();
}

class _AttendanceFlowPageState extends State<AttendanceFlowPage> {
  final auth = Get.find<StudentAuthController>();
  final beaconScanner = Get.find<BeaconScanController>();

  late final StudentSessionDto session;
  Map<String, dynamic>? expectedBeacon;

  BeaconScanResult? beaconResult;
  bool loadingDetail = true;
  bool submitting = false;
  int elapsedScanSec = 0;
  Timer? scanTimer;

  static const int beaconStabilityTargetSec = kBeaconUiStabilitySeconds;
  static const int beaconPingTarget = kBeaconUiMinPingCount;

  @override
  void initState() {
    super.initState();
    session = Get.arguments as StudentSessionDto;
    _prepare();
  }

  @override
  void dispose() {
    scanTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      loadingDetail = true;
      beaconResult = null;
    });

    try {
      final detail = await auth.api.studentSession(session.id);
      final beacon = detail['expectedBeacon'];
      if (beacon is Map) {
        expectedBeacon = Map<String, dynamic>.from(beacon);
      }

      if (expectedBeacon == null) {
        Get.snackbar('Beacon', 'No beacon mapped for this hall.');
      } else {
        await _scanBeacon();
      }
    } on DioException catch (error) {
      Get.snackbar(
        'Session load failed',
        error.message ?? 'Unable to load session detail.',
      );
    } finally {
      if (mounted) {
        setState(() => loadingDetail = false);
      }
    }
  }

  Future<void> _scanBeacon() async {
    if (expectedBeacon == null) return;

    scanTimer?.cancel();
    setState(() {
      elapsedScanSec = 0;
      beaconResult = null;
    });

    scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (elapsedScanSec >= 10) {
        timer.cancel();
        return;
      }
      setState(() {
        elapsedScanSec += 1;
      });
    });

    final scanned = await beaconScanner.scanEvidence(
      uuid: (expectedBeacon!['uuid'] as String?) ?? '',
      major: (expectedBeacon!['major'] as num?)?.toInt() ?? 0,
      minor: (expectedBeacon!['minor'] as num?)?.toInt() ?? 0,
      scanSeconds: 10,
    );

    scanTimer?.cancel();
    if (!mounted) return;

    setState(() {
      beaconResult = scanned;
      elapsedScanSec = 10;
    });
  }

  Future<void> _captureAndSubmit() async {
    if (beaconResult == null || !beaconResult!.matched) {
      Get.snackbar(
        'Attendance',
        'A verified hall beacon is required before you continue.',
      );
      return;
    }

    final result = await Get.toNamed('/capture') as String?;
    if (result == null || result.isEmpty) return;

    await _submitAttendance(result);
  }

  Future<void> _submitAttendance(String framePath) async {
    setState(() => submitting = true);
    try {
      final frame = MultipartFile.fromFileSync(
        framePath,
        filename: framePath.split('/').last,
      );
      final payload = AttendanceSubmitDto(
        sessionId: session.id,
        beaconEvidence: beaconResult!.evidence,
      );

      final response = await auth.api.submitAttendance(
        attendance: payload,
        frames: [frame],
      );

      final status = response['status'] as String? ?? 'REJECTED';
      final faceScore = (response['faceScore'] as num?)?.toDouble() ?? 0;
      final reasonCode = response['reasonCode'] as String?;

      Get.offNamed(
        '/attendance-result',
        arguments: {
          'session': session,
          'status': status,
          'faceScore': faceScore,
          'reasonCode': reasonCode,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } on DioException catch (error) {
      Get.snackbar('Submit failed', _extractDioError(error));
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final scanning = beaconScanner.scanning.value;
          final result = beaconResult;
          final hasMatchedBeacon = result?.matched ?? false;
          final hasDetectedSignal = result?.detected ?? false;
          final canConfirm = !scanning && hasMatchedBeacon && !submitting;
          final rssi = result?.evidence.avgRssi ?? -999;
          final stability =
              result?.evidence.durationSec ??
              math.min(elapsedScanSec, beaconStabilityTargetSec);
          final pingChecks = math.min(
            result?.evidence.pingCount ?? beaconScanner.pingCount.value,
            beaconPingTarget,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: Get.back,
                      icon: const Icon(Icons.arrow_back_ios_new),
                    ),
                    const Expanded(
                      child: Text(
                        'Proximity Check',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      onPressed: scanning || loadingDetail ? null : _scanBeacon,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      _radarStatus(scanning),
                      const SizedBox(height: 24),
                      Text(
                        _attendanceBeaconTitle(
                          scanning: scanning,
                          result: result,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF798380),
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${_displayHall(session.hallName, session.hallId)} • ${session.moduleName}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 20,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      _signalBars(rssi),
                      const SizedBox(height: 8),
                      Text(
                        hasDetectedSignal
                            ? '${rssi.toStringAsFixed(0)} dBm  ${_beaconStrengthLabel(rssi).toUpperCase()}'
                            : 'Waiting for hall beacon signal',
                        style: TextStyle(
                          color: hasMatchedBeacon
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _attendanceBeaconMessage(
                          scanning: scanning,
                          result: result,
                        ),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Beacon Checks',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 17,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Need 5 successful pings',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$pingChecks/$beaconPingTarget',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 26,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${math.min(stability, beaconStabilityTargetSec)}/${beaconStabilityTargetSec}s stable',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _attendanceBeaconBadgeBackground(
                                      scanning: scanning,
                                      result: result,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _attendanceBeaconBadgeLabel(
                                      scanning: scanning,
                                      result: result,
                                    ),
                                    style: TextStyle(
                                      color: _attendanceBeaconBadgeForeground(
                                        scanning: scanning,
                                        result: result,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      PrimaryActionButton(
                        text: 'Confirm Attendance',
                        busy: submitting,
                        disabledColor: const Color(0xFFB8C5D6),
                        onPressed: canConfirm ? _captureAndSubmit : null,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _attendanceBeaconFooter(
                          scanning: scanning,
                          result: result,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF90A0B8),
                          fontSize: 17,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (loadingDetail || scanning)
                        const Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _radarStatus(bool scanning) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEAF0ED),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: scanning ? 120 : 110,
            height: scanning ? 120 : 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFD5DFDA),
              border: Border.all(color: Colors.white, width: 8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.sensors,
              size: 44,
              color: scanning ? AppColors.primary : const Color(0xFF6A788F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _signalBars(double rssi) {
    final bars = _rssiBars(rssi);
    return SizedBox(
      height: 90,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(bars.length, (index) {
          final active = bars[index] > 0;
          return Container(
            width: 16,
            height: 26 + (bars[index] * 58),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : const Color(0xFFD3DBE6),
              borderRadius: BorderRadius.circular(10),
            ),
          );
        }),
      ),
    );
  }
}

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
                          : _attendanceRejectMessage(reasonCode),
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
                                : _displayHall(
                                    session.hallName,
                                    session.hallId,
                                  ),
                          ),
                          _resultDetail(
                            icon: Icons.schedule,
                            label: 'TIMESTAMP',
                            value: _formatDateTimeFromIso(timestamp),
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
                onPressed: () => Get.offAllNamed('/home'),
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
          final key = _monthGroupLabel(row['createdAt'] as String?);
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
        : _displayHall(session.hallName, session.hallId);
    final createdAt = _formatDateTimeShort(row['createdAt'] as String?);

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

class StudentSettingsPage extends StatefulWidget {
  const StudentSettingsPage({super.key});

  @override
  State<StudentSettingsPage> createState() => _StudentSettingsPageState();
}

class _StudentSettingsPageState extends State<StudentSettingsPage> {
  final auth = Get.find<StudentAuthController>();

  bool notificationsEnabled = true;
  bool faceIdEnabled = true;

  @override
  Widget build(BuildContext context) {
    final name = _nameFromEmail(auth.email.value);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCD0D2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFD9EEE3),
                          width: 5,
                        ),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 6,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(
                          Icons.verified_user,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EEF5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.badge,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'ID: 10953215',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'GENERAL',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _settingsSwitchRow(
                  icon: Icons.notifications,
                  iconColor: AppColors.success,
                  title: 'Notifications',
                  value: notificationsEnabled,
                  onChanged: (value) =>
                      setState(() => notificationsEnabled = value),
                ),
                const Divider(height: 1, color: AppColors.border),
                _settingsSwitchRow(
                  icon: Icons.face,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Face ID Login',
                  value: faceIdEnabled,
                  onChanged: (value) => setState(() => faceIdEnabled = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'LEGAL',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _settingsNavRow(
                  icon: Icons.shield,
                  title: 'Privacy & Consent',
                  onTap: () => Get.toNamed('/privacy'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: auth.logout,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFFCEBEC),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout, color: AppColors.danger),
                  SizedBox(width: 10),
                  Text(
                    'Log Out',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Log out of all devices',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
            ),
          ),
          const SizedBox(height: 30),
          const Center(
            child: Text(
              'N Wallet v1.0.4',
              style: TextStyle(color: Color(0xFFA4B1C2), fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSwitchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _settingsNavRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF0F8),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF5C6F8C)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF91A3BA)),
          ],
        ),
      ),
    );
  }
}

class PrivacyConsentPage extends StatefulWidget {
  const PrivacyConsentPage({super.key});

  @override
  State<PrivacyConsentPage> createState() => _PrivacyConsentPageState();
}

class _PrivacyConsentPageState extends State<PrivacyConsentPage> {
  bool consentChecked = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: Get.back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Privacy & Consent',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF004D35), Color(0xFF11804A)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 94),
                        const Row(
                          children: [
                            Icon(Icons.warning, color: Color(0xFFFFE082)),
                            SizedBox(width: 8),
                            Text(
                              'ACTION REQUIRED',
                              style: TextStyle(
                                color: Color(0xFFFFE082),
                                letterSpacing: 1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Pending Review',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please review the data collection policies below to verify your identity for university attendance.',
                          style: TextStyle(
                            color: Color(0xFFE2F4EA),
                            fontSize: 22,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'DATA COLLECTION POLICIES',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _policyExpansion(
                    icon: Icons.face,
                    title: 'Biometric Data (Face ID)',
                    body:
                        'Your facial data is cryptographically hashed and used solely for attendance verification. Images are processed locally and matched against the university\'s secure database. No raw facial data is shared with third parties.',
                    initiallyExpanded: true,
                  ),
                  _policyExpansion(
                    icon: Icons.location_on,
                    title: 'Location Verification (iBeacon)',
                    body:
                        'Bluetooth Low Energy iBeacon signals are used only at the attendance check moment to verify hall presence. Continuous location tracking is not performed.',
                  ),
                  _policyExpansion(
                    icon: Icons.description,
                    title: 'Audit Logs & Data Retention',
                    body:
                        'Attendance and admin access logs are retained for auditing and academic compliance. Access is restricted to authorized staff.',
                  ),
                  const SizedBox(height: 20),
                  const Center(
                    child: Text(
                      'ACCOUNT MANAGEMENT',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _outlineAction(
                    icon: Icons.refresh,
                    text: 'Request Re-enrollment',
                    color: AppColors.textSecondary,
                    onTap: () => Get.snackbar(
                      'Submitted',
                      'Your re-enrollment request has been logged.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _outlineAction(
                    icon: Icons.delete,
                    text: 'Request Account Deletion',
                    color: AppColors.danger,
                    onTap: () => Get.snackbar(
                      'Submitted',
                      'Your account deletion request has been logged.',
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: consentChecked,
                        onChanged: (value) =>
                            setState(() => consentChecked = value ?? false),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'I have read and agree to the data collection policies regarding my biometric and location data.',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 19,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PrimaryActionButton(
                    text: 'Confirm & Continue',
                    icon: Icons.arrow_forward,
                    onPressed: consentChecked
                        ? () {
                            Get.back();
                            Get.snackbar(
                              'Consent saved',
                              'Your privacy consent is confirmed.',
                            );
                          }
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

  Widget _policyExpansion({
    required IconData icon,
    required String title,
    required String body,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE5ECE8),
              borderRadius: BorderRadius.circular(19),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 19,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Text(
              body,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 17,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlineAction({
    required IconData icon,
    required String text,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const Map<DeviceOrientation, int> _kCameraOrientations =
    <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

enum _EnrollmentCaptureStage { front, firstSide, oppositeSide }

const double _kFrontYawMax = 10;
const double _kSideYawMin = 12;

class EnrollmentAutoCapturePage extends StatefulWidget {
  const EnrollmentAutoCapturePage({super.key});

  @override
  State<EnrollmentAutoCapturePage> createState() =>
      _EnrollmentAutoCapturePageState();
}

class _EnrollmentAutoCapturePageState extends State<EnrollmentAutoCapturePage> {
  late final FaceDetector faceDetector;

  CameraController? controller;
  final List<String> capturedPaths = <String>[];

  bool initializing = true;
  bool streaming = false;
  bool processingFrame = false;
  bool capturing = false;
  String? error;
  String guidanceTitle = 'Look straight ahead';
  String guidanceMessage = 'Hold still while we detect your face.';

  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _stableMatchCount = 0;
  int? _firstSideSign;

  _EnrollmentCaptureStage get _currentStage {
    switch (capturedPaths.length) {
      case 0:
        return _EnrollmentCaptureStage.front;
      case 1:
        return _EnrollmentCaptureStage.firstSide;
      default:
        return _EnrollmentCaptureStage.oppositeSide;
    }
  }

  @override
  void initState() {
    super.initState();
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableTracking: true,
        minFaceSize: 0.15,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameraLoadError = await _ensureCamerasLoaded();
    if (cameraLoadError != null) {
      setState(() {
        initializing = false;
        error = cameraLoadError;
      });
      return;
    }

    final selected = gCameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => gCameras.first,
    );

    final cameraController = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.nv21,
    );

    try {
      await cameraController.initialize();
      if (!cameraController.supportsImageStreaming()) {
        throw CameraException(
          'image-streaming-unavailable',
          'Live face detection is not supported on this device.',
        );
      }

      if (!mounted) {
        await cameraController.dispose();
        return;
      }

      setState(() {
        controller = cameraController;
        initializing = false;
        error = null;
      });
      _updateGuidanceForCurrentStage();
      await _startImageStream();
    } catch (e) {
      await cameraController.dispose();
      if (!mounted) return;
      setState(() {
        initializing = false;
        error = 'Unable to start guided capture: $e';
      });
    }
  }

  Future<void> _startImageStream() async {
    final cameraController = controller;
    if (cameraController == null || streaming || !mounted) return;
    await cameraController.startImageStream(_processCameraImage);
    streaming = true;
  }

  Future<void> _stopImageStream() async {
    final cameraController = controller;
    if (cameraController == null || !streaming) return;
    try {
      await cameraController.stopImageStream();
    } catch (_) {
      // Ignore stop failures during page transitions or dispose.
    } finally {
      streaming = false;
    }
  }

  Future<void> _restartScan() async {
    if (capturing) return;
    setState(() {
      capturedPaths.clear();
      _firstSideSign = null;
      _stableMatchCount = 0;
    });
    _updateGuidanceForCurrentStage();
  }

  Future<void> _retryCamera() async {
    final oldController = controller;
    controller = null;
    if (oldController != null) {
      await _stopImageStream();
      await oldController.dispose();
    }
    if (!mounted) return;
    setState(() {
      initializing = true;
      error = null;
      capturedPaths.clear();
      _firstSideSign = null;
      _stableMatchCount = 0;
    });
    await _initCamera();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted || capturing || processingFrame || error != null) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessedAt) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastProcessedAt = now;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;

    processingFrame = true;
    try {
      final faces = await faceDetector.processImage(inputImage);
      if (!mounted || capturing) return;
      _handleFaces(faces, inputImage.metadata!.size);
    } catch (_) {
      // Keep the preview alive if one frame fails to process.
    } finally {
      processingFrame = false;
    }
  }

  void _handleFaces(List<Face> faces, Size imageSize) {
    if (faces.isEmpty) {
      _stableMatchCount = 0;
      _setGuidance(
        'Find your face',
        'Place your full face inside the circle so the scan can begin.',
      );
      return;
    }

    if (faces.length > 1) {
      _stableMatchCount = 0;
      _setGuidance(
        'One person only',
        'Make sure only one face is visible in the camera view.',
      );
      return;
    }

    final face = faces.first;
    if (!_isFaceAligned(face, imageSize)) {
      _stableMatchCount = 0;
      return;
    }

    if (!_matchesCurrentStage(face)) {
      _stableMatchCount = 0;
      _updateGuidanceForCurrentStage();
      return;
    }

    _stableMatchCount += 1;
    if (_stableMatchCount < 2) {
      _setGuidance(
        'Hold still',
        'Stay steady for a moment while we capture this angle.',
      );
      return;
    }

    unawaited(_captureCurrentStage(face));
  }

  bool _isFaceAligned(Face face, Size imageSize) {
    final bounds = face.boundingBox;
    final widthRatio = bounds.width / imageSize.width;
    final heightRatio = bounds.height / imageSize.height;
    final centerX = bounds.center.dx / imageSize.width;
    final centerY = bounds.center.dy / imageSize.height;
    final isSideStage = _currentStage != _EnrollmentCaptureStage.front;
    final minWidthRatio = isSideStage ? 0.13 : 0.18;
    final minHeightRatio = isSideStage ? 0.15 : 0.18;
    final minCenterX = isSideStage ? 0.20 : 0.28;
    final maxCenterX = isSideStage ? 0.80 : 0.72;

    if (widthRatio < minWidthRatio || heightRatio < minHeightRatio) {
      _setGuidance(
        'Move closer',
        'Bring your face a little closer until it fills more of the circle.',
      );
      return false;
    }

    if (widthRatio > 0.68 || heightRatio > 0.82) {
      _setGuidance(
        'Move back slightly',
        'Keep your full face visible inside the guide.',
      );
      return false;
    }

    if (centerX < minCenterX ||
        centerX > maxCenterX ||
        centerY < 0.16 ||
        centerY > 0.80) {
      _setGuidance(
        'Center your face',
        isSideStage
            ? 'Keep your face inside the circle while you turn.'
            : 'Keep your face inside the circle and look directly at the camera.',
      );
      return false;
    }

    return true;
  }

  bool _matchesCurrentStage(Face face) {
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX ?? 0;
    final roll = face.headEulerAngleZ ?? 0;
    final isSideStage = _currentStage != _EnrollmentCaptureStage.front;

    if (yaw == null ||
        pitch.abs() > (isSideStage ? 24 : 18) ||
        roll.abs() > (isSideStage ? 20 : 15)) {
      return false;
    }

    switch (_currentStage) {
      case _EnrollmentCaptureStage.front:
        return yaw.abs() <= _kFrontYawMax;
      case _EnrollmentCaptureStage.firstSide:
        return yaw.abs() >= _kSideYawMin;
      case _EnrollmentCaptureStage.oppositeSide:
        final sign = _sideSignForYaw(yaw);
        return sign != null &&
            _firstSideSign != null &&
            sign != _firstSideSign &&
            yaw.abs() >= _kSideYawMin;
    }
  }

  int? _sideSignForYaw(double? yaw) {
    if (yaw == null || yaw.abs() < _kSideYawMin) return null;
    return yaw > 0 ? 1 : -1;
  }

  Future<void> _captureCurrentStage(Face face) async {
    final cameraController = controller;
    if (cameraController == null || capturing) return;

    final stageBeforeCapture = _currentStage;
    final sideSign = _sideSignForYaw(face.headEulerAngleY);

    setState(() {
      capturing = true;
      _stableMatchCount = 0;
    });
    _setGuidance(
      'Capturing ${capturedPaths.length + 1} of 3',
      'Hold still while the photo is saved.',
    );

    try {
      await _stopImageStream();
      final photo = await cameraController.takePicture();
      if (!mounted) return;

      setState(() {
        capturedPaths.add(photo.path);
        if (stageBeforeCapture == _EnrollmentCaptureStage.firstSide) {
          _firstSideSign = sideSign;
        }
      });

      if (capturedPaths.length == 3) {
        Get.back(result: List<String>.from(capturedPaths));
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;

      _updateGuidanceForCurrentStage();
      await _startImageStream();
      if (!mounted) return;
      setState(() {
        capturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        capturing = false;
        error = 'Automatic capture failed: $e';
      });
    }
  }

  void _updateGuidanceForCurrentStage() {
    switch (_currentStage) {
      case _EnrollmentCaptureStage.front:
        _setGuidance(
          'Look straight ahead',
          'Face the camera directly. We will take the first photo automatically.',
        );
        break;
      case _EnrollmentCaptureStage.firstSide:
        _setGuidance(
          'Turn to one side',
          'Slowly turn your head to either side and keep your face inside the circle.',
        );
        break;
      case _EnrollmentCaptureStage.oppositeSide:
        _setGuidance(
          'Turn to the other side',
          'Move back through the center, then turn the other way for the final photo.',
        );
        break;
    }
  }

  void _setGuidance(String title, String message) {
    if (!mounted) return;
    if (guidanceTitle == title && guidanceMessage == message) return;
    setState(() {
      guidanceTitle = title;
      guidanceMessage = message;
    });
  }

  // ML Kit expects platform-specific image metadata from the live camera stream.
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final cameraController = controller;
    if (cameraController == null) return null;

    final rotation = _inputRotationFromCamera(cameraController);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _inputRotationFromCamera(
    CameraController cameraController,
  ) {
    final sensorOrientation = cameraController.description.sensorOrientation;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (!Platform.isAndroid) return null;

    var compensation =
        _kCameraOrientations[cameraController.value.deviceOrientation];
    if (compensation == null) return null;

    if (cameraController.description.lensDirection ==
        CameraLensDirection.front) {
      compensation = (sensorOrientation + compensation) % 360;
    } else {
      compensation = (sensorOrientation - compensation + 360) % 360;
    }

    return InputImageRotationValue.fromRawValue(compensation);
  }

  @override
  void dispose() {
    final activeController = controller;
    if (activeController != null && activeController.value.isStreamingImages) {
      unawaited(activeController.stopImageStream().catchError((_) {}));
    }
    activeController?.dispose();
    unawaited(faceDetector.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Guided Face Scan')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                PrimaryActionButton(
                  text: 'Retry Camera',
                  onPressed: _retryCamera,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: Get.back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Guided Face Scan',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 42),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(
                'Keep your face inside the circle. We will capture three photos automatically as you change angles.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _PortraitCameraViewport(
                  controller: controller!,
                  overlayOpacity: 0.24,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Container(
                          width: 292,
                          height: 292,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: capturing
                                  ? AppColors.success
                                  : Colors.white,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 18,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Captured ${capturedPaths.length} of 3',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(3, (index) {
                      final done = index < capturedPaths.length;
                      final active = index == capturedPaths.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: done
                              ? AppColors.primary.withValues(alpha: 0.16)
                              : active
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: done || active
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Center(
                          child: done
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: AppColors.primary,
                                )
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: active
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            capturing
                                ? Icons.photo_camera
                                : Icons.face_retouching_natural,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                guidanceTitle,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                guidanceMessage,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Good lighting and a single face in the frame will give the best enrollment result.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: capturing ? null : _restartScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Restart Scan'),
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

class IdentityAutoCapturePage extends StatefulWidget {
  const IdentityAutoCapturePage({super.key});

  @override
  State<IdentityAutoCapturePage> createState() =>
      _IdentityAutoCapturePageState();
}

class _IdentityAutoCapturePageState extends State<IdentityAutoCapturePage> {
  late final FaceDetector faceDetector;

  CameraController? controller;
  bool initializing = true;
  bool streaming = false;
  bool processingFrame = false;
  bool capturing = false;
  String? error;
  String guidanceTitle = 'Look straight ahead';
  String guidanceMessage =
      'Keep your face inside the circle. The photo will be captured automatically.';

  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _stableMatchCount = 0;

  @override
  void initState() {
    super.initState();
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableTracking: true,
        minFaceSize: 0.15,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameraLoadError = await _ensureCamerasLoaded();
    if (cameraLoadError != null) {
      setState(() {
        initializing = false;
        error = cameraLoadError;
      });
      return;
    }

    final selected = gCameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => gCameras.first,
    );

    final cameraController = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.nv21,
    );

    try {
      await cameraController.initialize();
      if (!cameraController.supportsImageStreaming()) {
        throw CameraException(
          'image-streaming-unavailable',
          'Live face detection is not supported on this device.',
        );
      }

      if (!mounted) {
        await cameraController.dispose();
        return;
      }

      setState(() {
        controller = cameraController;
        initializing = false;
        error = null;
      });
      await _startImageStream();
    } catch (e) {
      await cameraController.dispose();
      if (!mounted) return;
      setState(() {
        initializing = false;
        error = 'Unable to start auto capture: $e';
      });
    }
  }

  Future<void> _startImageStream() async {
    final cameraController = controller;
    if (cameraController == null || streaming || !mounted) return;
    await cameraController.startImageStream(_processCameraImage);
    streaming = true;
  }

  Future<void> _stopImageStream() async {
    final cameraController = controller;
    if (cameraController == null || !streaming) return;
    try {
      await cameraController.stopImageStream();
    } catch (_) {
      // Ignore stop failures during page transitions or dispose.
    } finally {
      streaming = false;
    }
  }

  Future<void> _retryCamera() async {
    final oldController = controller;
    controller = null;
    if (oldController != null) {
      await _stopImageStream();
      await oldController.dispose();
    }
    if (!mounted) return;
    setState(() {
      initializing = true;
      error = null;
      _stableMatchCount = 0;
      guidanceTitle = 'Look straight ahead';
      guidanceMessage =
          'Keep your face inside the circle. The photo will be captured automatically.';
    });
    await _initCamera();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted || capturing || processingFrame || error != null) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessedAt) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastProcessedAt = now;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;

    processingFrame = true;
    try {
      final faces = await faceDetector.processImage(inputImage);
      if (!mounted || capturing) return;
      _handleFaces(faces, inputImage.metadata!.size);
    } catch (_) {
      // Keep the preview alive if one frame fails to process.
    } finally {
      processingFrame = false;
    }
  }

  void _handleFaces(List<Face> faces, Size imageSize) {
    if (faces.isEmpty) {
      _stableMatchCount = 0;
      _setGuidance(
        'Find your face',
        'Place your full face inside the circle so we can verify you.',
      );
      return;
    }

    if (faces.length > 1) {
      _stableMatchCount = 0;
      _setGuidance(
        'One person only',
        'Make sure only your face is visible in the frame.',
      );
      return;
    }

    final face = faces.first;
    if (!_isFaceAligned(face, imageSize)) {
      _stableMatchCount = 0;
      return;
    }

    if (!_isFaceFrontal(face)) {
      _stableMatchCount = 0;
      _setGuidance(
        'Face the camera',
        'Look straight ahead and keep your head level for a quick capture.',
      );
      return;
    }

    _stableMatchCount += 1;
    if (_stableMatchCount < 2) {
      _setGuidance(
        'Hold still',
        'Stay steady for a moment while we capture your photo.',
      );
      return;
    }

    unawaited(_capturePhoto());
  }

  bool _isFaceAligned(Face face, Size imageSize) {
    final bounds = face.boundingBox;
    final widthRatio = bounds.width / imageSize.width;
    final heightRatio = bounds.height / imageSize.height;
    final centerX = bounds.center.dx / imageSize.width;
    final centerY = bounds.center.dy / imageSize.height;

    if (widthRatio < 0.15 || heightRatio < 0.17) {
      _setGuidance(
        'Move closer',
        'Bring your face a little closer until it fills more of the guide.',
      );
      return false;
    }

    if (widthRatio > 0.74 || heightRatio > 0.84) {
      _setGuidance(
        'Move back slightly',
        'Keep your full face visible inside the circle.',
      );
      return false;
    }

    if (centerX < 0.24 || centerX > 0.76 || centerY < 0.16 || centerY > 0.80) {
      _setGuidance(
        'Center your face',
        'Keep your face inside the circle and look directly at the camera.',
      );
      return false;
    }

    return true;
  }

  bool _isFaceFrontal(Face face) {
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX ?? 0;
    final roll = face.headEulerAngleZ ?? 0;

    if (yaw == null) return false;
    return yaw.abs() <= _kFrontYawMax && pitch.abs() <= 18 && roll.abs() <= 15;
  }

  Future<void> _capturePhoto() async {
    final cameraController = controller;
    if (cameraController == null || capturing) return;

    setState(() {
      capturing = true;
      _stableMatchCount = 0;
    });
    _setGuidance('Capturing photo', 'Hold still while we save the image.');

    try {
      await _stopImageStream();
      final photo = await cameraController.takePicture();
      if (!mounted) return;
      Get.back(result: photo.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        capturing = false;
        error = 'Automatic capture failed: $e';
      });
    }
  }

  void _setGuidance(String title, String message) {
    if (!mounted) return;
    if (guidanceTitle == title && guidanceMessage == message) return;
    setState(() {
      guidanceTitle = title;
      guidanceMessage = message;
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final cameraController = controller;
    if (cameraController == null) return null;

    final rotation = _inputRotationFromCamera(cameraController);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _inputRotationFromCamera(
    CameraController cameraController,
  ) {
    final sensorOrientation = cameraController.description.sensorOrientation;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (!Platform.isAndroid) return null;

    var compensation =
        _kCameraOrientations[cameraController.value.deviceOrientation];
    if (compensation == null) return null;

    if (cameraController.description.lensDirection ==
        CameraLensDirection.front) {
      compensation = (sensorOrientation + compensation) % 360;
    } else {
      compensation = (sensorOrientation - compensation + 360) % 360;
    }

    return InputImageRotationValue.fromRawValue(compensation);
  }

  @override
  void dispose() {
    final activeController = controller;
    if (activeController != null && activeController.value.isStreamingImages) {
      unawaited(activeController.stopImageStream().catchError((_) {}));
    }
    activeController?.dispose();
    unawaited(faceDetector.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verify Your Identity')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                PrimaryActionButton(
                  text: 'Retry Camera',
                  onPressed: _retryCamera,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: Get.back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Verify Your Identity',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 42),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(
                'Look straight ahead. Your face photo will be captured automatically.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _PortraitCameraViewport(
                  controller: controller!,
                  overlayOpacity: 0.22,
                  child: Center(
                    child: Container(
                      width: 308,
                      height: 308,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: capturing ? AppColors.success : Colors.white,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            capturing
                                ? Icons.photo_camera
                                : Icons.face_retouching_natural,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                guidanceTitle,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                guidanceMessage,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Use good lighting and keep only your face in the frame.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
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

class _PortraitCameraViewport extends StatelessWidget {
  const _PortraitCameraViewport({
    required this.controller,
    required this.child,
    this.overlayOpacity = 0.2,
  });

  final CameraController controller;
  final Widget child;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const frameAspectRatio = 0.74;
        final frameWidth = math.min(
          constraints.maxWidth,
          constraints.maxHeight * frameAspectRatio,
        );
        final frameHeight = frameWidth / frameAspectRatio;

        return Center(
          child: SizedBox(
            width: frameWidth,
            height: frameHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CameraPreviewCover(controller: controller),
                  Container(
                    color: Colors.black.withValues(alpha: overlayOpacity),
                  ),
                  child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CameraPreviewCover extends StatelessWidget {
  const _CameraPreviewCover({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class CaptureFacePage extends StatefulWidget {
  const CaptureFacePage({super.key});

  @override
  State<CaptureFacePage> createState() => _CaptureFacePageState();
}

class _CaptureFacePageState extends State<CaptureFacePage> {
  CameraController? controller;
  bool initializing = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameraLoadError = await _ensureCamerasLoaded();
    if (cameraLoadError != null) {
      setState(() {
        initializing = false;
        error = cameraLoadError;
      });
      return;
    }

    final selected = gCameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => gCameras.first,
    );

    final cameraController = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await cameraController.initialize();
      setState(() {
        controller = cameraController;
        initializing = false;
      });
    } catch (e) {
      setState(() {
        initializing = false;
        error = 'Unable to initialize camera: $e';
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Capture Face')),
        body: Center(child: Text(error!)),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: Get.back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Capture Face',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _PortraitCameraViewport(
                  controller: controller!,
                  overlayOpacity: 0.2,
                  child: Center(
                    child: Container(
                      width: 304,
                      height: 304,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              child: SizedBox(
                width: 94,
                height: 94,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 94,
                      height: 94,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          width: 5,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        final file = await controller!.takePicture();
                        if (!mounted) return;
                        Get.back(result: file.path);
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.text,
    this.icon,
    required this.onPressed,
    this.busy = false,
    this.disabledColor,
  });

  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Color? disabledColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: disabledColor ?? const Color(0xFFB7C2D1),
          foregroundColor: Colors.white,
          elevation: enabled ? 7 : 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.2),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 22),
                  ],
                ],
              ),
      ),
    );
  }
}

DateTime? _buildSessionTime(String date, String time) {
  final dateParts = date.split('-');
  final timeParts = time.split(':');
  if (dateParts.length != 3 || timeParts.length < 2) return null;

  final year = int.tryParse(dateParts[0]);
  final month = int.tryParse(dateParts[1]);
  final day = int.tryParse(dateParts[2]);
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);

  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null) {
    return null;
  }

  return DateTime(year, month, day, hour, minute);
}

String _formatTo12Hour(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;

  final hour24 = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour24 == null || minute == null) return hhmm;

  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = ((hour24 + 11) % 12) + 1;
  return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $suffix';
}

String _formatHourMinute(String hhmm) {
  final parts = _formatTo12Hour(hhmm).split(' ');
  return parts.first;
}

String _formatAmPmShort(String hhmm) {
  final parts = _formatTo12Hour(hhmm).split(' ');
  return parts.length > 1 ? parts.last : '';
}

String _displayLecturer(String email) {
  if (email.isEmpty) return 'Lecturer';
  final local = email.split('@').first;
  final words = local
      .replaceAll(RegExp(r'[_\.-]+'), ' ')
      .split(' ')
      .where((word) => word.trim().isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .toList();
  return words.isEmpty ? email : words.join(' ');
}

String _displayHall(String hallName, String hallId) {
  final trimmedName = hallName.trim();
  if (trimmedName.isNotEmpty) {
    return trimmedName;
  }

  if (hallId.trim().isEmpty) {
    return 'Lecture Hall';
  }
  return 'Lecture Hall $hallId';
}

String _formatDateReadable(String ymd) {
  final parts = ymd.split('-');
  if (parts.length != 3) return ymd;

  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return ymd;

  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '${months[month - 1]} $day, $year';
}

String _attendanceWindowLabel(StudentSessionDto session) {
  final end = _buildSessionTime(session.sessionDate, session.endTime);
  if (end == null) return 'Open now';

  final close = end.add(Duration(minutes: session.attendanceCloseMinutesAfter));
  final hh = close.hour;
  final mm = close.minute;
  final suffix = hh >= 12 ? 'PM' : 'AM';
  final hour12 = ((hh + 11) % 12) + 1;
  return 'Open until ${hour12.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')} $suffix';
}

String _previewBeaconTitle({
  required bool hasMapping,
  required BeaconScanStatus? status,
}) {
  if (!hasMapping || status == BeaconScanStatus.noMapping) {
    return 'No Beacon Mapping';
  }

  switch (status) {
    case BeaconScanStatus.bluetoothOff:
      return 'Bluetooth Off';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Location Permission Required';
    case BeaconScanStatus.locationServicesOff:
      return 'Location Services Off';
    case BeaconScanStatus.scanFailed:
      return 'Beacon Scan Failed';
    case BeaconScanStatus.notFound:
      return 'Hall Beacon Not Detected';
    case BeaconScanStatus.weak:
    case BeaconScanStatus.unstable:
    case BeaconScanStatus.matched:
      return 'Hall Beacon Detected';
    case BeaconScanStatus.noMapping:
    case null:
      return 'Hall Beacon Mapped';
  }
}

String _previewBeaconMessage({
  required bool hasMapping,
  required BeaconScanResult? result,
}) {
  if (!hasMapping) {
    return 'Admin has not mapped an active beacon for this hall.';
  }

  final status = result?.status;
  switch (status) {
    case BeaconScanStatus.bluetoothOff:
      return 'Turn on Bluetooth to detect the hall beacon.';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Allow location access so the app can range iBeacons.';
    case BeaconScanStatus.locationServicesOff:
      return 'Turn on location services to scan for the hall beacon.';
    case BeaconScanStatus.scanFailed:
      return 'Unable to read the hall beacon right now. Please try again.';
    case BeaconScanStatus.notFound:
      return 'Move closer to the lecture hall beacon and refresh.';
    case BeaconScanStatus.weak:
      return 'Signal strength is ${_beaconStrengthLabel(result!.evidence.avgRssi)}. Move closer for attendance.';
    case BeaconScanStatus.unstable:
      return 'Beacon detected. Hold the device steady for a moment.';
    case BeaconScanStatus.matched:
      return 'Signal Strength: ${_beaconStrengthLabel(result!.evidence.avgRssi)}';
    case BeaconScanStatus.noMapping:
    case null:
      return 'Scanning for the mapped hall beacon.';
  }
}

String _attendanceBeaconTitle({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) return 'Searching for Beacon...';

  switch (result?.status) {
    case BeaconScanStatus.noMapping:
      return 'No Beacon Mapping';
    case BeaconScanStatus.bluetoothOff:
      return 'Bluetooth Off';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Location Permission Needed';
    case BeaconScanStatus.locationServicesOff:
      return 'Location Services Off';
    case BeaconScanStatus.scanFailed:
      return 'Scan Failed';
    case BeaconScanStatus.notFound:
      return 'No Beacon Found';
    case BeaconScanStatus.weak:
      return 'Beacon Signal Too Weak';
    case BeaconScanStatus.unstable:
      return 'Hold Steady Near Beacon';
    case BeaconScanStatus.matched:
      return 'Beacon Verified';
    case null:
      return 'Waiting for Beacon Scan';
  }
}

String _attendanceBeaconMessage({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) {
    return 'Looking for the exact hall beacon using UUID, major and minor.';
  }

  switch (result?.status) {
    case BeaconScanStatus.noMapping:
      return 'No active beacon is mapped to this lecture hall yet.';
    case BeaconScanStatus.bluetoothOff:
      return 'Turn on Bluetooth, then scan again.';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Allow location access for iBeacon proximity checks.';
    case BeaconScanStatus.locationServicesOff:
      return 'Turn on location services, then retry the beacon scan.';
    case BeaconScanStatus.scanFailed:
      return 'The beacon scan failed. Retry once you are near the lecture hall.';
    case BeaconScanStatus.notFound:
      return 'The expected hall beacon was not detected during this scan.';
    case BeaconScanStatus.weak:
      return 'The correct beacon was found, but the signal is too weak right now.';
    case BeaconScanStatus.unstable:
      return 'The correct beacon was found, but we need a few more successful beacon checks.';
    case BeaconScanStatus.matched:
      return 'Hall beacon identity and proximity checks passed.';
    case null:
      return 'Start a scan while standing inside the lecture hall.';
  }
}

String _attendanceBeaconBadgeLabel({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) return 'Scanning';

  switch (result?.status) {
    case BeaconScanStatus.matched:
      return 'Verified';
    case BeaconScanStatus.weak:
      return 'Weak signal';
    case BeaconScanStatus.unstable:
      return 'More checks';
    case BeaconScanStatus.notFound:
      return 'Not found';
    case BeaconScanStatus.bluetoothOff:
      return 'Bluetooth off';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Permission needed';
    case BeaconScanStatus.locationServicesOff:
      return 'Location off';
    case BeaconScanStatus.scanFailed:
      return 'Retry';
    case BeaconScanStatus.noMapping:
      return 'No mapping';
    case null:
      return 'Waiting';
  }
}

Color _attendanceBeaconBadgeBackground({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) {
    return const Color(0xFFE3ECF7);
  }

  switch (result?.status) {
    case BeaconScanStatus.matched:
      return const Color(0xFFD3F7E4);
    case BeaconScanStatus.weak:
    case BeaconScanStatus.unstable:
      return const Color(0xFFFFEDD5);
    case BeaconScanStatus.notFound:
    case BeaconScanStatus.bluetoothOff:
    case BeaconScanStatus.locationPermissionDenied:
    case BeaconScanStatus.locationServicesOff:
    case BeaconScanStatus.scanFailed:
    case BeaconScanStatus.noMapping:
    case null:
      return const Color(0xFFE7EDF5);
  }
}

Color _attendanceBeaconBadgeForeground({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) {
    return const Color(0xFF5E718F);
  }

  switch (result?.status) {
    case BeaconScanStatus.matched:
      return AppColors.success;
    case BeaconScanStatus.weak:
    case BeaconScanStatus.unstable:
      return AppColors.warning;
    case BeaconScanStatus.notFound:
    case BeaconScanStatus.bluetoothOff:
    case BeaconScanStatus.locationPermissionDenied:
    case BeaconScanStatus.locationServicesOff:
    case BeaconScanStatus.scanFailed:
    case BeaconScanStatus.noMapping:
    case null:
      return AppColors.textSecondary;
  }
}

String _attendanceBeaconFooter({
  required bool scanning,
  required BeaconScanResult? result,
}) {
  if (scanning) {
    return 'Stay inside the lecture hall until the beacon scan completes.';
  }

  switch (result?.status) {
    case BeaconScanStatus.matched:
      return 'Beacon verification passed. You can continue to face capture.';
    case BeaconScanStatus.weak:
      return 'Move closer to the hall beacon and scan again.';
    case BeaconScanStatus.unstable:
      return 'Stay near the beacon until 5 successful checks are recorded, then try again.';
    case BeaconScanStatus.notFound:
      return 'Please stand inside the lecture hall and retry the scan.';
    case BeaconScanStatus.bluetoothOff:
      return 'Enable Bluetooth before retrying the hall beacon scan.';
    case BeaconScanStatus.locationPermissionDenied:
      return 'Grant location permission before retrying the hall beacon scan.';
    case BeaconScanStatus.locationServicesOff:
      return 'Turn on location services before retrying the hall beacon scan.';
    case BeaconScanStatus.scanFailed:
      return 'Retry the beacon scan while standing near the lecture hall beacon.';
    case BeaconScanStatus.noMapping:
      return 'Ask an admin to map an active beacon to this lecture hall.';
    case null:
      return 'Please stay within the lecture hall for successful verification.';
  }
}

String _attendanceRejectMessage(String? reasonCode) {
  switch ((reasonCode ?? '').toUpperCase()) {
    case 'BEACON_MISMATCH':
      return 'The detected beacon does not match this lecture hall.';
    case 'BEACON_WEAK':
      return 'The correct hall beacon was found, but the signal was too weak.';
    case 'BEACON_UNSTABLE':
      return 'The correct hall beacon was found, but not enough successful proximity checks were recorded.';
    case 'FACE_FAIL':
      return 'Face verification did not pass.';
    case 'OUTSIDE_WINDOW':
      return 'Attendance is closed for this session.';
    case 'SESSION_NOT_ASSIGNED':
      return 'This session is not assigned to your academic profile.';
    case 'NOT_ENROLLED':
      return 'Face enrollment is required before attendance can be submitted.';
  }

  return reasonCode ?? 'Attendance rejected.';
}

String _beaconStrengthLabel(double rssi) {
  if (rssi >= -65) return 'Strong';
  if (rssi >= -75) return 'Medium';
  if (rssi >= -90) return 'Weak';
  return 'No signal';
}

List<double> _rssiBars(double rssi) {
  if (rssi < -120) {
    return const [0, 0, 0, 0, 0];
  }

  if (rssi >= -60) {
    return const [0.45, 0.65, 0.9, 0.55, 0.35];
  }
  if (rssi >= -70) {
    return const [0.35, 0.55, 0.78, 0.42, 0.2];
  }
  if (rssi >= -80) {
    return const [0.2, 0.35, 0.55, 0.2, 0.1];
  }
  if (rssi >= -90) {
    return const [0.1, 0.22, 0.35, 0.08, 0];
  }
  return const [0, 0, 0, 0, 0];
}

String _formatDateTimeFromIso(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '-';

  return '${_formatDateReadable(dt.toIso8601String().split('T').first)} • ${_formatTo12Hour('${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}')}';
}

String _formatDateTimeShort(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '-';

  final date = _formatDateReadable(dt.toIso8601String().split('T').first);
  final time = _formatTo12Hour(
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
  );
  return '$date, $time';
}

String _monthGroupLabel(String? iso) {
  final dt = DateTime.tryParse(iso ?? '');
  if (dt == null) return 'UNKNOWN';

  const months = <String>[
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  return '${months[dt.month - 1]} ${dt.year}';
}

String _initialsFromEmail(String? email) {
  if (email == null || email.isEmpty) return 'NW';
  final local = email.split('@').first;
  final words = local
      .replaceAll(RegExp(r'[_\.-]+'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();

  if (words.isEmpty) return 'NW';
  if (words.length == 1) {
    return words.first
        .substring(0, math.min(2, words.first.length))
        .toUpperCase();
  }

  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

String _nameFromEmail(String? email) {
  if (email == null || email.isEmpty) return 'Student';
  final local = email.split('@').first;
  final words = local
      .replaceAll(RegExp(r'[_\.-]+'), ' ')
      .split(' ')
      .where((word) => word.trim().isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .toList();

  return words.join(' ');
}

String _maskEmail(String email) {
  final parts = email.split('@');
  if (parts.length != 2) return email;

  final local = parts[0];
  if (local.length <= 3) {
    return '${local[0]}***@${parts[1]}';
  }

  final visible = local.substring(0, 3);
  final hidden = List<String>.filled(local.length - 3, '*').join();
  return '$visible$hidden@${parts[1]}';
}

String _formatCountdown(int totalSeconds) {
  final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final ss = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

String _extractDioError(DioException error) {
  final payload = error.response?.data;
  if (payload is Map<String, dynamic>) {
    final apiError = payload['error'];
    if (apiError is Map<String, dynamic>) {
      final message = apiError['message'];
      if (message is String && message.trim().isNotEmpty) {
        final details = apiError['details'];
        if (details is String && details.trim().isNotEmpty) {
          return '$message ($details)';
        }
        if (details is Map<String, dynamic>) {
          final detailText = details['detail'];
          if (detailText is String && detailText.trim().isNotEmpty) {
            return '$message ($detailText)';
          }
        }
        if (details is Map || details is List) {
          return message;
        }
        return message;
      }
    }
  }

  final status = error.response?.statusCode ?? 0;
  if (status >= 500) {
    return 'Server error. Please try again.';
  }

  return error.message ?? 'Unknown error';
}
