import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/errors/error_code.dart';
import 'src/errors/file_operations_exception.dart';
import 'src/models/directory_result.dart';
import 'src/models/file_type.dart';
import 'src/models/platform_file.dart';
import 'src/models/save_file_result.dart';
import 'xue_hua_file_operations_platform_interface.dart';

/// MethodChannel implementation of [XueHuaFileOperationsPlatform].
class MethodChannelXueHuaFileOperations extends XueHuaFileOperationsPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('xue_hua_file_operations');

  Map<String, Object?> _pickArgs({
    required bool withData,
    String? dialogTitle,
    required FileType type,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
    int? maxFiles,
  }) {
    return <String, Object?>{
      'withData': withData,
      'dialogTitle': ?dialogTitle,
      'type': type.wireName,
      'allowedExtensions': ?allowedExtensions,
      'allowedMimeTypes': ?allowedMimeTypes,
      'maxFiles': ?maxFiles,
    };
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw FileOperationsException(
        ErrorCode.fromCode(e.code),
        message: e.message ?? e.code,
        details: e.details,
      );
    }
  }

  @override
  Future<PlatformFile?> pickFile({
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
  }) async {
    final result = await _invoke<Map<Object?, Object?>>(
      'pickFile',
      _pickArgs(
        withData: withData,
        dialogTitle: dialogTitle,
        type: type,
        allowedExtensions: allowedExtensions,
        allowedMimeTypes: allowedMimeTypes,
      ),
    );
    if (result == null) return null;
    final file = result['file'];
    if (file is! Map) return null;
    return PlatformFile.fromMap(Map<Object?, Object?>.from(file));
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
    final result = await _invoke<Map<Object?, Object?>>(
      'pickFiles',
      _pickArgs(
        withData: withData,
        dialogTitle: dialogTitle,
        type: type,
        allowedExtensions: allowedExtensions,
        allowedMimeTypes: allowedMimeTypes,
        maxFiles: maxFiles,
      ),
    );
    if (result == null) return null;
    final files = result['files'];
    if (files is! List) return null;
    return files
        .whereType<Map>()
        .map((e) => PlatformFile.fromMap(Map<Object?, Object?>.from(e)))
        .toList();
  }

  @override
  Future<DirectoryResult?> pickDirectory({String? dialogTitle}) async {
    final result = await _invoke<Map<Object?, Object?>>(
      'pickDirectory',
      <String, Object?>{
        'dialogTitle': ?dialogTitle,
      },
    );
    if (result == null) return null;
    return DirectoryResult.fromMap(result);
  }

  @override
  Future<SaveFileResult?> saveFile({
    required String fileName,
    Uint8List? bytes,
    String? sourcePath,
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    final result = await _invoke<Map<Object?, Object?>>(
      'saveFile',
      <String, Object?>{
        'fileName': fileName,
        'bytes': ?bytes,
        'sourcePath': ?sourcePath,
        'allowedExtensions': ?allowedExtensions,
        'dialogTitle': ?dialogTitle,
      },
    );
    if (result == null) return null;
    return SaveFileResult.fromMap(result);
  }

  @override
  Future<void> openFile({String? path, String? identifier}) async {
    await _invoke<bool>(
      'openFile',
      <String, Object?>{
        'path': ?path,
        'identifier': ?identifier,
      },
    );
  }
}
