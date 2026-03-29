import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/attendance_submit_dto.dart';
import '../models/student_session_dto.dart';

class NWalletApi {
  NWalletApi({required String baseUrl, Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  final Dio _dio;

  Dio get dio => _dio;

  void setToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
      return;
    }
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<Map<String, dynamic>> requestStudentOtp(String email) async {
    final response = await _dio.post(
      '/auth/student/request-otp',
      data: {'email': email},
    );
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> verifyStudentOtp(
    String otpRequestId,
    String otp,
  ) async {
    final response = await _dio.post(
      '/auth/student/verify-otp',
      data: {'otpRequestId': otpRequestId, 'otp': otp},
    );
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> studentMe() async {
    final response = await _dio.get('/student/me');
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> verifyStudentIdentity(
    List<MultipartFile> frames,
  ) async {
    final formData = FormData.fromMap({'faceFrames[]': frames});
    final response = await _dio.post(
      '/student/identity/verify',
      data: formData,
    );
    return _extractDataMap(response.data);
  }

  Future<List<StudentSessionDto>> studentSessionsToday(String date) async {
    final response = await _dio.get(
      '/student/sessions/today',
      queryParameters: {'date': date},
    );
    final data = _extractDataList(response.data);
    return data
        .map(
          (item) => StudentSessionDto.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> studentSession(String sessionId) async {
    final response = await _dio.get('/student/sessions/$sessionId');
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> uploadEnrollment(
    List<MultipartFile> images,
  ) async {
    final formData = FormData.fromMap({'images[]': images});
    final response = await _dio.post(
      '/student/enrollment/upload',
      data: formData,
    );
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> studentEnrollmentStatus() async {
    final response = await _dio.get('/student/enrollment/status');
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> submitAttendance({
    required AttendanceSubmitDto attendance,
    required List<MultipartFile> frames,
  }) async {
    final formData = FormData.fromMap({
      'sessionId': attendance.sessionId,
      'faceFrames[]': frames,
      'beaconEvidence': jsonEncode(attendance.beaconEvidence.toJson()),
    });

    final response = await _dio.post(
      '/student/attendance/submit',
      data: formData,
    );
    return _extractDataMap(response.data);
  }

  Future<List<Map<String, dynamic>>> studentAttendanceHistory({
    required String from,
    required String to,
  }) async {
    final response = await _dio.get(
      '/student/attendance/history',
      queryParameters: {'from': from, 'to': to},
    );
    return _extractDataList(
      response.data,
    ).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> adminLogin(String email, String password) async {
    final response = await _dio.post(
      '/auth/admin/login',
      data: {'email': email, 'password': password},
    );
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> adminMe() async {
    final response = await _dio.get('/admin/me');
    return _extractDataMap(response.data);
  }

  Future<List<Map<String, dynamic>>> getAdminCollection(String path) async {
    final response = await _dio.get(path);
    return _extractDataList(
      response.data,
    ).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> postAdminCollection(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post(path, data: payload);
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> patchAdminCollection(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.patch(path, data: payload);
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> putAdminCollection(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.put(path, data: payload);
    return _extractDataMap(response.data);
  }

  Future<Map<String, dynamic>> deleteAdminCollection(String path) async {
    final response = await _dio.delete(path);
    return _extractDataMap(response.data);
  }

  List<dynamic> _extractDataList(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    final data = map['data'];
    if (data is List) {
      return data;
    }
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      message: 'Invalid API data list response',
    );
  }

  Map<String, dynamic> _extractDataMap(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    final data = map['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data == null) {
      return <String, dynamic>{};
    }
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      message: 'Invalid API data map response',
    );
  }
}
