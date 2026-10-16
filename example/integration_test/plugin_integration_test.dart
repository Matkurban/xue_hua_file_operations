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

  testWidgets('camera capture is unsupported on desktop', (tester) async {
    final isDesktop =
        !kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
    if (!isDesktop) return;
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
    final lost = await XueHuaFileOperations.instance.retrieveLostCapture();
    expect(lost.isEmpty, isTrue);
  });
}
