import 'dart:typed_data';

import 'src/errors/error_code.dart';
import 'src/errors/file_operations_exception.dart';
import 'src/models/camera_facing.dart';
import 'src/models/directory_result.dart';
import 'src/models/file_type.dart';
import 'src/models/gallery_media_type.dart';
import 'src/models/gallery_permission_status.dart';
import 'src/models/lost_capture_result.dart';
import 'src/models/media_picker_mode.dart';
import 'src/models/media_picker_options.dart';
import 'src/models/platform_file.dart';
import 'src/models/save_file_result.dart';
import 'src/models/save_to_gallery_result.dart';
import 'xue_hua_file_operations_platform_interface.dart';

export 'src/errors/error_code.dart';
export 'src/errors/file_operations_exception.dart';
export 'src/models/camera_facing.dart';
export 'src/models/directory_result.dart';
export 'src/models/file_type.dart';
export 'src/models/gallery_media_type.dart';
export 'src/models/gallery_permission_status.dart';
export 'src/models/lost_capture_result.dart';
export 'src/models/media_picker_mode.dart';
export 'src/models/media_picker_options.dart';
export 'src/models/media_picker_strings.dart';
export 'src/models/media_picker_theme.dart';
export 'src/models/platform_file.dart';
export 'src/models/save_file_result.dart';
export 'src/models/save_to_gallery_result.dart';

/// Cross-platform file pick / save / open singleton API.
class XueHuaFileOperations {
  XueHuaFileOperations._();

  static final XueHuaFileOperations instance = XueHuaFileOperations._();

  XueHuaFileOperationsPlatform get _platform =>
      XueHuaFileOperationsPlatform.instance;

  /// Validates [MediaPickerOptions] arguments before forwarding to native.
  /// 在转发到原生端之前校验 [MediaPickerOptions] 参数合法性。
  void _validateMediaPickerOptions(MediaPickerOptions? options) {
    if (options == null) return;
    if (options.crossAxisCount < 2 || options.crossAxisCount > 6) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'crossAxisCount must be between 2 and 6',
        details: {'crossAxisCount': options.crossAxisCount},
      );
    }
    final radius = options.theme?.sheetCornerRadius;
    if (radius != null && radius < 0) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'sheetCornerRadius cannot be negative',
        details: {'sheetCornerRadius': radius},
      );
    }
    final spacing = options.theme?.gridSpacing;
    if (spacing != null && spacing < 0) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'gridSpacing cannot be negative',
        details: {'gridSpacing': spacing},
      );
    }
  }

  /// Pick a single file. Returns `null` if the user cancels.
  /// 选择单个文件；用户取消时返回 `null`。
  ///
  /// Pass [mediaPickerOptions] with [MediaPickerMode.custom] to present the
  /// customizable native media picker when [type] is [FileType.image],
  /// [FileType.video], or [FileType.media] on Android and iOS.
  /// 在 Android 与 iOS 端选择图片/视频/媒体时，可传入 [mediaPickerOptions]
  /// （[MediaPickerMode.custom]）以展示可自定义样式的原生媒体选择器。
  Future<PlatformFile?> pickFile({
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
    MediaPickerOptions? mediaPickerOptions,
  }) {
    _validateMediaPickerOptions(mediaPickerOptions);
    return _platform.pickFile(
      withData: withData,
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
      allowedMimeTypes: allowedMimeTypes,
      mediaPickerOptions: mediaPickerOptions,
    );
  }

  /// Pick multiple files. Returns `null` if the user cancels.
  /// 选择多个文件；用户取消时返回 `null`。
  ///
  /// [maxFiles] defaults to `null` (unlimited). If set and the user selects
  /// more files, throws [FileOperationsException] with [ErrorCode.tooManyFiles].
  /// Pass [mediaPickerOptions] with [MediaPickerMode.custom] to present the
  /// customizable native media picker on Android and iOS.
  /// [maxFiles] 默认为 `null`（不限数量）。在 Android 与 iOS 端可传入
  /// [mediaPickerOptions] 启用可自定义样式的原生媒体选择器。
  Future<List<PlatformFile>?> pickFiles({
    int? maxFiles,
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
    MediaPickerOptions? mediaPickerOptions,
  }) {
    if (maxFiles != null && maxFiles < 1) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'maxFiles must be >= 1 when provided',
        details: {'maxFiles': maxFiles},
      );
    }
    _validateMediaPickerOptions(mediaPickerOptions);
    return _platform.pickFiles(
      maxFiles: maxFiles,
      withData: withData,
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
      allowedMimeTypes: allowedMimeTypes,
      mediaPickerOptions: mediaPickerOptions,
    );
  }

  /// Take a photo with the system camera. Returns `null` if the user cancels.
  ///
  /// [preferredCamera] is a hint for the front / rear camera. [maxWidth] /
  /// [maxHeight] downscale the photo (keeping its aspect ratio) so it fits
  /// inside the given size; [imageQuality] (0-100) sets the JPEG compression.
  /// Without any of them the original capture is returned untouched.
  ///
  /// Android needs the host Activity to extend `FlutterFragmentActivity` and
  /// asks for the camera permission when it is declared in the manifest; a
  /// refusal throws [FileOperationsException] with
  /// [ErrorCode.permissionDenied]. A device without a camera app throws
  /// [ErrorCode.unsupported]. On iOS the camera needs
  /// `NSCameraUsageDescription`. On Web it opens the browser capture UI
  /// (mobile browsers only; desktop browsers show a file chooser).
  ///
  /// macOS, Windows and Linux open a native preview window with the
  /// computer's camera (AVFoundation, Media Foundation and GStreamer
  /// respectively); [preferredCamera] picks the built-in (front) or an
  /// external (rear) camera. A computer without a camera, or a Linux build
  /// without GStreamer, throws [ErrorCode.unsupported]; blocked camera access
  /// throws [ErrorCode.permissionDenied]. macOS needs the camera entitlement
  /// and `NSCameraUsageDescription` (see the README).
  Future<PlatformFile?> capturePhoto({
    CameraFacing preferredCamera = CameraFacing.rear,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    bool withData = false,
  }) {
    if (maxWidth != null && maxWidth < 0) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'maxWidth cannot be negative',
        details: {'maxWidth': maxWidth},
      );
    }
    if (maxHeight != null && maxHeight < 0) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'maxHeight cannot be negative',
        details: {'maxHeight': maxHeight},
      );
    }
    if (imageQuality != null && (imageQuality < 0 || imageQuality > 100)) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'imageQuality must be between 0 and 100',
        details: {'imageQuality': imageQuality},
      );
    }
    return _platform.capturePhoto(
      preferredCamera: preferredCamera,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
      withData: withData,
    );
  }

  /// Record a video with the system camera. Returns `null` if the user
  /// cancels.
  ///
  /// [maxDuration] caps the recording length (best effort: some Android
  /// camera apps ignore it and browsers cannot enforce it).
  /// [preferredCamera] is a hint for the front / rear camera. Permission and
  /// platform notes are the same as for [capturePhoto]; iOS additionally
  /// needs `NSMicrophoneUsageDescription`.
  Future<PlatformFile?> captureVideo({
    CameraFacing preferredCamera = CameraFacing.rear,
    Duration? maxDuration,
    bool withData = false,
  }) {
    if (maxDuration != null && maxDuration.isNegative) {
      throw FileOperationsException(
        ErrorCode.invalidArgs,
        message: 'maxDuration cannot be negative',
        details: {'maxDuration': maxDuration.inSeconds},
      );
    }
    return _platform.captureVideo(
      preferredCamera: preferredCamera,
      maxDuration: maxDuration,
      withData: withData,
    );
  }

  /// Recover a capture lost because Android destroyed the host Activity while
  /// the camera app was open.
  ///
  /// Call once on startup. Always returns [LostCaptureResult.empty] on
  /// platforms other than Android.
  Future<LostCaptureResult> retrieveLostCapture() {
    return _platform.retrieveLostCapture();
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
  /// [albumName]. On macOS this is ignored (PhotoKit is always `readWrite`).
  /// On Web this always returns [GalleryPermissionStatus.granted].
  Future<GalleryPermissionStatus> galleryPermissionStatus({
    bool forAlbum = false,
  }) {
    return _platform.galleryPermissionStatus(forAlbum: forAlbum);
  }

  /// Request gallery permission, showing a system prompt if undetermined.
  ///
  /// Returns the new [GalleryPermissionStatus]. Denial is a status, not an
  /// exception. Pass [forAlbum] `true` when you need read access to create or
  /// look up a custom album. On macOS this is ignored (PhotoKit is always
  /// `readWrite`). On Web this always returns
  /// [GalleryPermissionStatus.granted].
  ///
  /// On iOS / macOS the system dialog appears only while PhotoKit status is
  /// `notDetermined`. If the result is [GalleryPermissionStatus.permanentlyDenied]
  /// or [GalleryPermissionStatus.restricted], call [openAppSettings] so the
  /// user can change Photos access.
  ///
  /// On macOS, launching via Cursor/VS Code can silently deny Photos (TCC
  /// attributes the request to the IDE). Prefer the system Terminal or opening
  /// the built `.app`.
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
