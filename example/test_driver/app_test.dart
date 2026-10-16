// Run with (see README of the example):
//   flutter drive --driver=test_driver/app_test.dart \
//     --target=test_driver/app.dart -d <linux|macos|android-emulator|ios-sim>
//
// Environment (read by this driver process):
//   XUE_HUA_EXPECT=captured     camera capture must succeed (Linux test
//                               source, or a camera that is already allowed)
//   XUE_HUA_EXPECT=unsupported  capture must report `unsupported`
//   unset / any                 only check that the app answers
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

  setUpAll(() async {
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

  /// The `path=` and `size=` shown in the first file card.
  Future<({String path, int size})> capturedInfo() async {
    final info = await driver.getText(find.byValueKey('file_info_0'));
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

  /// Duration in seconds of a video, with ffprobe or (macOS) mdls.
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
    if (Platform.isMacOS) {
      final m = await Process.run('mdls', [
        '-raw',
        '-name',
        'kMDItemDurationSeconds',
        file.path,
      ]);
      return double.parse((m.stdout as String).trim());
    }
    fail('neither ffprobe nor mdls is available to validate the video');
  }

  const slow = Timeout(Duration(minutes: 4));

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
      final duration = await videoDuration(file);
      // ignore: avoid_print
      print(
        'EVIDENCE video ${info.path} size=$length (reported ${info.size}) duration=${duration}s',
      );
      expect(length, greaterThan(1000));
      expect(length, info.size);
      expect(duration, greaterThan(0.5));
    } else {
      await waitStatus(
        (s) => s.contains('unsupported'),
        const Duration(seconds: 30),
      );
    }
  });
}
