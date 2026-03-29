import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:get_storage/get_storage.dart';
import 'package:shared_dart/shared_dart.dart';

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://51.255.201.31:18082/api/v1',
);

String extractApiError(Object error) {
  if (error is DioException) {
    final payload = error.response?.data;
    if (payload is Map) {
      final envelope = Map<String, dynamic>.from(payload);
      final errorNode = envelope['error'];
      if (errorNode is Map) {
        final apiError = Map<String, dynamic>.from(errorNode);
        final message = (apiError['message'] as String?)?.trim();
        final details = apiError['details'];
        if (details is Map) {
          final detailMap = Map<String, dynamic>.from(details);
          final missingModuleCodes = detailMap['missingModuleCodes'];
          if (missingModuleCodes is List && missingModuleCodes.isNotEmpty) {
            final missing = missingModuleCodes
                .map((value) => value.toString())
                .join(', ');
            return '${message ?? 'Validation failed.'} Missing module codes: $missing';
          }
        }
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    }
    return error.message ?? 'Unknown API error';
  }
  return error.toString();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  Get.put(AuthController());
  Get.put(AdminDataController());

  runApp(const AdminWebApp());
}

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();

    return Obx(
      () => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'N Wallet Admin',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A7C66)),
          useMaterial3: true,
        ),
        initialRoute: auth.hasToken ? '/dashboard' : '/login',
        getPages: [
          GetPage(name: '/login', page: () => const AdminLoginPage()),
          GetPage(name: '/dashboard', page: () => const AdminDashboardPage()),
        ],
      ),
    );
  }
}

class AuthController extends GetxController {
  final GetStorage _storage = GetStorage();
  late final NWalletApi api;

  final RxnString token = RxnString();
  final RxMap<String, dynamic> admin = <String, dynamic>{}.obs;
  final RxBool loading = false.obs;

  bool get hasToken => (token.value ?? '').isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    api = NWalletApi(baseUrl: kApiBaseUrl);

    final savedToken = _storage.read<String>('admin_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      token.value = savedToken;
      api.setToken(savedToken);
      fetchMe();
    }
  }

  Future<void> login(String email, String password) async {
    loading.value = true;
    try {
      final response = await api.adminLogin(email, password);
      final accessToken = response['accessToken'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Token missing in login response');
      }

      token.value = accessToken;
      _storage.write('admin_token', accessToken);
      api.setToken(accessToken);
      admin.assignAll(
        Map<String, dynamic>.from(response['admin'] as Map? ?? {}),
      );
      try {
        await Get.find<AdminDataController>().refreshAll();
      } catch (_) {
        // Dashboard pages can still load lazily if one dataset fails at login time.
      }

      Get.offAllNamed('/dashboard');
    } on DioException catch (error) {
      Get.snackbar('Login failed', _extractError(error));
    } catch (error) {
      Get.snackbar('Login failed', error.toString());
    } finally {
      loading.value = false;
    }
  }

  Future<void> fetchMe() async {
    if (!hasToken) {
      return;
    }

    try {
      final me = await api.adminMe();
      admin.assignAll(me);
    } on DioException {
      logout();
    }
  }

  void logout() {
    token.value = null;
    admin.clear();
    _storage.remove('admin_token');
    api.setToken(null);
    Get.offAllNamed('/login');
  }

  String _extractError(DioException error) {
    return extractApiError(error);
  }
}

class AdminDataController extends GetxController {
  final AuthController auth = Get.find<AuthController>();

  final RxInt selectedTab = 0.obs;

  final RxList<Map<String, dynamic>> halls = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> beacons = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> modules = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> courses = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> sessions = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> students = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> attendanceLogs =
      <Map<String, dynamic>>[].obs;

  final RxMap<String, dynamic> settings = <String, dynamic>{}.obs;

  final RxBool loading = false.obs;

  @override
  void onInit() {
    super.onInit();
    ever<bool>(auth.loading, (_) {});
    if (auth.hasToken) {
      refreshAll();
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([
      fetchHalls(),
      fetchBeacons(),
      fetchModules(),
      fetchCourses(),
      fetchSessions(),
      fetchStudents(),
      fetchAttendanceLogs(),
      fetchSettings(),
    ]);
  }

  Future<void> fetchHalls() async {
    halls.assignAll(await auth.api.getAdminCollection('/admin/halls'));
  }

  Future<void> fetchBeacons() async {
    beacons.assignAll(await auth.api.getAdminCollection('/admin/beacons'));
  }

  Future<void> fetchModules() async {
    modules.assignAll(await auth.api.getAdminCollection('/admin/modules'));
  }

  Future<void> fetchCourses() async {
    courses.assignAll(await auth.api.getAdminCollection('/admin/courses'));
  }

  Future<void> fetchSessions() async {
    sessions.assignAll(await auth.api.getAdminCollection('/admin/sessions'));
  }

  Future<void> fetchStudents() async {
    students.assignAll(await auth.api.getAdminCollection('/admin/students'));
  }

  Future<void> fetchAttendanceLogs() async {
    attendanceLogs.assignAll(
      await auth.api.getAdminCollection('/admin/attendance/logs'),
    );
  }

  Future<void> fetchSettings() async {
    final response = await auth.api.dio.get('/admin/settings');
    final payload = Map<String, dynamic>.from(response.data as Map);
    settings.assignAll(
      Map<String, dynamic>.from(payload['data'] as Map? ?? {}),
    );
  }

  Future<void> createHall(String name) async {
    await auth.api.postAdminCollection('/admin/halls', {'name': name});
    await fetchHalls();
  }

  Future<void> updateHall(String id, String name) async {
    await auth.api.putAdminCollection('/admin/halls/$id', {'name': name});
    await fetchHalls();
  }

  Future<void> deleteHall(String id) async {
    await auth.api.deleteAdminCollection('/admin/halls/$id');
    await fetchHalls();
  }

  Future<void> createBeacon(Map<String, dynamic> payload) async {
    await auth.api.postAdminCollection('/admin/beacons', payload);
    await fetchBeacons();
  }

  Future<void> updateBeacon(String id, Map<String, dynamic> payload) async {
    await auth.api.putAdminCollection('/admin/beacons/$id', payload);
    await fetchBeacons();
  }

  Future<void> deleteBeacon(String id) async {
    await auth.api.deleteAdminCollection('/admin/beacons/$id');
    await fetchBeacons();
  }

  Future<void> createModule(Map<String, dynamic> payload) async {
    await auth.api.postAdminCollection('/admin/modules', payload);
    await fetchModules();
  }

  Future<void> updateModule(String id, Map<String, dynamic> payload) async {
    await auth.api.putAdminCollection('/admin/modules/$id', payload);
    await fetchModules();
  }

  Future<void> deleteModule(String id) async {
    await auth.api.deleteAdminCollection('/admin/modules/$id');
    await fetchModules();
  }

  Future<void> createCourse(Map<String, dynamic> payload) async {
    await auth.api.postAdminCollection('/admin/courses', payload);
    await fetchCourses();
  }

  Future<void> updateCourse(String id, Map<String, dynamic> payload) async {
    await auth.api.putAdminCollection('/admin/courses/$id', payload);
    await fetchCourses();
  }

  Future<void> deleteCourse(String id) async {
    await auth.api.deleteAdminCollection('/admin/courses/$id');
    await fetchCourses();
  }

  Future<Map<String, dynamic>> importCsv(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('CSV file bytes are empty');
    }

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: file.name),
    });

    final response = await auth.api.dio.post(
      '/admin/timetable/import',
      data: formData,
    );
    final envelope = Map<String, dynamic>.from(response.data as Map? ?? {});
    final data = Map<String, dynamic>.from(envelope['data'] as Map? ?? {});
    await fetchSessions();

    return data;
  }

  Future<void> resetEnrollment(String email) async {
    await auth.api.postAdminCollection(
      '/admin/students/${Uri.encodeComponent(email)}/reset-enrollment',
      {},
    );
    await fetchStudents();
  }

  Future<void> updateStudentDetails(
    String currentEmail, {
    required String email,
    String? name,
  }) async {
    await auth.api.patchAdminCollection(
      '/admin/students/${Uri.encodeComponent(currentEmail)}',
      {'email': email, 'name': name},
    );
    await fetchStudents();
    await fetchAttendanceLogs();
  }

  Future<void> deleteStudent(String email) async {
    await auth.api.deleteAdminCollection(
      '/admin/students/${Uri.encodeComponent(email)}',
    );
    await fetchStudents();
  }

  Future<void> assignAcademicProfile(
    String email, {
    String? courseCode,
    String? batch,
    String? studyMode,
  }) async {
    await auth.api.patchAdminCollection(
      '/admin/students/${Uri.encodeComponent(email)}/academic-profile',
      {'courseCode': courseCode, 'batch': batch, 'studyMode': studyMode},
    );
    await fetchStudents();
    await fetchSessions();
  }

  Future<List<Map<String, dynamic>>> getEnrollmentImages(String email) async {
    return auth.api.getAdminCollection(
      '/admin/students/${Uri.encodeComponent(email)}/enrollment-images',
    );
  }

  Future<void> updateSettings(Map<String, dynamic> payload) async {
    await auth.api.patchAdminCollection('/admin/settings', payload);
    await fetchSettings();
  }

  Future<String> exportAttendanceCsv() async {
    final response = await auth.api.dio.get<String>(
      '/admin/attendance/export',
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final AuthController auth = Get.find<AuthController>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    emailController.text = 'nwallet.2002@gmail.com';
    passwordController.text = 'Nodecmb@2k26';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Card(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'N Wallet Admin Login',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 20),
                Obx(
                  () => FilledButton(
                    onPressed: auth.loading.value
                        ? null
                        : () {
                            auth.login(
                              emailController.text.trim(),
                              passwordController.text,
                            );
                          },
                    child: auth.loading.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(),
                          )
                        : const Text('Login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final data = Get.find<AdminDataController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('N Wallet Admin Dashboard'),
        actions: [
          TextButton(
            onPressed: () => data.refreshAll(),
            child: const Text('Refresh'),
          ),
          TextButton(onPressed: auth.logout, child: const Text('Logout')),
        ],
      ),
      body: Row(
        children: [
          Obx(
            () => NavigationRail(
              selectedIndex: data.selectedTab.value,
              onDestinationSelected: (index) => data.selectedTab.value = index,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard),
                  label: Text('Dashboard'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.location_city),
                  label: Text('Halls'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bluetooth),
                  label: Text('Beacons'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.book),
                  label: Text('Modules'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.school),
                  label: Text('Courses'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.upload_file),
                  label: Text('Import CSV'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.event),
                  label: Text('Sessions'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.groups),
                  label: Text('Students'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.fact_check),
                  label: Text('Attendance'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Obx(() {
              switch (data.selectedTab.value) {
                case 1:
                  return HallPage(controller: data);
                case 2:
                  return BeaconPage(controller: data);
                case 3:
                  return ModulePage(controller: data);
                case 4:
                  return CoursePage(controller: data);
                case 5:
                  return TimetableImportPage(controller: data);
                case 6:
                  return SessionPage(controller: data);
                case 7:
                  return StudentPage(controller: data);
                case 8:
                  return AttendancePage(controller: data);
                case 9:
                  return SettingsPage(controller: data);
                default:
                  return DashboardHome(controller: data);
              }
            }),
          ),
        ],
      ),
    );
  }
}

class DashboardHome extends StatelessWidget {
  const DashboardHome({super.key, required this.controller});

  final AdminDataController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _metricCard('Halls', controller.halls.length.toString()),
          _metricCard('Beacons', controller.beacons.length.toString()),
          _metricCard('Modules', controller.modules.length.toString()),
          _metricCard('Courses', controller.courses.length.toString()),
          _metricCard('Sessions', controller.sessions.length.toString()),
          _metricCard('Students', controller.students.length.toString()),
          _metricCard(
            'Attendance Logs',
            controller.attendanceLogs.length.toString(),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value) {
    return Card(
      child: SizedBox(
        width: 220,
        height: 120,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 16)),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HallPage extends StatefulWidget {
  const HallPage({super.key, required this.controller});

  final AdminDataController controller;

  @override
  State<HallPage> createState() => _HallPageState();
}

class _HallPageState extends State<HallPage> {
  final TextEditingController nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'New hall name'),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () async {
                  await widget.controller.createHall(
                    nameController.text.trim(),
                  );
                  nameController.clear();
                },
                child: const Text('Add Hall'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(
              () => ListView.builder(
                itemCount: widget.controller.halls.length,
                itemBuilder: (_, index) {
                  final hall = widget.controller.halls[index];
                  return ListTile(
                    title: Text(hall['name'] as String? ?? ''),
                    subtitle: Text(hall['id'] as String? ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () =>
                          widget.controller.deleteHall(hall['id'] as String),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BeaconPage extends StatefulWidget {
  const BeaconPage({super.key, required this.controller});

  final AdminDataController controller;

  @override
  State<BeaconPage> createState() => _BeaconPageState();
}

class _BeaconPageState extends State<BeaconPage> {
  final uuidController = TextEditingController();
  final majorController = TextEditingController();
  final minorController = TextEditingController();
  String? selectedHallId;

  String? _selectedHallValue(List<Map<String, dynamic>> halls) {
    final current = selectedHallId;
    if (current != null &&
        halls.any((hall) => (hall['id'] as String?) == current)) {
      return current;
    }
    return halls.isEmpty ? null : halls.first['id'] as String?;
  }

  String _hallName(String? hallId) {
    for (final hall in widget.controller.halls) {
      if ((hall['id'] as String?) == hallId) {
        final name = (hall['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          return name;
        }
      }
    }
    return hallId?.trim().isNotEmpty == true ? hallId! : 'Unknown hall';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Obx(() {
            final halls = widget.controller.halls.toList(growable: false);
            final currentHallId = _selectedHallValue(halls);

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: uuidController,
                    decoration: const InputDecoration(labelText: 'UUID'),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: majorController,
                    decoration: const InputDecoration(labelText: 'Major'),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: minorController,
                    decoration: const InputDecoration(labelText: 'Minor'),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    value: currentHallId,
                    decoration: const InputDecoration(
                      labelText: 'Lecture hall',
                    ),
                    items: halls
                        .map(
                          (hall) => DropdownMenuItem<String>(
                            value: hall['id'] as String?,
                            child: Text(
                              (hall['name'] as String?) ??
                                  (hall['id'] as String? ?? ''),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: halls.isEmpty
                        ? null
                        : (value) {
                            setState(() => selectedHallId = value);
                          },
                  ),
                ),
                FilledButton(
                  onPressed: halls.isEmpty
                      ? null
                      : () async {
                          final hallId = _selectedHallValue(halls);
                          if (hallId == null || hallId.isEmpty) {
                            Get.snackbar(
                              'Beacon',
                              'Please select a lecture hall first.',
                            );
                            return;
                          }

                          await widget.controller.createBeacon({
                            'uuid': uuidController.text.trim(),
                            'major': int.tryParse(majorController.text) ?? 0,
                            'minor': int.tryParse(minorController.text) ?? 0,
                            'hallId': hallId,
                            'enabled': true,
                          });

                          uuidController.clear();
                          majorController.clear();
                          minorController.clear();
                        },
                  child: const Text('Add Beacon'),
                ),
              ],
            );
          }),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(
              () => ListView.builder(
                itemCount: widget.controller.beacons.length,
                itemBuilder: (_, index) {
                  final beacon = widget.controller.beacons[index];
                  return ListTile(
                    title: Text(
                      '${beacon['uuid']} (${beacon['major']}/${beacon['minor']})',
                    ),
                    subtitle: Text(
                      '${_hallName(beacon['hallId'] as String?)} | hallId: ${beacon['hallId']} | enabled: ${beacon['enabled']}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => widget.controller.deleteBeacon(
                        beacon['id'] as String,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ModulePage extends StatefulWidget {
  const ModulePage({super.key, required this.controller});

  final AdminDataController controller;

  @override
  State<ModulePage> createState() => _ModulePageState();
}

class _ModulePageState extends State<ModulePage> {
  final codeController = TextEditingController();
  final nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: codeController,
                  decoration: const InputDecoration(labelText: 'Module code'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Module name'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  await widget.controller.createModule({
                    'moduleCode': codeController.text.trim(),
                    'moduleName': nameController.text.trim(),
                    'leaderAdminId': null,
                  });
                },
                child: const Text('Add Module'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(
              () => ListView.builder(
                itemCount: widget.controller.modules.length,
                itemBuilder: (_, index) {
                  final module = widget.controller.modules[index];
                  return ListTile(
                    title: Text(
                      '${module['moduleCode']} - ${module['moduleName']}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => widget.controller.deleteModule(
                        module['id'] as String,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CoursePage extends StatefulWidget {
  const CoursePage({super.key, required this.controller});

  final AdminDataController controller;

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  final courseNameController = TextEditingController();
  final batchCountController = TextEditingController(text: '1');
  final batchLabelsController = TextEditingController();
  final moduleCodesController = TextEditingController();

  String deliveryMode = 'BOTH';
  bool enabled = true;

  List<String> _splitCsv(String value) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> _coursePayload() {
    final moduleCodes = _splitCsv(
      moduleCodesController.text,
    ).map((code) => code.toUpperCase()).toList();
    final batchLabels = _splitCsv(batchLabelsController.text);

    return {
      'courseName': courseNameController.text.trim(),
      'deliveryMode': deliveryMode,
      'batchCount': int.tryParse(batchCountController.text.trim()) ?? 1,
      'batchLabels': batchLabels,
      'moduleCodes': moduleCodes,
      'enabled': enabled,
    };
  }

  Future<void> _showEditDialog(Map<String, dynamic> course) async {
    final nameCtrl = TextEditingController(
      text: course['courseName'] as String? ?? '',
    );
    final batchCountCtrl = TextEditingController(
      text: (course['batchCount'] ?? 1).toString(),
    );
    final batchLabelsCtrl = TextEditingController(
      text: (course['batchLabels'] is List)
          ? (course['batchLabels'] as List).join(', ')
          : '',
    );
    final moduleCodesCtrl = TextEditingController(
      text: (course['moduleCodes'] is List)
          ? (course['moduleCodes'] as List).join(', ')
          : '',
    );
    var editMode = course['deliveryMode'] as String? ?? 'BOTH';
    var editEnabled = (course['enabled'] as bool?) ?? true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Course'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Course name',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: editMode,
                        decoration: const InputDecoration(
                          labelText: 'Delivery mode',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'WEEKDAY',
                            child: Text('WEEKDAY'),
                          ),
                          DropdownMenuItem(
                            value: 'WEEKEND',
                            child: Text('WEEKEND'),
                          ),
                          DropdownMenuItem(value: 'BOTH', child: Text('BOTH')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => editMode = value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: batchCountCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Batch count',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: batchLabelsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Batch labels (comma-separated, optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: moduleCodesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Module codes (comma-separated)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Enabled'),
                        value: editEnabled,
                        onChanged: (value) =>
                            setDialogState(() => editEnabled = value),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    await widget.controller
                        .updateCourse(course['id'] as String, {
                          'courseName': nameCtrl.text.trim(),
                          'deliveryMode': editMode,
                          'batchCount':
                              int.tryParse(batchCountCtrl.text.trim()) ?? 1,
                          'batchLabels': _splitCsv(batchLabelsCtrl.text),
                          'moduleCodes': _splitCsv(
                            moduleCodesCtrl.text,
                          ).map((code) => code.toUpperCase()).toList(),
                          'enabled': editEnabled,
                        });
                    if (context.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    batchCountCtrl.dispose();
    batchLabelsCtrl.dispose();
    moduleCodesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: courseNameController,
                  decoration: const InputDecoration(labelText: 'Course name'),
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: deliveryMode,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: const [
                    DropdownMenuItem(value: 'WEEKDAY', child: Text('WEEKDAY')),
                    DropdownMenuItem(value: 'WEEKEND', child: Text('WEEKEND')),
                    DropdownMenuItem(value: 'BOTH', child: Text('BOTH')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => deliveryMode = value);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: batchCountController,
                  decoration: const InputDecoration(labelText: 'Batch count'),
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: batchLabelsController,
                  decoration: const InputDecoration(
                    labelText: 'Batch labels (comma-separated, optional)',
                  ),
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: moduleCodesController,
                  decoration: const InputDecoration(
                    labelText: 'Module codes (comma-separated)',
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: SwitchListTile(
                  title: const Text('Enabled'),
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await widget.controller.createCourse(_coursePayload());
                    courseNameController.clear();
                    batchCountController.text = '1';
                    batchLabelsController.clear();
                    moduleCodesController.clear();
                    if (context.mounted) {
                      Get.snackbar('Saved', 'Course added successfully.');
                    }
                  } catch (error) {
                    if (context.mounted) {
                      Get.snackbar('Add Course failed', extractApiError(error));
                    }
                  }
                },
                child: const Text('Add Course'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Tip: Module codes entered here are auto-created if missing.',
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(
              () => ListView.builder(
                itemCount: widget.controller.courses.length,
                itemBuilder: (_, index) {
                  final course = widget.controller.courses[index];
                  final batchLabels = (course['batchLabels'] as List? ?? [])
                      .join(', ');
                  final moduleCodes = (course['moduleCodes'] as List? ?? [])
                      .join(', ');

                  return Card(
                    child: ListTile(
                      title: Text('${course['courseName']}'),
                      subtitle: Text(
                        'mode: ${course['deliveryMode']} | batches: $batchLabels | modules: $moduleCodes',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showEditDialog(course),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => widget.controller.deleteCourse(
                              course['id'] as String,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TimetableImportPage extends StatefulWidget {
  const TimetableImportPage({super.key, required this.controller});

  final AdminDataController controller;

  @override
  State<TimetableImportPage> createState() => _TimetableImportPageState();
}

class _TimetableImportPageState extends State<TimetableImportPage> {
  String? selectedFile;
  Map<String, dynamic>? _lastImportSummary;
  List<Map<String, dynamic>> _lastImportErrors = const [];
  String? _lastImportMessage;
  bool _importing = false;
  static const String _requiredHeaders =
      'session_date,start_time,end_time,course_name,module_code,module_name,hall_name,batch,delivery_mode,lecturer_email,attendance_open_minutes_after_start,attendance_close_minutes_before_end,notes';
  static const String _exampleRow =
      '2026-02-23,09:00,11:00,BSc Software Engineering,SE401,Software Engineering Project,Hall A,Batch-01,WEEKDAY,lecturer1@university.edu,20,15,Week 1 lecture';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upload timetable CSV',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'CSV format guide',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE1E6EF)),
              ),
              child: const SelectableText(
                'Required headers:\n$_requiredHeaders',
                style: TextStyle(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE1E6EF)),
              ),
              child: const SelectableText(
                'Example row:\n$_exampleRow',
                style: TextStyle(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tip: You can use sample-data/timetable_sample.csv as a template.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5C6B83)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Legacy support: course_code column is still accepted but optional.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5C6B83)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Attendance columns now mean: opens X minutes after start, closes Y minutes before end. Legacy before/after header names are still accepted.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5C6B83)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Date accepts YYYY-MM-DD or M/D/YYYY. Time accepts HH:MM or hour values like 9, 14.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5C6B83)),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _importing ? null : _importCsv,
              child: Text(
                _importing ? 'Importing...' : 'Choose CSV and Import',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              selectedFile == null
                  ? 'No file selected'
                  : 'Selected: $selectedFile',
            ),
            if (_lastImportSummary != null || _lastImportMessage != null) ...[
              const SizedBox(height: 16),
              _buildImportResultCard(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    setState(() {
      selectedFile = file.name;
      _importing = true;
      _lastImportMessage = null;
    });

    try {
      final summary = await widget.controller.importCsv(file);
      final errors = (summary['errors'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final inserted = (summary['inserted'] as num?)?.toInt() ?? 0;
      final errorCount = (summary['errorCount'] as num?)?.toInt() ?? 0;
      final errorRowCount =
          (summary['errorRowCount'] as num?)?.toInt() ?? errorCount;
      final status = (summary['status'] as String?) ?? 'SUCCESS';

      setState(() {
        _lastImportSummary = summary;
        _lastImportErrors = errors;
        _lastImportMessage = null;
      });

      if (status == 'FAILED' || inserted == 0) {
        Get.snackbar(
          'Import failed',
          'No timetable rows imported. Review the row errors below.',
        );
      } else if (errorCount > 0) {
        Get.snackbar(
          'Import partial',
          'Imported $inserted row(s). Rejected $errorRowCount row(s). Review the errors below.',
        );
      } else {
        Get.snackbar(
          'Import complete',
          'CSV imported successfully. $inserted row(s) added.',
        );
      }
    } catch (error) {
      setState(() {
        _lastImportSummary = null;
        _lastImportErrors = const [];
        _lastImportMessage = extractApiError(error);
      });
      Get.snackbar('Import failed', extractApiError(error));
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
        });
      }
    }
  }

  Widget _buildImportResultCard() {
    final summary = _lastImportSummary;
    final status = (summary?['status'] as String?) ?? 'FAILED';
    final inserted = (summary?['inserted'] as num?)?.toInt() ?? 0;
    final errorCount = (summary?['errorCount'] as num?)?.toInt() ?? 0;
    final errorRowCount =
        (summary?['errorRowCount'] as num?)?.toInt() ?? errorCount;
    final totalRows = (summary?['totalRows'] as num?)?.toInt() ?? 0;
    final background = switch (status) {
      'SUCCESS' => const Color(0xFFE9F8EF),
      'PARTIAL' => const Color(0xFFFFF6E5),
      _ => const Color(0xFFFDECEC),
    };
    final accent = switch (status) {
      'SUCCESS' => const Color(0xFF1E8E3E),
      'PARTIAL' => const Color(0xFFB26A00),
      _ => const Color(0xFFC62828),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _lastImportMessage ?? _statusLabel(status),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _summaryChip('Imported', inserted.toString()),
                _summaryChip('Rejected Rows', errorRowCount.toString()),
                _summaryChip('Error Details', errorCount.toString()),
                _summaryChip('Rows Read', totalRows.toString()),
              ],
            ),
          ],
          if (_lastImportErrors.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Row-level errors',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Row numbers match the CSV file, including the header row.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5C6B83)),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  Colors.white.withValues(alpha: 0.75),
                ),
                columns: const [
                  DataColumn(label: Text('Row')),
                  DataColumn(label: Text('Column')),
                  DataColumn(label: Text('Value')),
                  DataColumn(label: Text('Error')),
                ],
                rows: _lastImportErrors
                    .map(
                      (error) => DataRow(
                        cells: [
                          DataCell(Text((error['row'] ?? '-').toString())),
                          DataCell(Text(_displayErrorColumn(error['column']))),
                          DataCell(
                            SizedBox(
                              width: 180,
                              child: Text(
                                _displayErrorValue(error['value']),
                                softWrap: true,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 420,
                              child: Text(
                                (error['message'] ?? 'Unknown error')
                                    .toString(),
                                softWrap: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: $value'),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'SUCCESS':
        return 'Import complete';
      case 'PARTIAL':
        return 'Import completed with skipped rows';
      default:
        return 'Import failed';
    }
  }

  String _displayErrorColumn(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _displayErrorValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }
}

class SessionPage extends StatelessWidget {
  const SessionPage({super.key, required this.controller});

  final AdminDataController controller;

  String _resolveCourseName(String? courseCode) {
    for (final course in controller.courses) {
      if ((course['courseCode'] as String?) == courseCode) {
        return (course['courseName'] as String?) ?? (courseCode ?? '-');
      }
    }
    return courseCode ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: controller.sessions.length,
        itemBuilder: (_, index) {
          final session = controller.sessions[index];
          final courseName = _resolveCourseName(
            session['courseCode'] as String?,
          );
          return Card(
            child: ListTile(
              title: Text(
                '$courseName | ${session['moduleCode']} ${session['moduleName']}',
              ),
              subtitle: Text(
                '${session['sessionDate']} ${session['startTime']}-${session['endTime']} | batch: ${session['batch']} | mode: ${session['deliveryMode'] ?? 'BOTH'} | hallId: ${session['hallId']}',
              ),
            ),
          );
        },
      ),
    );
  }
}

class StudentPage extends StatelessWidget {
  const StudentPage({super.key, required this.controller});

  final AdminDataController controller;

  String _resolveCourseName(String? courseCode) {
    if (courseCode == null || courseCode.isEmpty) {
      return '-';
    }

    for (final course in controller.courses) {
      if ((course['courseCode'] as String?) == courseCode) {
        return (course['courseName'] as String?) ?? courseCode;
      }
    }

    return courseCode;
  }

  Future<void> _openAcademicProfileDialog(
    BuildContext context,
    Map<String, dynamic> student,
  ) async {
    final email = student['email'] as String? ?? '';
    var selectedCourseCode = student['courseCode'] as String?;
    var selectedStudyMode = student['studyMode'] as String? ?? 'WEEKDAY';
    var selectedBatch = student['batch'] as String?;
    final batchController = TextEditingController(text: selectedBatch ?? '');

    List<String> resolveBatchLabels(String? courseCode) {
      Map<String, dynamic>? course;
      for (final item in controller.courses) {
        if (item['courseCode'] == courseCode) {
          course = item;
          break;
        }
      }
      if (course == null) {
        return [];
      }
      return (course['batchLabels'] as List? ?? [])
          .map((item) => item.toString())
          .toList();
    }

    List<String> batchLabels = resolveBatchLabels(selectedCourseCode);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('Academic Profile: $email'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedCourseCode,
                      decoration: const InputDecoration(labelText: 'Course'),
                      items: controller.courses
                          .map(
                            (course) => DropdownMenuItem<String>(
                              value: course['courseCode'] as String?,
                              child: Text('${course['courseName']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedCourseCode = value;
                          batchLabels = resolveBatchLabels(value);
                          if (batchLabels.isNotEmpty) {
                            selectedBatch = batchLabels.first;
                            batchController.text = selectedBatch ?? '';
                          } else {
                            selectedBatch = null;
                            batchController.clear();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedStudyMode,
                      decoration: const InputDecoration(
                        labelText: 'Student study mode',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'WEEKDAY',
                          child: Text('WEEKDAY'),
                        ),
                        DropdownMenuItem(
                          value: 'WEEKEND',
                          child: Text('WEEKEND'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedStudyMode = value);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    if (batchLabels.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: batchLabels.contains(selectedBatch)
                            ? selectedBatch
                            : batchLabels.first,
                        decoration: const InputDecoration(labelText: 'Batch'),
                        items: batchLabels
                            .map(
                              (batch) => DropdownMenuItem<String>(
                                value: batch,
                                child: Text(batch),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() => selectedBatch = value);
                        },
                      )
                    else
                      TextField(
                        controller: batchController,
                        decoration: const InputDecoration(
                          labelText: 'Batch (free text)',
                        ),
                        onChanged: (value) => selectedBatch = value.trim(),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    await controller.assignAcademicProfile(
                      email,
                      courseCode: null,
                      batch: null,
                      studyMode: null,
                    );
                    if (context.mounted) {
                      Navigator.of(dialogContext).pop();
                      Get.snackbar(
                        'Academic profile',
                        'Academic profile cleared for $email',
                      );
                    }
                  },
                  child: const Text('Clear'),
                ),
                FilledButton(
                  onPressed: () async {
                    final batch = (selectedBatch ?? batchController.text)
                        .trim();
                    if ((selectedCourseCode ?? '').isEmpty || batch.isEmpty) {
                      Get.snackbar(
                        'Validation',
                        'Course and batch are required for assignment.',
                      );
                      return;
                    }

                    await controller.assignAcademicProfile(
                      email,
                      courseCode: selectedCourseCode!.trim(),
                      batch: batch,
                      studyMode: selectedStudyMode,
                    );

                    if (context.mounted) {
                      Navigator.of(dialogContext).pop();
                      Get.snackbar(
                        'Academic profile',
                        'Academic profile updated for $email',
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    batchController.dispose();
  }

  Future<void> _openEditStudentDialog(
    BuildContext context,
    Map<String, dynamic> student,
  ) async {
    final currentEmail = student['email'] as String? ?? '';
    final emailController = TextEditingController(text: currentEmail);
    final nameController = TextEditingController(
      text: student['name'] as String? ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Edit Student: $currentEmail'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Student email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Student name (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final updatedEmail = emailController.text.trim().toLowerCase();
                final updatedName = nameController.text.trim();
                if (updatedEmail.isEmpty) {
                  Get.snackbar('Validation', 'Student email is required.');
                  return;
                }

                try {
                  await controller.updateStudentDetails(
                    currentEmail,
                    email: updatedEmail,
                    name: updatedName.isEmpty ? null : updatedName,
                  );
                  if (context.mounted) {
                    Navigator.of(dialogContext).pop();
                    Get.snackbar(
                      'Student updated',
                      'Details updated for $updatedEmail',
                    );
                  }
                } catch (error) {
                  Get.snackbar('Update failed', extractApiError(error));
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    emailController.dispose();
    nameController.dispose();
  }

  Future<void> _confirmDeleteStudent(BuildContext context, String email) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete student?'),
          content: Text(
            'This will remove the student account for $email. Attendance records are kept for logs.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                try {
                  await controller.deleteStudent(email);
                  if (context.mounted) {
                    Navigator.of(dialogContext).pop();
                    Get.snackbar('Student deleted', 'Removed $email');
                  }
                } catch (error) {
                  Get.snackbar('Delete failed', extractApiError(error));
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: controller.students.length,
        itemBuilder: (_, index) {
          final student = controller.students[index];
          final email = student['email'] as String;
          final courseName = _resolveCourseName(
            student['courseCode'] as String?,
          );
          final name = (student['name'] as String?)?.trim();
          final profileText =
              'Course: $courseName | Batch: ${student['batch'] ?? '-'} | Mode: ${student['studyMode'] ?? '-'}';
          return Card(
            child: ListTile(
              title: Text(
                name != null && name.isNotEmpty ? '$name <$email>' : email,
              ),
              subtitle: Text(
                'Status: ${student['enrollmentStatus']}\n$profileText',
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _openEditStudentDialog(context, student),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    onPressed: () =>
                        _openAcademicProfileDialog(context, student),
                    child: const Text('Assign Profile'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final images = await controller.getEnrollmentImages(
                        email,
                      );
                      Get.dialog(
                        AlertDialog(
                          title: Text('Enrollment images: $email'),
                          content: SizedBox(
                            width: 500,
                            child: ListView(
                              shrinkWrap: true,
                              children: images
                                  .map(
                                    (image) => ListTile(
                                      title: Text(
                                        (image['path'] as String?) ?? '',
                                      ),
                                      subtitle: Text(
                                        'quality: ${(image['qualityScore'] ?? '').toString()}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('View Images'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await controller.resetEnrollment(email);
                      Get.snackbar(
                        'Reset complete',
                        'Enrollment reset for $email',
                      );
                    },
                    child: const Text('Reset Enrollment'),
                  ),
                  TextButton(
                    onPressed: () => _confirmDeleteStudent(context, email),
                    child: const Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key, required this.controller});

  final AdminDataController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            final csv = await controller.exportAttendanceCsv();
            Get.dialog(
              AlertDialog(
                title: const Text('Attendance CSV Export Preview'),
                content: SizedBox(
                  width: 700,
                  child: SingleChildScrollView(child: Text(csv)),
                ),
              ),
            );
          },
          child: const Text('Export CSV'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Obx(
            () => ListView.builder(
              itemCount: controller.attendanceLogs.length,
              itemBuilder: (_, index) {
                final row = controller.attendanceLogs[index];
                return ListTile(
                  title: Text('${row['studentEmail']} - ${row['status']}'),
                  subtitle: Text(
                    'reason: ${row['reasonCode'] ?? '-'} | score: ${row['faceScore']}',
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AdminDataController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final faceController = TextEditingController();
  final rssiController = TextEditingController();
  final stabilityController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = widget.controller.settings;
    faceController.text = (data['faceMatchThreshold'] ?? 0.55).toString();
    rssiController.text = (data['beaconRssiThreshold'] ?? -70).toString();
    stabilityController.text = (data['beaconStabilitySeconds'] ?? 8).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: faceController,
              decoration: const InputDecoration(
                labelText: 'Face Match Threshold',
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 320,
            child: TextField(
              controller: rssiController,
              decoration: const InputDecoration(
                labelText: 'Beacon RSSI Threshold',
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 320,
            child: TextField(
              controller: stabilityController,
              decoration: const InputDecoration(
                labelText: 'Beacon Stability Seconds',
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await widget.controller.updateSettings({
                'faceMatchThreshold':
                    double.tryParse(faceController.text) ?? 0.55,
                'beaconRssiThreshold':
                    double.tryParse(rssiController.text) ?? -70,
                'beaconStabilitySeconds':
                    int.tryParse(stabilityController.text) ?? 8,
              });
              Get.snackbar('Saved', 'Settings updated.');
            },
            child: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }
}
