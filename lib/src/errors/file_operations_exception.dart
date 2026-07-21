import 'error_code.dart';

/// Typed exception thrown by XueHuaFileOperations on hard failures.
class FileOperationsException implements Exception {
  FileOperationsException(
    this.code, {
    required this.message,
    this.details,
  });

  final ErrorCode code;
  final String message;
  final Object? details;

  @override
  String toString() =>
      'FileOperationsException(${code.code}): $message'
      '${details != null ? ' details=$details' : ''}';
}
