import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

/// Edge cases: tooManyFiles and camera unsupported.
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
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    fail('Timed out, status is "${await status()}"');
  }

  test('tooManyFiles when maxFiles=3 and hook has 4', () async {
    if (!Platform.environment.containsKey('XUE_HUA_TEST_PICK_FILES')) return;
    await driver.tap(find.byValueKey('limitMaxFiles'));
    await driver.tap(find.byValueKey('pickFiles'));
    await waitStatus(
      (s) => s.contains('too_many_files') || s.contains('tooManyFiles') ||
          s.contains('Selected more files'),
      const Duration(seconds: 20),
    );
    // ignore: avoid_print
    print('EVIDENCE tooManyFiles ${await status()}');
  });

  test('capturePhoto unsupported without camera', () async {
    if (expectation != 'unsupported') return;
    await driver.tap(find.byValueKey('capturePhoto'));
    await waitStatus(
      (s) => s.contains('unsupported'),
      const Duration(seconds: 30),
    );
    // ignore: avoid_print
    print('EVIDENCE unsupported photo ${await status()}');
  });

  test('captureVideo unsupported without camera', () async {
    if (expectation != 'unsupported') return;
    await driver.tap(find.byValueKey('captureVideo'));
    await waitStatus(
      (s) => s.contains('unsupported'),
      const Duration(seconds: 30),
    );
    // ignore: avoid_print
    print('EVIDENCE unsupported video ${await status()}');
  });
}
