import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/errors/error_code.dart';
import 'src/errors/file_operations_exception.dart';
import 'src/models/camera_facing.dart';
import 'src/models/directory_result.dart';
import 'src/models/file_type.dart';
import 'src/models/gallery_media_type.dart';
import 'src/models/gallery_permission_status.dart';
import 'src/models/lost_capture_result.dart';
import 'src/models/platform_file.dart';
import 'src/models/save_file_result.dart';
import 'src/models/save_to_gallery_result.dart';
import 'src/utils/media_resize.dart';
import 'xue_hua_file_operations_platform_interface.dart';

/// Web implementation using HTML file input / Blob download.
class XueHuaFileOperationsWeb extends XueHuaFileOperationsPlatform {
  XueHuaFileOperationsWeb();

  static void registerWith(Registrar registrar) {
    XueHuaFileOperationsPlatform.instance = XueHuaFileOperationsWeb();
  }

  String _acceptFor({
    required FileType type,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
  }) {
    final parts = <String>[];
    if (allowedMimeTypes != null) {
      parts.addAll(allowedMimeTypes);
    }
    if (allowedExtensions != null) {
      parts.addAll(allowedExtensions.map((e) => e.startsWith('.') ? e : '.$e'));
    }
    if (parts.isNotEmpty) return parts.join(',');

    switch (type) {
      case FileType.media:
        return 'image/*,video/*';
      case FileType.image:
        return 'image/*';
      case FileType.video:
        return 'video/*';
      case FileType.audio:
        return 'audio/*';
      case FileType.custom:
      case FileType.any:
        return '';
    }
  }

  Future<List<web.File>> _pickHtmlFiles({
    required bool multiple,
    required bool directory,
    required String accept,
    String? capture,
  }) {
    final completer = Completer<List<web.File>>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..multiple = multiple;

    if (accept.isNotEmpty) {
      input.accept = accept;
    }
    if (capture != null) {
      input.setAttribute('capture', capture);
    }
    if (directory) {
      input.setAttribute('webkitdirectory', '');
      input.setAttribute('directory', '');
    }

    var settled = false;
    void finish(List<web.File> files) {
      if (settled) return;
      settled = true;
      input.remove();
      if (!completer.isCompleted) {
        completer.complete(files);
      }
    }

    input.addEventListener(
      'change',
      (web.Event event) {
        final list = input.files;
        if (list == null || list.length == 0) {
          finish(const []);
          return;
        }
        final files = <web.File>[];
        for (var i = 0; i < list.length; i++) {
          files.add(list.item(i)!);
        }
        finish(files);
      }.toJS,
    );

    input.addEventListener(
      'cancel',
      (web.Event event) {
        finish(const []);
      }.toJS,
    );

    web.document.body?.append(input);
    input.click();
    return completer.future;
  }

  Future<PlatformFile> _toPlatformFile(web.File file) async {
    final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    final identifier = web.URL.createObjectURL(file);
    return PlatformFile(
      name: file.name,
      size: file.size,
      path: null,
      bytes: bytes,
      identifier: identifier,
    );
  }

  Future<web.HTMLImageElement> _loadImage(String url) {
    final completer = Completer<web.HTMLImageElement>();
    final image = web.HTMLImageElement();
    image.addEventListener(
      'load',
      (web.Event _) {
        if (!completer.isCompleted) completer.complete(image);
      }.toJS,
    );
    image.addEventListener(
      'error',
      (web.Event _) {
        if (!completer.isCompleted) {
          completer.completeError('Unable to decode image');
        }
      }.toJS,
    );
    image.src = url;
    return completer.future;
  }

  /// Re-encodes [file] on a canvas so it honours the size / quality limits.
  ///
  /// Falls back to the original bytes when the image cannot be decoded and
  /// leaves GIFs untouched (a canvas would drop the animation).
  Future<PlatformFile> _toCapturedPhoto(
    web.File file, {
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    if (file.type == 'image/gif' ||
        !mediaResizeNeeded(maxWidth, maxHeight, imageQuality)) {
      return _toPlatformFile(file);
    }
    final url = web.URL.createObjectURL(file);
    try {
      final image = await _loadImage(url);
      final (width, height) = downScaledSize(
        image.naturalWidth,
        image.naturalHeight,
        maxWidth,
        maxHeight,
      );
      final canvas = web.HTMLCanvasElement()
        ..width = width
        ..height = height;
      canvas.context2D.drawImage(
        image,
        0,
        0,
        width.toDouble(),
        height.toDouble(),
      );
      final completer = Completer<web.Blob?>();
      canvas.toBlob(
        (web.Blob? blob) {
          completer.complete(blob);
        }.toJS,
        file.type.isEmpty ? 'image/jpeg' : file.type,
        ((imageQuality ?? 100) / 100).toJS,
      );
      final blob = await completer.future;
      if (blob == null) return await _toPlatformFile(file);
      final buffer = await blob.arrayBuffer().toDart;
      return PlatformFile(
        name: file.name,
        size: blob.size,
        path: null,
        bytes: buffer.toDart.asUint8List(),
        identifier: web.URL.createObjectURL(blob),
      );
    } catch (_) {
      return _toPlatformFile(file);
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }

  /// HTML Media Capture: `user` = front, `environment` = rear camera.
  /// Only mobile browsers honour it; desktop browsers show a file chooser.
  String _captureAttribute(CameraFacing preferredCamera) =>
      preferredCamera == CameraFacing.front ? 'user' : 'environment';

  @override
  Future<PlatformFile?> capturePhoto({
    CameraFacing preferredCamera = CameraFacing.rear,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    bool withData = false,
  }) async {
    final files = await _pickHtmlFiles(
      multiple: false,
      directory: false,
      accept: 'image/*',
      capture: _captureAttribute(preferredCamera),
    );
    if (files.isEmpty) return null;
    return _toCapturedPhoto(
      files.first,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
  }

  /// Browsers cannot cap the recording length, so `maxDuration` is ignored.
  @override
  Future<PlatformFile?> captureVideo({
    CameraFacing preferredCamera = CameraFacing.rear,
    Duration? maxDuration,
    bool withData = false,
  }) async {
    final files = await _pickHtmlFiles(
      multiple: false,
      directory: false,
      accept: 'video/*',
      capture: _captureAttribute(preferredCamera),
    );
    if (files.isEmpty) return null;
    return _toPlatformFile(files.first);
  }

  /// A browser page never loses a pending capture, so nothing to recover.
  @override
  Future<LostCaptureResult> retrieveLostCapture() async =>
      LostCaptureResult.empty;

  @override
  Future<PlatformFile?> pickFile({
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
  }) async {
    final files = await _pickHtmlFiles(
      multiple: false,
      directory: false,
      accept: _acceptFor(
        type: type,
        allowedExtensions: allowedExtensions,
        allowedMimeTypes: allowedMimeTypes,
      ),
    );
    if (files.isEmpty) return null;
    return _toPlatformFile(files.first);
  }

  @override
  Future<List<PlatformFile>?> pickFiles({
    int? maxFiles,
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
  }) async {
    final files = await _pickHtmlFiles(
      multiple: true,
      directory: false,
      accept: _acceptFor(
        type: type,
        allowedExtensions: allowedExtensions,
        allowedMimeTypes: allowedMimeTypes,
      ),
    );
    if (files.isEmpty) return null;
    if (maxFiles != null && files.length > maxFiles) {
      throw FileOperationsException(
        ErrorCode.tooManyFiles,
        message: 'Selected ${files.length} files but maxFiles is $maxFiles',
        details: {'selected': files.length, 'maxFiles': maxFiles},
      );
    }
    final result = <PlatformFile>[];
    for (final file in files) {
      result.add(await _toPlatformFile(file));
    }
    return result;
  }

  @override
  Future<DirectoryResult?> pickDirectory({String? dialogTitle}) async {
    final files = await _pickHtmlFiles(
      multiple: true,
      directory: true,
      accept: '',
    );
    if (files.isEmpty) return null;

    final relative = files.first.webkitRelativePath;
    final name = relative.contains('/')
        ? relative.split('/').first
        : 'selected';
    return DirectoryResult(path: name, name: name, identifier: name);
  }

  void _downloadBytes(String fileName, Uint8List bytes, {String? mime}) {
    final blob = mime == null || mime.isEmpty
        ? web.Blob([bytes.toJS].toJS)
        : web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }

  String _mimeForGallery(String fileName, GalleryMediaType type) {
    final dot = fileName.lastIndexOf('.');
    if (dot >= 0 && dot < fileName.length - 1) {
      switch (fileName.substring(dot + 1).toLowerCase()) {
        case 'jpg':
        case 'jpeg':
          return 'image/jpeg';
        case 'png':
          return 'image/png';
        case 'gif':
          return 'image/gif';
        case 'webp':
          return 'image/webp';
        case 'bmp':
          return 'image/bmp';
        case 'tif':
        case 'tiff':
          return 'image/tiff';
        case 'heic':
          return 'image/heic';
        case 'heif':
          return 'image/heif';
        case 'avif':
          return 'image/avif';
        case 'ico':
          return 'image/x-icon';
        case 'mp4':
          return 'video/mp4';
        case 'mov':
        case 'm4v':
          return 'video/quicktime';
        case 'webm':
          return 'video/webm';
        case 'avi':
          return 'video/x-msvideo';
        case 'mkv':
          return 'video/x-matroska';
        case 'mpeg':
        case 'mpg':
          return 'video/mpeg';
        case '3gp':
          return 'video/3gpp';
        case '3g2':
          return 'video/3gpp2';
      }
    }
    return type == GalleryMediaType.video ? 'video/mp4' : 'image/jpeg';
  }

  @override
  Future<SaveFileResult?> saveFile({
    required String fileName,
    Uint8List? bytes,
    String? sourcePath,
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    if (bytes == null) {
      throw FileOperationsException(
        ErrorCode.unsupported,
        message: 'Web saveFile requires bytes; sourcePath is not supported',
      );
    }

    _downloadBytes(fileName, bytes);
    return SaveFileResult(name: fileName, path: null);
  }

  @override
  Future<SaveToGalleryResult> saveToGallery({
    required String fileName,
    Uint8List? bytes,
    String? sourcePath,
    required GalleryMediaType type,
    String? albumName,
  }) async {
    if (bytes == null) {
      throw FileOperationsException(
        ErrorCode.unsupported,
        message:
            'Web saveToGallery requires bytes; sourcePath is not supported',
      );
    }

    _downloadBytes(fileName, bytes, mime: _mimeForGallery(fileName, type));
    return SaveToGalleryResult(name: fileName);
  }

  @override
  Future<GalleryPermissionStatus> galleryPermissionStatus({
    bool forAlbum = false,
  }) async {
    return GalleryPermissionStatus.granted;
  }

  @override
  Future<GalleryPermissionStatus> requestGalleryPermission({
    bool forAlbum = false,
  }) async {
    return GalleryPermissionStatus.granted;
  }

  @override
  Future<void> openFile({String? path, String? identifier}) async {
    if (identifier != null && identifier.isNotEmpty) {
      web.window.open(identifier, '_blank');
      return;
    }
    throw FileOperationsException(
      ErrorCode.unsupported,
      message:
          'Opening local paths is not supported on Web; pass identifier (object URL)',
    );
  }

  @override
  Future<void> openAppSettings() async {}
}
