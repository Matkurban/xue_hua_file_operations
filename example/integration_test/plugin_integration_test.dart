import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('singleton is available', (WidgetTester tester) async {
    expect(XueHuaFileOperations.instance, isNotNull);
  });

  testWidgets('retrieveLostCapture is empty without a lost capture', (
    tester,
  ) async {
    final lost = await XueHuaFileOperations.instance.retrieveLostCapture();
    expect(lost.isEmpty, isTrue);
  });

  // Desktop capture opens a real camera window, so the test only runs where a
  // camera is known to be absent: Linux without the videotestsrc test hook.
  testWidgets('camera capture reports unsupported without a camera', (
    tester,
  ) async {
    final linuxWithoutCamera =
        !kIsWeb &&
        Platform.isLinux &&
        !Platform.environment.containsKey('XUE_HUA_CAMERA_TEST_SOURCE');
    if (!linuxWithoutCamera) return;
    for (final capture in <Future<Object?> Function()>[
      () => XueHuaFileOperations.instance.capturePhoto(),
      () => XueHuaFileOperations.instance.captureVideo(),
    ]) {
      await expectLater(
        capture(),
        throwsA(
          isA<FileOperationsException>().having(
            (e) => e.code,
            'code',
            ErrorCode.unsupported,
          ),
        ),
      );
    }
  });
}
