class ApiEnvelope<T> {
  ApiEnvelope({required this.success, this.data, this.error});

  final bool success;
  final T? data;
  final ApiError? error;

  factory ApiEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? mapper,
  ) {
    return ApiEnvelope<T>(
      success: json['success'] as bool? ?? false,
      data: mapper == null ? null : mapper(json['data']),
      error: json['error'] == null ? null : ApiError.fromJson(json['error']),
    );
  }
}

class ApiError {
  ApiError({required this.code, required this.message, this.details});

  final String code;
  final String message;
  final dynamic details;

  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      code: json['code'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? 'Unknown error',
      details: json['details'],
    );
  }
}
