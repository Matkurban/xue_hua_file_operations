import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations_method_channel.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations_platform_interface.dart';

class MockXueHuaFileOperationsPlatform
    with MockPlatformInterfaceMixin
    implements XueHuaFileOperationsPlatform {
  @override
  Future<PlatformFile?> pickFile({
    bool withData = false,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    List<String>? allowedMimeTypes,
  }) async {
    return PlatformFile(
      name: 'a.txt',
      size: 3,
      path: '/tmp/a.txt',
      bytes: withData ? Uint8List.fromList([1, 2, 3]) : null,
      identifier: 'file:///tmp/a.txt',
    );
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
    return [
      const PlatformFile(name: 'a.txt', size: 1, path: '/tmp/a.txt'),
      const PlatformFile(name: 'b.txt', size: 1, path: '/tmp/b.txt'),
    ];
  }

  @override
  Future<DirectoryResult?> pickDirectory({String? dialogTitle}) async {
    return const DirectoryResult(path: '/tmp', name: 'tmp');
  }

  @override
  Future<SaveFileResult?> saveFile({
    required String fileName,
    Uint8List? bytes,
    String? sourcePath,
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    return SaveFileResult(name: fileName, path: '/tmp/$fileName');
  }

  @override
  Future<void> openFile({String? path, String? identifier}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final XueHuaFileOperationsPlatform initialPlatform =
      XueHuaFileOperationsPlatform.instance;

  test('$MethodChannelXueHuaFileOperations is the default instance', () {
    expect(initialPlatform, isA<MethodChannelXueHuaFileOperations>());
  });

  test('singleton instance', () {
    expect(
      identical(XueHuaFileOperations.instance, XueHuaFileOperations.instance),
      isTrue,
    );
  });

  test('PlatformFile.fromMap / hasBytes', () {
    final file = PlatformFile.fromMap({
      'name': 'x.bin',
      'size': 2,
      'path': '/x',
      'bytes': Uint8List.fromList([9, 8]),
      'identifier': 'id',
    });
    expect(file.name, 'x.bin');
    expect(file.hasBytes, isTrue);

    final empty = PlatformFile.fromMap({
      'name': 'empty.bin',
      'size': 0,
      'bytes': Uint8List(0),
    });
    expect(empty.hasBytes, isTrue);

    final metaOnly = PlatformFile.fromMap({
      'name': 'meta.bin',
      'size': 10,
      'bytes': null,
    });
    expect(metaOnly.hasBytes, isFalse);
  });

  test('pickFile delegates to platform', () async {
    final fake = MockXueHuaFileOperationsPlatform();
    XueHuaFileOperationsPlatform.instance = fake;

    final file = await XueHuaFileOperations.instance.pickFile(withData: true);
    expect(file?.name, 'a.txt');
    expect(file?.hasBytes, isTrue);
  });

  test('pickFiles rejects invalid maxFiles', () async {
    expect(
      () => XueHuaFileOperations.instance.pickFiles(maxFiles: 0),
      throwsA(isA<FileOperationsException>()),
    );
  });

  test('saveFile requires bytes or sourcePath', () async {
    expect(
      () => XueHuaFileOperations.instance.saveFile(fileName: 'a.txt'),
      throwsA(isA<FileOperationsException>()),
    );
  });
}
