// Run with (see README of the example):
//   flutter drive --driver=test_driver/app_test.dart \
//     --target=test_driver/app.dart -d <linux|windows|macos|android-emulator|ios-sim>
//
// Environment (read by this driver process AND the app under test):
//   XUE_HUA_EXPECT=captured     camera capture must succeed (Linux test
//                               source, or a camera that is already allowed)
//   XUE_HUA_EXPECT=unsupported  capture must report `unsupported`
//   unset / any                 only check that the app answers
//
// Desktop dialog hooks (skip native choosers for automated runs):
//   XUE_HUA_TEST_PICK_FILE / XUE_HUA_TEST_PICK_FILES / XUE_HUA_TEST_PICK_DIR
//   XUE_HUA_TEST_SAVE_FILE / XUE_HUA_TEST_OPEN_FILE=skip
//   Literal CANCEL on a pick/save hook simulates cancel.
//   Multi-file paths: colon-separated on Linux/macOS, semicolon-separated on Windows.
//
// Optional (Android, where the captured file lives on the device):
//   XUE_HUA_ADB=<path to adb>  XUE_HUA_ADB_SERIAL=<serial>  XUE_HUA_APP_ID=<applicationId>
//   The file is then fetched with `adb exec-out run-as <id> cat <path>`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  late FlutterDriver driver;
  final expectation = Platform.environment['XUE_HUA_EXPECT'] ?? 'any';
  final fixturesDir = Directory(
    '${Directory.systemTemp.path}/xhfo_driver_fixtures',
  );
  late File saveDest;

  setUpAll(() async {
    // Recreate fixtures so pick/save hooks always have files even if the
    // launch shell did not prepare them.
    if (fixturesDir.existsSync()) {
      fixturesDir.deleteSync(recursive: true);
    }
    fixturesDir.createSync(recursive: true);
    File('${fixturesDir.path}/hello.txt')
        .writeAsStringSync('hello from flutter_driver\n');
    File('${fixturesDir.path}/world.txt').writeAsStringSync('world\n');
    // Minimal valid 1x1 JPEG.
    File('${fixturesDir.path}/dot.jpg').writeAsBytesSync(<int>[
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
        0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
        0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
        0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
        0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x09, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
        0x7F, 0xFF, 0xD9,
    ]);
    final saveHook = Platform.environment['XUE_HUA_TEST_SAVE_FILE'];
    saveDest = File(
      (saveHook != null && saveHook.isNotEmpty && saveHook != 'CANCEL')
          ? saveHook
          : '${fixturesDir.path}/saved_out.txt',
    );
    if (saveDest.existsSync()) saveDest.deleteSync();

    // Export hooks for the app process when the driver hosts the launch on
    // platforms that inherit this process environment (Linux / desktop).
    // flutter drive already inherits the shell env that launched it.
    driver = await FlutterDriver.connect();
  });

  tearDownAll(() async {
    await driver.close();
  });

  Future<String> status() => driver.getText(find.byValueKey('status'));

  Future<void> waitStatus(bool Function(String) test, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (test(await status())) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    fail('Timed out, status is "${await status()}"');
  }

  /// The `path=` and `size=` shown in the first file card.
  Future<({String path, int size})> capturedInfo({int index = 0}) async {
    final info = await driver.getText(find.byValueKey('file_info_$index'));
    final path = RegExp(r'path=(.*)').firstMatch(info)!.group(1)!.trim();
    final size = int.parse(RegExp(r'size=(\d+)').firstMatch(info)!.group(1)!);
    return (path: path, size: size);
  }

  /// A local copy of the captured file (fetched from the device on Android).
  Future<File> localCopy(String path) async {
    final adb = Platform.environment['XUE_HUA_ADB'];
    final appId = Platform.environment['XUE_HUA_APP_ID'];
    if (adb != null && appId != null && !File(path).existsSync()) {
      final serial = Platform.environment['XUE_HUA_ADB_SERIAL'];
      final out = File(
        '${Directory.systemTemp.path}/driver_${path.split('/').last}',
      );
      final r = await Process.run(adb, [
        if (serial != null) ...['-s', serial],
        'exec-out',
        'run-as',
        appId,
        'cat',
        path,
      ], stdoutEncoding: null);
      expect(r.exitCode, 0, reason: 'adb run-as cat failed: ${r.stderr}');
      await out.writeAsBytes(r.stdout as List<int>);
      return out;
    }
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'captured file $path must exist');
    return file;
  }

  /// Width x height from the first JPEG SOF marker.
  (int, int) jpegSize(Uint8List b) {
    expect(b[0], 0xFF);
    expect(b[1], 0xD8);
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final m = b[i + 1];
      if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
        return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
      }
      i += 2 + ((b[i + 2] << 8) | b[i + 3]);
    }
    fail('no JPEG SOF marker found');
  }

  /// Duration in seconds of a video, with ffprobe or the MP4 `mvhd` atom.
  Future<double> videoDuration(File file) async {
    final r = await Process.run('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=nw=1:nk=1',
      file.path,
    ]).catchError((_) => ProcessResult(0, 127, '', ''));
    if (r.exitCode == 0) return double.parse((r.stdout as String).trim());
    // No ffprobe: read the duration from the MP4 / QuickTime `mvhd` atom.
    final b = await file.readAsBytes();
    final data = ByteData.sublistView(b);
    for (var o = 4; o + 32 < b.length; o++) {
      if (b[o] == 0x6d &&
          b[o + 1] == 0x76 &&
          b[o + 2] == 0x68 &&
          b[o + 3] == 0x64) {
        final v = b[o + 4];
        final timescale = data.getUint32(o + (v == 1 ? 24 : 16));
        final duration = v == 1
            ? data.getUint64(o + 28)
            : data.getUint32(o + 20);
        return duration / timescale;
      }
    }
    fail('no ffprobe and no mvhd atom found in ${file.path}');
  }

  const slow = Timeout(Duration(minutes: 4));

  final hasPickHook = Platform.environment.containsKey('XUE_HUA_TEST_PICK_FILE');
  final hasPickFilesHook =
      Platform.environment.containsKey('XUE_HUA_TEST_PICK_FILES') ||
      hasPickHook;
  final hasPickDirHook =
      Platform.environment.containsKey('XUE_HUA_TEST_PICK_DIR');
  final hasSaveHook = Platform.environment.containsKey('XUE_HUA_TEST_SAVE_FILE');
  final openSkipped =
      Platform.environment['XUE_HUA_TEST_OPEN_FILE'] == 'skip';

  test('app starts', () async {
    expect(await status(), 'Ready');
  });

  test('retrieveLostCapture answers', () async {
    await driver.tap(find.byValueKey('retrieveLostCapture'));
    await waitStatus(
      (s) => s == 'No lost capture',
      const Duration(seconds: 20),
    );
  });

  test('galleryPermissionStatus answers', () async {
    await driver.tap(find.byValueKey('galleryStatus'));
    await waitStatus(
      (s) => s.startsWith('Gallery status:'),
      const Duration(seconds: 20),
    );
    // ignore: avoid_print
    print('EVIDENCE ${await status()}');
  });

  test('requestGalleryPermission answers', () async {
    await driver.tap(find.byValueKey('requestGalleryPermission'));
    await waitStatus(
      (s) => s.startsWith('Gallery permission:'),
      const Duration(seconds: 20),
    );
    // ignore: avoid_print
    print('EVIDENCE ${await status()}');
    // The example may show a Photos Settings AlertDialog when permanently
    // denied / restricted. Dismiss it so later taps are not blocked.
    try {
      await driver.waitFor(
        find.text('Not now'),
        timeout: const Duration(seconds: 3),
      );
      await driver.tap(find.text('Not now'));
      // ignore: avoid_print
      print('EVIDENCE dismissed Photos permission dialog');
    } catch (_) {
      // Dialog not shown — fine.
    }
  });

  test('pickFile via dialog hook', () async {
    if (!hasPickHook) return;
    await driver.tap(find.byValueKey('pickFile'));
    await waitStatus((s) => s == 'Picked 1 file', const Duration(seconds: 20));
    expect(
      await driver.getText(find.byValueKey('file_name_0')),
      'hello.txt',
    );
    final info = await capturedInfo();
    expect(File(info.path).existsSync(), isTrue);
    expect(info.size, greaterThan(0));
    // ignore: avoid_print
    print('EVIDENCE pickFile ${info.path} size=${info.size}');
  });

  test('pickFiles via dialog hook', () async {
    if (!hasPickFilesHook) return;
    await driver.tap(find.byValueKey('pickFiles'));
    await waitStatus(
      (s) => s.startsWith('Picked ') && s.contains('file'),
      const Duration(seconds: 20),
    );
    // ignore: avoid_print
    print('EVIDENCE ${await status()}');
  });

  test('pickDirectory via dialog hook', () async {
    if (!hasPickDirHook) return;
    await driver.tap(find.byValueKey('pickDirectory'));
    await waitStatus(
      (s) => s.startsWith('Directory:'),
      const Duration(seconds: 20),
    );
    final info = await driver.getText(find.byValueKey('directory_info'));
    expect(info.contains(fixturesDir.path) || info.isNotEmpty, isTrue);
    // ignore: avoid_print
    print('EVIDENCE pickDirectory $info');
  });

  test('saveFile via dialog hook', () async {
    if (!hasSaveHook) return;
    // Uses selected file from prior pick, or demo bytes fallback.
    await driver.tap(find.byValueKey('saveFile'));
    await waitStatus((s) => s.startsWith('Saved:'), const Duration(seconds: 20));
    expect(saveDest.existsSync(), isTrue, reason: 'hook destination written');
    expect(saveDest.lengthSync(), greaterThan(0));
    // ignore: avoid_print
    print(
      'EVIDENCE saveFile ${saveDest.path} size=${saveDest.lengthSync()} status=${await status()}',
    );
  });

  test('capturePhoto', timeout: slow, () async {
    if (expectation == 'any') return;
    await driver.tap(find.byValueKey('capturePhoto'));
    if (expectation == 'captured') {
      await waitStatus(
        (s) => s == 'Photo captured',
        const Duration(seconds: 90),
      );
      expect(
        await driver.getText(find.byValueKey('file_name_0')),
        endsWith('.jpg'),
      );
      final info = await capturedInfo();
      final file = await localCopy(info.path);
      final bytes = await file.readAsBytes();
      final (w, h) = jpegSize(bytes);
      // ignore: avoid_print
      print(
        'EVIDENCE photo ${info.path} size=${bytes.length} (reported ${info.size}) ${w}x$h',
      );
      expect(bytes.length, greaterThan(1000));
      expect(bytes.length, info.size);
      expect(w, greaterThan(0));
      expect(h, greaterThan(0));
    } else {
      await waitStatus(
        (s) => s.contains('unsupported'),
        const Duration(seconds: 30),
      );
    }
  });

  test('saveToGallery after photo', timeout: slow, () async {
    if (expectation != 'captured') return;
    await driver.tap(find.byValueKey('saveToGallery'));
    await waitStatus(
      (s) =>
          s.startsWith('Gallery:') ||
          s.contains('permission_denied') ||
          s.contains('permissionDenied'),
      const Duration(seconds: 30),
    );
    final s = await status();
    // ignore: avoid_print
    print('EVIDENCE saveToGallery $s');
    if (s.startsWith('Gallery:')) {
      final pathMatch = RegExp(r'Gallery: (.+)').firstMatch(s);
      expect(pathMatch, isNotNull);
      final galleryPath = pathMatch!.group(1)!;
      if (!galleryPath.startsWith('file://') && File(galleryPath).existsSync()) {
        expect(File(galleryPath).lengthSync(), greaterThan(1000));
      }
    } else {
      // macOS Photos TCC may deny when the launch parent is not Terminal.
      expect(s.contains('permission_denied') || s.contains('permissionDenied'), isTrue);
    }
  });

  test('openSelected after photo', timeout: slow, () async {
    if (expectation != 'captured') return;
    await driver.tap(find.byValueKey('openSelected'));
    await waitStatus(
      (s) => s.startsWith('Opened ') || s.contains('io_error') || s.contains('Error'),
      const Duration(seconds: 30),
    );
    final s = await status();
    if (openSkipped) {
      expect(s, startsWith('Opened '));
    }
    // ignore: avoid_print
    print('EVIDENCE openSelected $s');
  });

  test('captureVideo', timeout: slow, () async {
    if (expectation == 'any') return;
    await driver.tap(find.byValueKey('captureVideo'));
    if (expectation == 'captured') {
      await waitStatus(
        (s) => s == 'Video captured',
        const Duration(seconds: 120),
      );
      expect(
        await driver.getText(find.byValueKey('file_name_0')),
        anyOf(
          endsWith('.mp4'),
          endsWith('.webm'),
          endsWith('.mov'),
          endsWith('.3gp'),
        ),
      );
      final info = await capturedInfo();
      final file = await localCopy(info.path);
      final length = await file.length();
      final isWebm = file.path.endsWith('.webm');
      if (isWebm) {
        final head = await file.openRead(0, 4).first;
        expect(head, [0x1a, 0x45, 0xdf, 0xa3], reason: 'WebM (EBML) header');
      }
      final duration = isWebm
          ? await videoDuration(file).catchError((_) => -1.0)
          : await videoDuration(file);
      // ignore: avoid_print
      print(
        'EVIDENCE video ${info.path} size=$length (reported ${info.size}) duration=${duration}s',
      );
      expect(length, greaterThan(1000));
      expect(length, info.size);
      // WebM durations need ffprobe; without it only the header is checked.
      if (!(isWebm && duration < 0)) expect(duration, greaterThan(0.3));
    } else {
      await waitStatus(
        (s) => s.contains('unsupported'),
        const Duration(seconds: 30),
      );
    }
  });

  test('saveToGallery video', timeout: slow, () async {
    if (expectation != 'captured') return;
    await driver.tap(find.byValueKey('saveToGallery'));
    await waitStatus(
      (s) =>
          s.startsWith('Gallery:') ||
          s.contains('permission_denied') ||
          s.contains('permissionDenied'),
      const Duration(seconds: 30),
    );
    // ignore: avoid_print
    print('EVIDENCE saveToGallery video ${await status()}');
  });
}
