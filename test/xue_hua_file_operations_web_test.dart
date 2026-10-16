@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations_web.dart';

@JS('eval')
external JSAny? _eval(String code);

@JS('__xueHuaLastInput')
external JSObject? get _lastInput;

extension on JSObject {
  external String? get accept;
  external String? get capture;
}

/// Replaces `HTMLInputElement.click` so "the user" instantly picks a generated
/// image / video file and records the attributes the plugin put on the input.
void _fakeUserSelection({required bool video}) {
  _eval('''
    HTMLInputElement.prototype.click = function () {
      const input = this;
      window.__xueHuaLastInput = {
        accept: input.accept,
        capture: input.getAttribute('capture'),
      };
      const finish = (file) => {
        const dt = new DataTransfer();
        dt.items.add(file);
        input.files = dt.files;
        input.dispatchEvent(new Event('change'));
      };
      if ($video) {
        finish(new File([new Uint8Array([1, 2, 3, 4])], 'clip.mp4', {type: 'video/mp4'}));
        return;
      }
      const canvas = document.createElement('canvas');
      canvas.width = 400;
      canvas.height = 200;
      canvas.getContext('2d').fillRect(0, 0, 400, 200);
      canvas.toBlob((blob) => finish(new File([blob], 'photo.png', {type: 'image/png'})), 'image/png');
    };
  ''');
}

/// PNG header stores width / height big-endian at offsets 16 and 20.
(int, int) _dimensions(List<int> bytes) {
  int be(int o) =>
      (bytes[o] << 24) |
      (bytes[o + 1] << 16) |
      (bytes[o + 2] << 8) |
      bytes[o + 3];
  return (be(16), be(20));
}

void main() {
  final web = XueHuaFileOperationsWeb();

  test('capturePhoto sets capture=environment and returns original', () async {
    _fakeUserSelection(video: false);
    final file = await web.capturePhoto();
    expect(file, isNotNull);
    expect(file!.hasBytes, isTrue);
    expect(_lastInput!.accept, 'image/*');
    expect(_lastInput!.capture, 'environment');
    expect(_dimensions(file.bytes!), (400, 200));
  });

  test('capturePhoto front camera and maxWidth downscale', () async {
    _fakeUserSelection(video: false);
    final file = await web.capturePhoto(
      preferredCamera: CameraFacing.front,
      maxWidth: 100,
    );
    expect(_lastInput!.capture, 'user');
    expect(_dimensions(file!.bytes!), (100, 50));
  });

  test('captureVideo uses video accept + capture', () async {
    _fakeUserSelection(video: true);
    final file = await web.captureVideo(
      preferredCamera: CameraFacing.front,
      maxDuration: const Duration(seconds: 5),
    );
    expect(_lastInput!.accept, 'video/*');
    expect(_lastInput!.capture, 'user');
    expect(file!.name, 'clip.mp4');
    expect(file.size, 4);
  });

  test('retrieveLostCapture is empty on web', () async {
    expect((await web.retrieveLostCapture()).isEmpty, isTrue);
  });
}
