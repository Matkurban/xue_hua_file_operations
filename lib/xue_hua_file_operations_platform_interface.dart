import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/models/directory_result.dart';
import 'src/models/file_type.dart';
import 'src/models/platform_file.dart';
import 'src/models/save_file_result.dart';
import 'xue_hua_file_operations_method_channel.dart';

abstract class XueHuaFileOperationsPlatform extends PlatformInterface {
  XueHuaFileOperationsPlatform() : super(token: _token);

  static final Object _token = Object();

  static XueHuaFileOperationsPlatform _instance =
      MethodChannelXueHuaFileOperations();

  static XueHuaFileOperationsPlatform get instance => _instance;

  static set instance(XueHuaFileOperationsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<PlatformFile?> pickFile({
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
  }) {
    throw UnimplementedError('pickFile() has not been implemented.');
  }

  Future<List<PlatformFile>?> pickFiles({
    int? maxFiles,
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
  }) {
    throw UnimplementedError('pickFiles() has not been implemented.');
  }

  Future<DirectoryResult?> pickDirectory({String? dialogTitle}) {
    throw UnimplementedError('pickDirectory() has not been implemented.');
  }

  Future<SaveFileResult?> saveFile({
    required String fileName,
    Uint8List? bytes,
    String? sourcePath,
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) {
    throw UnimplementedError('saveFile() has not been implemented.');
  }

  Future<void> openFile({String? path, String? identifier}) {
    throw UnimplementedError('openFile() has not been implemented.');
  }
}
