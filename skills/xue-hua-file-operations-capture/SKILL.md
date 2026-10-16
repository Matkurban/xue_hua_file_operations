---
name: xue-hua-file-operations-capture
description: >-
  Use when taking a photo or recording a video with the system camera using
  XueHuaFileOperations (capturePhoto, captureVideo, retrieveLostCapture,
  CameraFacing, LostCaptureResult).
---

# XueHua file operations capture

## Guidelines

* Use `XueHuaFileOperations.instance`.
* Treat user cancel as `null`. Do not catch `ErrorCode.cancelled` for cancel.
* Catch `FileOperationsException`: `ErrorCode.permissionDenied` (camera refused), `ErrorCode.unsupported` (no camera / camera app, or a Linux build without GStreamer), `ErrorCode.invalidArgs`.
* `maxWidth` / `maxHeight` must be `>= 0`, `imageQuality` must be 0-100, `maxDuration` must not be negative; otherwise `ErrorCode.invalidArgs` is thrown before the camera opens.
* `maxDuration` is best effort (ignored by some Android camera apps and by browsers).
* Android: host `Activity` must extend `FlutterFragmentActivity`; declare `android.permission.CAMERA` in the app manifest only if the app wants the plugin to request it.
* iOS: add `NSCameraUsageDescription` (and `NSMicrophoneUsageDescription` for video) to `Info.plist`.
* Call `retrieveLostCapture()` once on startup to recover a capture lost when Android recreated the Activity.
* Set `withData: true` only when the app needs `PlatformFile.bytes`.

## Examples

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

final ops = XueHuaFileOperations.instance;

try {
  final photo = await ops.capturePhoto(
    preferredCamera: CameraFacing.front,
    maxWidth: 1280,
    imageQuality: 85,
  );
  if (photo == null) return; // cancelled

  final video = await ops.captureVideo(maxDuration: const Duration(seconds: 30));
} on FileOperationsException catch (e) {
  // e.code == ErrorCode.permissionDenied / unsupported / ...
}

final lost = await ops.retrieveLostCapture();
if (!lost.isEmpty) {
  final recovered = lost.files; // lost.type: image / video
}
```

## Read when needed

* Full signatures: [references/capture-api.md](references/capture-api.md)
* Manifest / Info.plist setup: skill `xue-hua-file-operations-setup`
* Error codes: skill `xue-hua-file-operations-errors`
