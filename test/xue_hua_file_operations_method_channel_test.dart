import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_file_operations/src/errors/error_code.dart';
import 'package:xue_hua_file_operations/src/errors/file_operations_exception.dart';
import 'package:xue_hua_file_operations/src/models/file_type.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelXueHuaFileOperations();
  const channel = MethodChannel('xue_hua_file_operations');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('pickFile encodes args and decodes map', () async {
    late MethodCall captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          captured = methodCall;
          return {
            'file': {
              'name': 'a.txt',
              'size': 1,
              'path': '/tmp/a.txt',
              'bytes': null,
              'identifier': 'file:///tmp/a.txt',
            },
          };
        });

    final file = await platform.pickFile(
      withData: true,
      dialogTitle: 'Pick one',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      allowedMimeTypes: const ['text/plain'],
    );

    expect(captured.method, 'pickFile');
    final args = captured.arguments as Map;
    expect(args['withData'], isTrue);
    expect(args['dialogTitle'], 'Pick one');
    expect(args['type'], 'custom');
    expect(args['allowedExtensions'], ['txt']);
    expect(args['allowedMimeTypes'], ['text/plain']);
    expect(args.containsKey('maxFiles'), isFalse);

    expect(file?.name, 'a.txt');
    expect(file?.path, '/tmp/a.txt');
    expect(file?.identifier, 'file:///tmp/a.txt');
  });

  test('pickFiles encodes maxFiles and decodes list', () async {
    late MethodCall captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          captured = methodCall;
          return {
            'files': [
              {
                'name': 'a.txt',
                'size': 1,
                'path': '/tmp/a.txt',
                'bytes': null,
                'identifier': 'id-a',
              },
              {
                'name': 'b.txt',
                'size': 2,
                'path': '/tmp/b.txt',
                'bytes': Uint8List.fromList([1, 2]),
                'identifier': 'id-b',
              },
            ],
          };
        });

    final files = await platform.pickFiles(maxFiles: 3, withData: false);
    expect(captured.method, 'pickFiles');
    expect((captured.arguments as Map)['maxFiles'], 3);
    expect(files, hasLength(2));
    expect(files?[0].name, 'a.txt');
    expect(files?[1].hasBytes, isTrue);
  });

  test('pickFiles maps PlatformException to FileOperationsException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          throw PlatformException(
            code: 'too_many_files',
            message: 'too many',
            details: {'selected': 5, 'maxFiles': 2},
          );
        });

    expect(
      () => platform.pickFiles(maxFiles: 2),
      throwsA(
        isA<FileOperationsException>().having(
          (e) => e.code,
          'code',
          ErrorCode.tooManyFiles,
        ),
      ),
    );
  });

  test('pickDirectory encodes and decodes', () async {
    late MethodCall captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          captured = methodCall;
          return {
            'path': '/tmp/dir',
            'name': 'dir',
            'identifier': 'file:///tmp/dir',
          };
        });

    final dir = await platform.pickDirectory(dialogTitle: 'Folders');
    expect(captured.method, 'pickDirectory');
    expect((captured.arguments as Map)['dialogTitle'], 'Folders');
    expect(dir?.path, '/tmp/dir');
    expect(dir?.name, 'dir');
    expect(dir?.identifier, 'file:///tmp/dir');
  });

  test('saveFile encodes prefer-bytes args and decodes', () async {
    late MethodCall captured;
    final bytes = Uint8List.fromList([9, 8, 7]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          captured = methodCall;
          return {'path': '/tmp/out.bin', 'name': 'out.bin'};
        });

    final saved = await platform.saveFile(
      fileName: 'out.bin',
      bytes: bytes,
      sourcePath: '/tmp/ignored.bin',
      allowedExtensions: const ['bin'],
      dialogTitle: 'Save',
    );

    expect(captured.method, 'saveFile');
    final args = captured.arguments as Map;
    expect(args['fileName'], 'out.bin');
    expect(args['bytes'], bytes);
    expect(args['sourcePath'], '/tmp/ignored.bin');
    expect(args['allowedExtensions'], ['bin']);
    expect(args['dialogTitle'], 'Save');
    expect(saved?.name, 'out.bin');
    expect(saved?.path, '/tmp/out.bin');
  });

  test('openFile encodes path and identifier', () async {
    late MethodCall captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          captured = methodCall;
          return true;
        });

    await platform.openFile(path: '/tmp/a.txt', identifier: 'id-a');
    expect(captured.method, 'openFile');
    final args = captured.arguments as Map;
    expect(args['path'], '/tmp/a.txt');
    expect(args['identifier'], 'id-a');
  });

  test('cancel returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return null;
        });

    expect(await platform.pickFile(), isNull);
    expect(await platform.pickFiles(), isNull);
    expect(await platform.pickDirectory(), isNull);
    expect(await platform.saveFile(fileName: 'x', bytes: Uint8List(0)), isNull);
  });
}
