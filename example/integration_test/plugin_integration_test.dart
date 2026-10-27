import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

/// Device-level coverage for public APIs that do not require a live UI picker.
///
/// Dialog-driven flows (pick/save/open success / openAppSettings) stay in
/// `test_driver/app_test.dart` (flutter_driver + XUE_HUA_TEST_* hooks) so this
/// suite never presents system sheets that hang automation. This file is the
/// supported `integration_test` path used with:
///   `flutter test integration_test -d DEVICE`
///   `flutter drive --driver=test_driver/integration_test.dart`
///   `--target=integration_test/plugin_integration_test.dart -d DEVICE`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final api = XueHuaFileOperations.instance;

  final invalidArgs = isA<FileOperationsException>().having(
    (e) => e.code,
    'code',
    ErrorCode.invalidArgs,
  );

  testWidgets('singleton is available', (tester) async {
    expect(api, isNotNull);
    expect(identical(api, XueHuaFileOperations.instance), isTrue);
  });

  testWidgets('retrieveLostCapture is empty without a lost capture', (
    tester,
  ) async {
    final lost = await api.retrieveLostCapture();
    expect(lost.isEmpty, isTrue);
    expect(lost.files, isEmpty);
    expect(lost.exception, isNull);
  });

  testWidgets('galleryPermissionStatus returns a GalleryPermissionStatus', (
    tester,
  ) async {
    final status = await api.galleryPermissionStatus();
    expect(status, isA<GalleryPermissionStatus>());
    expect(GalleryPermissionStatus.values, contains(status));
    // Getter consistency for the wire-mapped enum.
    expect(status.canSave, status.isGranted || status.isLimited);
    expect(status.wireName, isNotEmpty);

    final forAlbum = await api.galleryPermissionStatus(forAlbum: true);
    expect(forAlbum, isA<GalleryPermissionStatus>());
    expect(forAlbum.canSave, forAlbum.isGranted || forAlbum.isLimited);
  });

  testWidgets('requestGalleryPermission returns a status without hanging', (
    tester,
  ) async {
    // Native short-circuits when PhotoKit is already determined (1.5.3+).
    // When still notDetermined a system prompt may appear; only call after a
    // non-notDetermined status, or accept any returned enum value quickly.
    final before = await api.galleryPermissionStatus();
    if (before == GalleryPermissionStatus.denied) {
      // May map from notDetermined; skip interactive prompt in automation.
      return;
    }
    final after = await api.requestGalleryPermission().timeout(
      const Duration(seconds: 10),
    );
    expect(after, isA<GalleryPermissionStatus>());

    final album = await api
        .requestGalleryPermission(forAlbum: true)
        .timeout(const Duration(seconds: 10));
    expect(album, isA<GalleryPermissionStatus>());
  });

  testWidgets('Dart-side invalid args are rejected', (tester) async {
    expect(() => api.pickFiles(maxFiles: 0), throwsA(invalidArgs));
    expect(() => api.pickFiles(maxFiles: -1), throwsA(invalidArgs));
    expect(() => api.capturePhoto(maxWidth: -1), throwsA(invalidArgs));
    expect(() => api.capturePhoto(maxHeight: -1), throwsA(invalidArgs));
    expect(() => api.capturePhoto(imageQuality: -1), throwsA(invalidArgs));
    expect(() => api.capturePhoto(imageQuality: 101), throwsA(invalidArgs));
    expect(
      () => api.captureVideo(maxDuration: const Duration(seconds: -1)),
      throwsA(invalidArgs),
    );
    expect(() => api.saveFile(fileName: 'a.txt'), throwsA(invalidArgs));
    expect(() => api.saveToGallery(fileName: 'a.bin'), throwsA(invalidArgs));
    expect(
      () => api.saveToGallery(
        fileName: 'noext',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(invalidArgs),
    );
    expect(() => api.openFile(), throwsA(invalidArgs));
  });

  // Linux without videotestsrc, or iOS Simulator (no camera pipeline):
  // capture must report unsupported rather than hanging on a camera UI.
  testWidgets('camera capture reports unsupported without a camera', (
    tester,
  ) async {
    final linuxWithoutCamera =
        !kIsWeb &&
        Platform.isLinux &&
        !Platform.environment.containsKey('XUE_HUA_CAMERA_TEST_SOURCE');
    final iosSimulator =
        !kIsWeb &&
        Platform.isIOS &&
        Platform.environment['SIMULATOR_DEVICE_NAME'] != null;
    if (!linuxWithoutCamera && !iosSimulator) return;

    for (final capture in <Future<Object?> Function()>[
      () => api.capturePhoto(),
      () => api.captureVideo(),
    ]) {
      await expectLater(
        capture(),
        throwsA(
          isA<FileOperationsException>().having(
            (e) => e.code,
            'code',
            anyOf(ErrorCode.unsupported, ErrorCode.permissionDenied),
          ),
        ),
      );
    }
  });

  testWidgets('saveToGallery succeeds when gallery write is already allowed', (
    tester,
  ) async {
    final status = await api.galleryPermissionStatus();
    if (!status.canSave) return;

    // 1x1 PNG
    const png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
      0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    final result = await api.saveToGallery(
      fileName: 'xue_hua_it_${DateTime.now().millisecondsSinceEpoch}.png',
      bytes: Uint8List.fromList(png),
      type: GalleryMediaType.image,
    );
    expect(result.name, endsWith('.png'));
    expect(result.identifier, isNotNull);
  });

  testWidgets('saveToGallery reports permission_denied when save is blocked', (
    tester,
  ) async {
    final status = await api.galleryPermissionStatus();
    if (status.canSave) return;
    if (status == GalleryPermissionStatus.denied) {
      // notDetermined maps to denied; requesting would show a system prompt.
      return;
    }

    const png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
      0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    await expectLater(
      api.saveToGallery(
        fileName: 'xue_hua_it_denied.png',
        bytes: Uint8List.fromList(png),
        type: GalleryMediaType.image,
      ),
      throwsA(
        isA<FileOperationsException>().having(
          (e) => e.code,
          'code',
          ErrorCode.permissionDenied,
        ),
      ),
    );
  });

  testWidgets('saveToGallery missing sourcePath reports not_found', (
    tester,
  ) async {
    if (kIsWeb) return;
    await expectLater(
      api.saveToGallery(
        fileName: 'missing.png',
        sourcePath: '${Directory.systemTemp.path}/xhfo_it_missing_source.png',
        type: GalleryMediaType.image,
      ),
      throwsA(
        isA<FileOperationsException>().having(
          (e) => e.code,
          'code',
          anyOf(ErrorCode.notFound, ErrorCode.ioError),
        ),
      ),
    );
  });

  testWidgets('openFile missing path reports not_found or io_error', (
    tester,
  ) async {
    if (kIsWeb) return;
    await expectLater(
      api.openFile(path: '/tmp/xue_hua_file_operations_missing_it_file.txt'),
      throwsA(
        isA<FileOperationsException>().having(
          (e) => e.code,
          'code',
          anyOf(ErrorCode.notFound, ErrorCode.ioError, ErrorCode.unknown),
        ),
      ),
    );
  });

  // openAppSettings leaves the app for Settings — covered by unit/channel
  // tests and the example UI, not by this non-interactive suite.
}
