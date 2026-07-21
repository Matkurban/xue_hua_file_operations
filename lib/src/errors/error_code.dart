/// Unified error codes for [FileOperationsException] / PlatformException.
enum ErrorCode {
  cancelled('cancelled'),
  permissionDenied('permission_denied'),
  invalidArgs('invalid_args'),
  tooManyFiles('too_many_files'),
  notFound('not_found'),
  ioError('io_error'),
  unsupported('unsupported'),
  unknown('unknown');

  const ErrorCode(this.code);

  final String code;

  static ErrorCode fromCode(String? code) {
    if (code == null) return ErrorCode.unknown;
    for (final value in ErrorCode.values) {
      if (value.code == code) return value;
    }
    return ErrorCode.unknown;
  }
}
