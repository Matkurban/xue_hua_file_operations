// Run with (see README of the example):
//   flutter drive --driver=test_driver/app_test.dart \
//     --target=test_driver/app.dart -d <linux|macos|android-emulator|ios-sim>
//
// Environment (read by this driver process):
//   XUE_HUA_EXPECT=captured     camera capture must succeed (Linux test
//                               source, or a camera that is already allowed)
//   XUE_HUA_EXPECT=unsupported  capture must report `unsupported`
//   unset / any                 only check that the app answers
import 'dart:io';

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

  test('capturePhoto', () async {
    if (expectation == 'any') return;
    await driver.tap(find.byValueKey('capturePhoto'));
    if (expectation == 'captured') {
      await waitStatus(
        (s) => s == 'Photo captured',
        const Duration(seconds: 60),
      );
      expect(
        await driver.getText(find.byValueKey('file_name_0')),
        endsWith('.jpg'),
      );
    } else {
      await waitStatus(
        (s) => s.contains('unsupported'),
        const Duration(seconds: 30),
      );
    }
  });

  test('captureVideo', () async {
    if (expectation == 'any') return;
    await driver.tap(find.byValueKey('captureVideo'));
    if (expectation == 'captured') {
      await waitStatus(
        (s) => s == 'Video captured',
        const Duration(seconds: 90),
      );
      expect(
        await driver.getText(find.byValueKey('file_name_0')),
        anyOf(endsWith('.mp4'), endsWith('.webm'), endsWith('.mov')),
      );
    } else {
      await waitStatus(
        (s) => s.contains('unsupported'),
        const Duration(seconds: 30),
      );
    }
  });
}
