import 'dart:typed_data';

import 'src/errors/error_code.dart';
import 'src/errors/file_operations_exception.dart';
import 'src/models/directory_result.dart';
import 'src/models/file_type.dart';
import 'src/models/gallery_media_type.dart';
import 'src/models/gallery_permission_status.dart';
import 'src/models/platform_file.dart';
import 'src/models/save_file_result.dart';
import 'src/models/save_to_gallery_result.dart';
import 'xue_hua_file_operations_platform_interface.dart';

export 'src/errors/error_code.dart';
export 'src/errors/file_operations_exception.dart';
export 'src/models/directory_result.dart';
export 'src/models/file_type.dart';
export 'src/models/gallery_media_type.dart';
export 'src/models/gallery_permission_status.dart';
export 'src/models/platform_file.dart';
export 'src/models/save_file_result.dart';
export 'src/models/save_to_gallery_result.dart';

/// Cross-platform file pick / save / open singleton API.
class XueHuaFileOperations {
  XueHuaFileOperations._();

  static final XueHuaFileOperations instance = XueHuaFileOperations._();

  XueHuaFileOperationsPlatform get _platform =>
      XueHuaFileOperationsPlatform.instance;

  /// Pick a single file. Returns `null` if the user cancels.
  Future<PlatformFile?> pickFile({
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
  }) {
    return _platform.pickFile(
      withData: withData,
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
      allowedMimeTypes: allowedMimeTypes,
    );
  }

  /// Pick multiple files. Returns `null` if the user cancels.
  ///
  /// [maxFiles] defaults to `null` (unlimited). If set and the user selects
  /// more files, throws [FileOperationsException] with [ErrorCode.tooManyFiles].
  Future<List<PlatformFile>?> pickFiles({
    int? maxFiles,
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
  }) {
    if (maxFiles != null && maxFiles < 1) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'maxFiles must be >= 1 when provided',
        details: {'maxFiles': maxFiles},
      );
    }
    return _platform.pickFiles(
      maxFiles: maxFiles,
      withData: withData,
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
      allowedMimeTypes: allowedMimeTypes,
    );
  }

  /// Pick a directory. Returns `null` if the user cancels.
  Future<DirectoryResult?> pickDirectory({String? dialogTitle}) {
    return _platform.pickDirectory(dialogTitle: dialogTitle);
  }

  /// Show a save-as dialog and write [bytes] or copy from [sourcePath].
  ///
  /// At least one of [bytes] / [sourcePath] is required. Returns `null` on cancel.
  Future<SaveFileResult?> saveFile({
    required String fileName,
    Uint8List? bytes,
    String? sourcePath,
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) {
    if (bytes == null && (sourcePath == null || sourcePath.isEmpty)) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'Either bytes or sourcePath must be provided',
      );
    }
    return _platform.saveFile(
      fileName: fileName,
      bytes: bytes,
      sourcePath: sourcePath,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
  }

  /// Save an image or video to the system gallery / Pictures folder.
  ///
  /// At least one of [bytes] / [sourcePath] is required. [type] is inferred
  /// from [fileName] (or [sourcePath]) when omitted. On Web this triggers a
  /// browser download (`bytes` required).
  Future<SaveToGalleryResult> saveToGallery({
    required String fileName,
    Uint8List? bytes,
    String? sourcePath,
    GalleryMediaType? type,
    String? albumName,
  }) {
    if (bytes == null && (sourcePath == null || sourcePath.isEmpty)) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'Either bytes or sourcePath must be provided',
      );
    }
    final resolvedType =
        type ??
        GalleryMediaType.fromFileName(fileName) ??
        (sourcePath != null ? GalleryMediaType.fromFileName(sourcePath) : null);
    if (resolvedType == null) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message:
            'Unable to infer image/video type from fileName; '
            'pass GalleryMediaType or use a media extension',
        details: {'fileName': fileName},
      );
    }
    return _platform.saveToGallery(
      fileName: fileName,
      bytes: bytes,
      sourcePath: sourcePath,
      type: resolvedType,
      albumName: albumName,
    );
  }

  /// Current gallery permission without showing a system prompt.
  ///
  /// Pass [forAlbum] `true` when you will call [saveToGallery] with an
  /// [albumName]. On Web this always returns [GalleryPermissionStatus.granted].
  Future<GalleryPermissionStatus> galleryPermissionStatus({
    bool forAlbum = false,
  }) {
    return _platform.galleryPermissionStatus(forAlbum: forAlbum);
  }

  /// Request gallery permission, showing a system prompt if undetermined.
  ///
  /// Returns the new [GalleryPermissionStatus]. Denial is a status, not an
  /// exception. Pass [forAlbum] `true` when you need read access to create or
  /// look up a custom album. On Web this always returns
  /// [GalleryPermissionStatus.granted].
  ///
  /// On iOS / macOS the system dialog appears only while PhotoKit status is
  /// `notDetermined`. If the result is [GalleryPermissionStatus.permanentlyDenied]
  /// or [GalleryPermissionStatus.restricted], call [openAppSettings] so the
  /// user can change Photos access.
  Future<GalleryPermissionStatus> requestGalleryPermission({
    bool forAlbum = false,
  }) {
    return _platform.requestGalleryPermission(forAlbum: forAlbum);
  }

  /// Open the OS settings UI for this app (or Photos privacy on macOS).
  ///
  /// Use after [GalleryPermissionStatus.permanentlyDenied] or
  /// [GalleryPermissionStatus.restricted]. Does not request permission itself.
  /// On Web this is a no-op. On Linux there is no app Photos toggle; this
  /// succeeds without opening a pane.
  Future<void> openAppSettings() {
    return _platform.openAppSettings();
  }

  /// Open [path] or [identifier] with the system default application.
  Future<void> openFile({String? path, String? identifier}) {
    if ((path == null || path.isEmpty) &&
        (identifier == null || identifier.isEmpty)) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'Either path or identifier must be provided',
      );
    }
    return _platform.openFile(path: path, identifier: identifier);
  }
}
