import 'package:dio/dio.dart';

String extractDioError(DioException error) {
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
