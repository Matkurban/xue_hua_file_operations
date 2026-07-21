import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/errors/error_code.dart';
import 'src/errors/file_operations_exception.dart';
import 'src/models/directory_result.dart';
import 'src/models/file_type.dart';
import 'src/models/platform_file.dart';
import 'src/models/save_file_result.dart';
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
  }) {
    final completer = Completer<List<web.File>>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..multiple = multiple;

    if (accept.isNotEmpty) {
      input.accept = accept;
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

    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);

    return SaveFileResult(name: fileName, path: null);
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
}
