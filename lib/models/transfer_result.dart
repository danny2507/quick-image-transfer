class TransferResult {
  final bool success;
  final String message;
  final String? filePath;
  final String? error;

  TransferResult({
    required this.success,
    required this.message,
    this.filePath,
    this.error,
  });

  factory TransferResult.success(String path) {
    return TransferResult(
      success: true,
      message: 'Transfer successful',
      filePath: path,
    );
  }

  factory TransferResult.failure(String errorMessage) {
    return TransferResult(
      success: false,
      message: 'Transfer failed',
      error: errorMessage,
    );
  }

  factory TransferResult.fromJson(Map<String, dynamic> json) {
    return TransferResult(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      filePath: json['path'],
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      if (filePath != null) 'path': filePath,
      if (error != null) 'error': error,
    };
  }
}