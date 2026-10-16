import '../errors/error_code.dart';
import '../errors/file_operations_exception.dart';
import 'gallery_media_type.dart';
import 'platform_file.dart';

/// Result of [XueHuaFileOperations.retrieveLostCapture].
///
/// On Android the host Activity can be destroyed while the camera app is in
/// the foreground. The capture that finished in the meantime is cached
/// natively and returned here after the app restarts. Other
/// platforms never lose data, so they always return [LostCaptureResult.empty].
class LostCaptureResult {
  const LostCaptureResult({this.files = const [], this.type, this.exception});

  /// Nothing was recovered.
  static const LostCaptureResult empty = LostCaptureResult();

  /// Recovered capture (at most one file), empty when nothing was lost.
  final List<PlatformFile> files;

  /// Whether the recovered capture is a photo or a video.
  final GalleryMediaType? type;

  /// Set when the lost operation failed instead of producing [files].
  final FileOperationsException? exception;

  /// `true` when there is neither a recovered file nor an error.
  bool get isEmpty => files.isEmpty && exception == null;

  factory LostCaptureResult.fromMap(Map<Object?, Object?> map) {
    final rawFiles = map['files'];
    final files = rawFiles is List
        ? rawFiles
              .whereType<Map>()
              .map((e) => PlatformFile.fromMap(Map<Object?, Object?>.from(e)))
              .toList()
        : <PlatformFile>[];
    final errorCode = map['errorCode'] as String?;
    return LostCaptureResult(
      files: files,
      type: GalleryMediaType.fromWireName(map['type'] as String?),
      exception: errorCode == null
          ? null
          : FileOperationsException(
              ErrorCode.fromCode(errorCode),
              message: map['errorMessage'] as String? ?? errorCode,
            ),
    );
  }

  @override
  String toString() =>
      'LostCaptureResult(files: $files, type: $type, exception: $exception)';
}
