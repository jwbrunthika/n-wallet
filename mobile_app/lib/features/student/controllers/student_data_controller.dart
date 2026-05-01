import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:mobile_app/features/auth/controllers/student_auth_controller.dart';
import 'package:mobile_app/shared/utils/dio_error.dart';
import 'package:shared_dart/shared_dart.dart';

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
      Get.snackbar('Sessions error', extractDioError(error));
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
      Get.snackbar('History error', extractDioError(error));
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
