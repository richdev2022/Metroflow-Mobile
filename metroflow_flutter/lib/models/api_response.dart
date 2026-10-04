class ApiResponse<T> {
  final bool success;
  final String? message;
  final String? error;
  final T? data;

  ApiResponse({
    required this.success,
    this.message,
    this.error,
    this.data,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    return ApiResponse<T>(
      success: json['success'] as bool,
      message: json['message'] as String?,
      error: json['error'] as String?,
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : null,
    );
  }

  Map<String, dynamic> toJson(Object? Function(T)? toJsonT) {
    return {
      'success': success,
      'message': message,
      'error': error,
      'data': data != null && toJsonT != null ? toJsonT(data as T) : null,
    };
  }
}
