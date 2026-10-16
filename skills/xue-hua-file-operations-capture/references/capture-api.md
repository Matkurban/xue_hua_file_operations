# Capture API reference

Every public member below is from `package:xue_hua_file_operations`. Access the API through `XueHuaFileOperations.instance`.

## `XueHuaFileOperations.capturePhoto`

Take a photo with the system camera. Returns `null` if the user cancels.

```dart
Future<PlatformFile?> capturePhoto({
  CameraFacing preferredCamera = CameraFacing.rear,
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
  bool withData = false,
})
```

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `preferredCamera` | `CameraFacing` | `rear` | Front / rear hint; falls back to the available camera. Web maps to `capture="user"` / `"environment"`. |
| `maxWidth` | `double?` | `null` | Downscale to fit, aspect ratio kept, never enlarged. `>= 0`. |
| `maxHeight` | `double?` | `null` | Same for height. `>= 0`. |
| `imageQuality` | `int?` | `null` | JPEG quality 0-100 (not applied to PNG / alpha photos). |
| `withData` | `bool` | `false` | Load `PlatformFile.bytes`; always loaded on Web. |

The returned `PlatformFile.path` points into the app cache (`null` on Web).

## `XueHuaFileOperations.captureVideo`

```dart
Future<PlatformFile?> captureVideo({
  CameraFacing preferredCamera = CameraFacing.rear,
  Duration? maxDuration,
  bool withData = false,
})
```

`maxDuration` caps the recording length (best effort).

## `XueHuaFileOperations.retrieveLostCapture`

```dart
Future<LostCaptureResult> retrieveLostCapture()
```

Android only; other platforms return `LostCaptureResult.empty`.

## `CameraFacing`

`enum CameraFacing { rear, front }`

## `LostCaptureResult`

| Member | Type | Description |
| --- | --- | --- |
| `files` | `List<PlatformFile>` | Recovered capture (at most one). |
| `type` | `GalleryMediaType?` | `image` or `video`. |
| `exception` | `FileOperationsException?` | Set when the lost operation failed. |
| `isEmpty` | `bool` | No files and no exception. |
| `LostCaptureResult.empty` | const | Nothing recovered. |

## Platform behavior

| Platform | Behavior |
| --- | --- |
| Android | `ACTION_IMAGE_CAPTURE` / `ACTION_VIDEO_CAPTURE` via the plugin `FileProvider`; `CAMERA` requested when declared in the manifest |
| iOS | `UIImagePickerController` camera; needs `NSCameraUsageDescription` (+ `NSMicrophoneUsageDescription` for video) |
| Web | `<input type="file" capture>`; mobile browsers only, canvas resize |
| macOS | AVFoundation preview sheet; JPEG / `.mov`; entitlements `device.camera` (+ `device.audio-input`) and `NSCameraUsageDescription` (+ `NSMicrophoneUsageDescription`) |
| Windows | Media Foundation preview window; JPEG / H.264+AAC MP4; desktop camera privacy setting must allow desktop apps |
| Linux | GStreamer + GTK preview dialog; JPEG / MP4 (H.264) or WebM; build needs GStreamer dev packages, runtime needs a V4L2 camera (`ErrorCode.unsupported` otherwise) |

## UI-test hooks

The native camera UI is outside Flutter's widget tree. Set `XUE_HUA_CAMERA_TEST_AUTO=1` in the app's environment to auto-press the shutter / Record (and stop recordings after 2 s) on macOS, iOS and Linux; Linux additionally supports `XUE_HUA_CAMERA_TEST_SOURCE=videotestsrc` to run without a camera. Without the variables nothing happens.
