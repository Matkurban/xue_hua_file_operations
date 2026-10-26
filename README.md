# xue_hua_file_operations

English | [中文](README_zh.md)

**Live demo:** [https://matkurban.github.io/xue_hua_file_operations/](https://matkurban.github.io/xue_hua_file_operations/)

Cross-platform Flutter plugin for picking files and directories, saving files (save-as), saving images/videos to the gallery, and opening files with the system default application.

## Features

- Pick a single file (`pickFile`) or multiple files (`pickFiles`)
- Filter by high-level `FileType`, file extensions, and/or MIME types
- Optional `maxFiles` limit for multi-select (validated after selection)
- Capture a photo (`capturePhoto`) or record a video (`captureVideo`) with the system camera, with front/rear preference, photo size/quality and video duration limits
- Recover a capture lost to Android Activity recreation (`retrieveLostCapture`)
- Pick a directory (`pickDirectory`)
- Save-as dialog (`saveFile`) from bytes or by copying a source path
- Save an image or video to the system gallery (`saveToGallery`)
- Query or request gallery permission (`galleryPermissionStatus` / `requestGalleryPermission`)
- Open system settings when gallery access is permanently denied (`openAppSettings`)
- Open a file with the system handler (`openFile`)
- Unified `PlatformFile` model and typed `FileOperationsException` / `ErrorCode`
- Package Skills for AI agents (`dart run skills@ get`)

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  xue_hua_file_operations: ^1.5.0
```

Then run:

```bash
flutter pub get
```

## Package skills

This package ships Agent Skills that teach AI coding agents how to use the public API. After adding the dependency, run the following in **your** project (not inside this plugin repo):

```bash
dart run skills@ get
# or install every discovered skill
dart run skills@ get --all
```

Skills included:

| Skill                            | Use when                                                                                      |
|----------------------------------|-----------------------------------------------------------------------------------------------|
| `xue-hua-file-operations-setup`  | Adding the package, platform permissions, `FlutterFragmentActivity`, Info.plist, entitlements |
| `xue-hua-file-operations-pick`   | `pickFile` / `pickFiles` / `pickDirectory`                                                    |
| `xue-hua-file-operations-save`   | `saveFile`, `saveToGallery`, gallery permission APIs                                          |
| `xue-hua-file-operations-open`   | `openFile`                                                                                    |
| `xue-hua-file-operations-errors` | `FileOperationsException` / `ErrorCode`                                                       |

See [Ship skills with packages](https://dart.dev/tools/pub/package-skills).

## Supported platforms

| Platform | Supported   | Notes                                                                                                            |
|----------|-------------|------------------------------------------------------------------------------------------------------------------|
| Android  | Yes         | Storage Access Framework (SAF) / Activity Result APIs; `saveToGallery` uses MediaStore / public Pictures         |
| iOS      | Yes (13.0+) | Media uses `PHPickerViewController` (iOS 14+), other types use `UIDocumentPicker`; `saveToGallery` uses PhotoKit |
| macOS    | Yes         | Native `NSOpenPanel` / `NSSavePanel`; `saveToGallery` uses PhotoKit; camera capture via AVFoundation              |
| Windows  | Yes         | Native file / folder dialogs; `saveToGallery` writes Pictures / Videos; camera capture via Media Foundation       |
| Linux    | Yes         | Native file / folder dialogs; `saveToGallery` writes XDG Pictures / Videos; camera capture via GStreamer          |
| Web      | Yes         | HTML `<input type="file">` and Blob download; `saveToGallery` downloads the file                                 |

### Path and identifier behavior

| Platform                | `path`                                           | Notes                                                                                      |
|-------------------------|--------------------------------------------------|--------------------------------------------------------------------------------------------|
| Android / iOS / Desktop | Usually non-null (cache copy or filesystem path) | `identifier` keeps the native URI / URL / bookmark                                         |
| Web                     | Always `null`                                    | `bytes` are always loaded; save triggers a download; open needs an object-URL `identifier` |

### Directory picking

| Platform                | What you get                                                  | Notes                                                                            |
|-------------------------|---------------------------------------------------------------|----------------------------------------------------------------------------------|
| Android                 | SAF tree URI in `path` / `identifier`                         | Persistable read permission is taken when possible                               |
| iOS                     | Display `path` + security-scoped **bookmark** in `identifier` | Prefer `identifier` for later access / `openFile`; raw path alone is not durable |
| macOS / Windows / Linux | Real filesystem path                                          | Native folder dialogs                                                            |
| Web                     | Folder name via `webkitdirectory`                             | Not a real FS path; capability depends on the browser                            |

## Platform setup and permissions

### Android

**Permissions for pick / save-as / open:** No dangerous storage permissions (`READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` / media permissions) are required. Those APIs use the system document picker (SAF).

**Permissions for `saveToGallery`:**

- **API 24–28:** the plugin declares `WRITE_EXTERNAL_STORAGE` with `maxSdkVersion=28` and requests it at runtime. Denial throws `ErrorCode.permissionDenied`. You can also call `requestGalleryPermission` first and inspect `GalleryPermissionStatus`.
- **API 29+:** no storage permission. The plugin inserts via MediaStore (`RELATIVE_PATH` + `IS_PENDING`).
- **API 33+:** do **not** add `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` for this API. Inserting media the app creates does not need them.

Do not rely on `requestLegacyExternalStorage`.

**Camera capture (`capturePhoto` / `captureVideo`):** the plugin does not declare the camera permission itself. If your app manifest declares `<uses-permission android:name="android.permission.CAMERA" />` the plugin requests it at runtime (refusal throws `ErrorCode.permissionDenied`); without it the system camera app handles its own permission. Add `<uses-feature android:name="android.hardware.camera" android:required="false" />` so non-camera devices can still install the app. Photos / videos are written to the app cache through the plugin's own `FileProvider`, so no host FileProvider configuration is needed. A device without a camera app throws `ErrorCode.unsupported`.

**FileProvider:** The plugin registers its own `FileProvider` for opening files via content URIs. No host-app FileProvider setup is required for basic use.

**Host Activity (required):** The host `Activity` must extend `FlutterFragmentActivity` (not plain `FlutterActivity`), because pickers use Activity Result contracts:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

### iOS

Minimum version is **iOS 13.0** (same as Flutter’s default `IPHONEOS_DEPLOYMENT_TARGET`). Host apps do not need to raise it to 14.0 to use this plugin.

**Permissions for document pick / save / open:** No extra Info.plist privacy keys (such as photo library usage descriptions) are required for those document-picker APIs.

**Permissions for `saveToGallery`:** add to the host `Info.plist`:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app saves images and videos to your photo library.</string>
```

If you pass `albumName` (create / add to a custom album), also add:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>This app saves images and videos to albums in your photo library.</string>
```

PhotoKit shows the system prompt **only while status is `notDetermined`**. After the user taps Don’t Allow, `requestGalleryPermission` returns `permanentlyDenied` with no dialog. Call `openAppSettings()` (uses [`UIApplication.openSettingsURLString`](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring)) so they can enable Photos in Settings.

To re-test the first prompt during development, delete the app or reset the Simulator’s Privacy settings. The same bundle ID remembers a previous denial.

**Camera capture (`capturePhoto` / `captureVideo`):** add to the host `Info.plist` (the app is terminated by iOS without them; the plugin returns `ErrorCode.invalidArgs` when a key is missing):

```xml
<key>NSCameraUsageDescription</key>
<string>This app takes photos and records videos.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app records audio when capturing videos.</string>
```

The camera is not available in the iOS Simulator (`ErrorCode.unsupported`); test on a device.

**Directory access:** When the user picks a directory, the plugin stores a security-scoped bookmark in `DirectoryResult.identifier` (prefixed). Prefer that identifier for later access or `openFile`; the display `path` alone is not durable across app launches.

### macOS

**Entitlements (App Sandbox):** If your app uses App Sandbox (typical for Mac App Store / Flutter macOS apps), add user-selected file access:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

For `saveToGallery` (Photos library), also add:

```xml
<key>com.apple.security.personal-information.photos-library</key>
<true/>
```

And the same `NSPhotoLibraryAddUsageDescription` / `NSPhotoLibraryUsageDescription` keys as on iOS (in `macos/Runner/Info.plist`).

**Camera:** `capturePhoto` / `captureVideo` use AVFoundation and show a sheet (or panel) with a live preview and *Take Photo* / *Record* / *Stop* / *Cancel* buttons. `preferredCamera: front` picks the built-in camera, `rear` prefers an external camera; output is JPEG / QuickTime `.mov`. Add the camera (and microphone, for video) entitlements to `DebugProfile.entitlements` and `Release.entitlements` when the App Sandbox is on:

```xml
<key>com.apple.security.device.camera</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

and the usage descriptions to `macos/Runner/Info.plist` (the plugin returns `ErrorCode.invalidArgs` when a key is missing; video still works without the microphone permission, just without sound):

```xml
<key>NSCameraUsageDescription</key>
<string>This app takes photos and records videos.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app records audio when capturing videos.</string>
```

A denied camera permission throws `ErrorCode.permissionDenied` (System Settings → Privacy & Security → Camera); no camera throws `ErrorCode.unsupported`.

**UI-test hook (macOS and iOS):** the native camera UI is outside Flutter's widget tree, so `flutter_driver` cannot press its buttons. Start the app with the environment variable `XUE_HUA_CAMERA_TEST_AUTO=1` and the plugin presses the shutter / Record about 1.5 s after the camera appears and stops a recording 2 s after it started. The real camera is still used; without the variable nothing happens. On macOS `flutter drive -d macos` passes the variable through; for the iOS simulator use `SIMCTL_CHILD_XUE_HUA_CAMERA_TEST_AUTO=1` (note: the iOS simulator has no working camera pipeline, so real capture can only be tested on a device). See `example/test_driver/`.

Without the Photos entitlement, PhotoKit often returns `.denied` immediately and never shows a prompt.

Same one-shot prompt rule as iOS. macOS always requests PhotoKit `readWrite` (`forAlbum` is ignored): System Settings → Privacy & Security → Photos only lists read/write clients. `addOnly` does not appear in that list and may return `.denied` without a prompt.

**Launch path (TCC responsible process):** macOS attributes Photos prompts to the parent process. If you `flutter run -d macos` from Cursor or VS Code, the system may silently deny access and **never list this app** under Photos. Test Photos from the system Terminal, or build then open the app bundle:

```bash
cd example
flutter build macos
open build/macos/Build/Products/Debug/xue_hua_file_operations_example.app
```

An empty Photos list after a request means TCC did not record this app; resetting the bundle ID will not fix that. After a real denial, `openAppSettings()` opens that Photos pane (a convenience URL, not an Apple `openSettingsURLString` equivalent). To reset a recorded decision during development:

```bash
tccutil reset Photos com.your.bundle.id
```

See the example app entitlements under `example/macos/Runner/`.

### Windows

**Camera:** `capturePhoto` / `captureVideo` open a native preview window (Media Foundation capture engine) with *Take Photo* / *Record* / *Stop* / *Cancel* buttons. Photos are JPEG, videos are H.264 + AAC MP4 (sound is skipped when no microphone exists). `preferredCamera` prefers an integrated (front) or an external (rear) camera by device name. No manifest entry is needed for desktop (Win32) apps, but Windows Settings → Privacy & security → Camera → *Let desktop apps access your camera* must be on; otherwise `ErrorCode.permissionDenied` is thrown. No camera → `ErrorCode.unsupported`. Verified on Windows 11 with a USB webcam (640x480 JPEG, 2 s H.264 MP4). UI-test hook: start the app with `XUE_HUA_CAMERA_TEST_AUTO=1` to auto-press Take Photo / Record ~1.5 s after the preview starts and stop recordings 2 s after they started (real camera; harmless without the variable).

**Permissions:** None. Uses native system file and folder dialogs. `saveToGallery` writes to the user Pictures or Videos known folder. No extra manifest entries are required for this plugin.

Dialog-based APIs can skip the native chooser in automated runs (same env vars as Linux): `XUE_HUA_TEST_PICK_FILE`, `XUE_HUA_TEST_PICK_FILES` (semicolon-separated on Windows because of drive letters), `XUE_HUA_TEST_PICK_DIR`, `XUE_HUA_TEST_SAVE_FILE` (literal `CANCEL` simulates cancel), and `XUE_HUA_TEST_OPEN_FILE=skip`. See `example/test_driver/`.

### Linux

**Camera:** `capturePhoto` / `captureVideo` open a GTK preview dialog fed by GStreamer (`v4l2src`). Photos are JPEG, videos are MP4 (H.264 via `x264enc` or `openh264enc`, plus `h264parse` from the *bad* plugins and `mp4mux`) or WebM (VP8) when no H.264 encoder / parser is installed. The build needs the GStreamer development packages (without them the plugin still builds and the capture methods throw `ErrorCode.unsupported`); at runtime a V4L2 camera is required (`ErrorCode.unsupported` otherwise, `ErrorCode.permissionDenied` when `/dev/video*` cannot be opened - add the user to the `video` group).

| Distro        | Build packages                                                                             | Runtime plugins (video recording)                       |
| ------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------- |
| Ubuntu/Debian | `libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`                                     | `gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly` |
| Fedora        | `gstreamer1-devel gstreamer1-plugins-base-devel`                                           | `gstreamer1-plugins-good gstreamer1-plugins-bad-free` (+ RPM Fusion `x264` / `openh264` for H.264)|
| Arch          | `gstreamer gst-plugins-base`                                                               | `gst-plugins-good gst-plugins-bad gst-plugins-ugly`                   |

Testing without a camera: set `XUE_HUA_CAMERA_TEST_SOURCE=videotestsrc` to use GStreamer's test pattern as the camera, and `XUE_HUA_CAMERA_TEST_AUTO=1` to press the shutter / stop automatically (used by the example's `flutter_driver` test). Dialog-based APIs can skip the native GTK chooser in automated runs: `XUE_HUA_TEST_PICK_FILE`, `XUE_HUA_TEST_PICK_FILES` (colon-separated), `XUE_HUA_TEST_PICK_DIR`, `XUE_HUA_TEST_SAVE_FILE` (literal `CANCEL` simulates cancel), and `XUE_HUA_TEST_OPEN_FILE=skip` (validate the path exists without opening a viewer). See `example/test_driver/`.

**Permissions:** None. Uses native system file and folder dialogs. `saveToGallery` writes to XDG Pictures or Videos (there is no system photo library). No extra desktop permissions are required for this plugin.

### Web

**Camera:** `capturePhoto` / `captureVideo` use `<input type="file" capture>`: mobile browsers open the camera (`user` / `environment` follows `preferredCamera`), desktop browsers show the file chooser. `maxDuration` is ignored; photos are resized on a canvas.

**Permissions:** None at the app level. The browser shows its own file picker / download UI. A user gesture is typically required to open the picker.

**Limitations:**

- `path` is always `null`
- Picked files always include `bytes`
- `saveFile` requires `bytes` (`sourcePath` is not supported)
- `saveToGallery` triggers a browser download (`bytes` required; `albumName` is ignored)
- `galleryPermissionStatus` / `requestGalleryPermission` always return `granted`
- `openFile` requires an object-URL `identifier` (for example from a previous pick); local filesystem paths are not supported

## Quick start

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

final ops = XueHuaFileOperations.instance;

// Single file
final file = await ops.pickFile(withData: false);

// Multiple files (optional max)
final files = await ops.pickFiles(maxFiles: 5, type: FileType.image);

// Directory
final dir = await ops.pickDirectory();

// Save as
await ops.saveFile(
  fileName: 'export.txt',
  bytes: file?.bytes,
  sourcePath: file?.path,
);

// Save image/video to gallery
await ops.saveToGallery(
  fileName: file?.name ?? 'shot.jpg',
  bytes: file?.bytes,
  sourcePath: file?.path,
);

final status = await ops.requestGalleryPermission();
if (status.isPermanentlyDenied || status.isRestricted) {
  await ops.openAppSettings();
}

// Open
await ops.openFile(path: file?.path, identifier: file?.identifier);
```

Cancel returns `null`. Hard failures throw `FileOperationsException`.

## API reference

Access the API through the singleton:

```dart
XueHuaFileOperations.instance
```

### `pickFile`

Pick a single file. Returns `null` if the user cancels.

```dart
Future<PlatformFile?> pickFile({
  bool withData = false,
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  List<String>? allowedMimeTypes,
})
```

| Parameter           | Type            | Default        | Description                                                                                                                                                                                                                                                                                     |
|---------------------|-----------------|----------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `withData`          | `bool`          | `false`        | When `true`, load file contents into `PlatformFile.bytes`. On Web, bytes are always loaded regardless of this flag.                                                                                                                                                                             |
| `dialogTitle`       | `String?`       | `null`         | Optional title for the native dialog where supported (desktop). May be ignored on some platforms (e.g. Android SAF, Web).                                                                                                                                                                       |
| `type`              | `FileType`      | `FileType.any` | High-level filter: `any`, `media`, `image`, `video`, `audio`, or `custom`. On iOS / Android, `image` / `video` / `media` (without extension / MIME filters) opens the system photo picker (iOS `PHPickerViewController`, Android Photo Picker) so items can be selected from the photo library. |
| `allowedExtensions` | `List<String>?` | `null`         | Allowed extensions (with or without leading `.`), e.g. `['pdf', 'txt']`. Used especially with `FileType.custom` or as an additional filter.                                                                                                                                                     |
| `allowedMimeTypes`  | `List<String>?` | `null`         | Allowed MIME types, e.g. `['application/pdf']`. Behavior depends on the platform picker.                                                                                                                                                                                                        |

**Returns:** `PlatformFile?` — selected file, or `null` on cancel.

### `pickFiles`

Pick multiple files. Returns `null` if the user cancels.

```dart
Future<List<PlatformFile>?> pickFiles({
  int? maxFiles,
  bool withData = false,
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  List<String>? allowedMimeTypes,
})
```

| Parameter           | Type            | Default        | Description                                                                                                                                                                                     |
|---------------------|-----------------|----------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `maxFiles`          | `int?`          | `null`         | Maximum number of files allowed. `null` means unlimited. If provided, must be `>= 1`. If the user selects more than `maxFiles`, throws `FileOperationsException` with `ErrorCode.tooManyFiles`. |
| `withData`          | `bool`          | `false`        | Same as `pickFile`.                                                                                                                                                                             |
| `dialogTitle`       | `String?`       | `null`         | Same as `pickFile`.                                                                                                                                                                             |
| `type`              | `FileType`      | `FileType.any` | Same as `pickFile`.                                                                                                                                                                             |
| `allowedExtensions` | `List<String>?` | `null`         | Same as `pickFile`.                                                                                                                                                                             |
| `allowedMimeTypes`  | `List<String>?` | `null`         | Same as `pickFile`.                                                                                                                                                                             |

**Returns:** `List<PlatformFile>?` — selected files, or `null` on cancel.

**Throws:** `FileOperationsException` with `ErrorCode.invalidArgs` if `maxFiles` is provided and `< 1`.

### `capturePhoto`

Take a photo with the system / device camera. Returns `null` if the user cancels.

```dart
Future<PlatformFile?> capturePhoto({
  CameraFacing preferredCamera = CameraFacing.rear,
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
  bool withData = false,
})
```

| Parameter         | Type           | Default             | Description                                                                                                                     |
|-------------------|----------------|---------------------|---------------------------------------------------------------------------------------------------------------------------------|
| `preferredCamera` | `CameraFacing` | `CameraFacing.rear` | Front / rear camera hint. Falls back to the available camera.                                                                   |
| `maxWidth`        | `double?`      | `null`              | Downscale so the photo fits this width (aspect ratio kept, never enlarged). Must be `>= 0`.                                     |
| `maxHeight`       | `double?`      | `null`              | Same for height. Must be `>= 0`.                                                                                                |
| `imageQuality`    | `int?`         | `null`              | JPEG quality `0`-`100`. Ignored for photos with transparency (PNG). Values outside the range throw `ErrorCode.invalidArgs`.    |
| `withData`        | `bool`         | `false`             | Load bytes into `PlatformFile.bytes` (always loaded on Web).                                                                    |

Without `maxWidth` / `maxHeight` / `imageQuality` the original capture is returned untouched.

**Errors:** `ErrorCode.permissionDenied` (camera refused), `ErrorCode.unsupported` (no camera, or Linux without GStreamer), `ErrorCode.invalidArgs` (bad option, or missing iOS `Info.plist` key), `ErrorCode.ioError`.

### `captureVideo`

Record a video with the system camera. Returns `null` if the user cancels.

```dart
Future<PlatformFile?> captureVideo({
  CameraFacing preferredCamera = CameraFacing.rear,
  Duration? maxDuration,
  bool withData = false,
})
```

`maxDuration` caps the recording length (best effort: some Android camera apps ignore it, browsers cannot enforce it). Other parameters and errors are as for `capturePhoto`.

### `retrieveLostCapture`

Recover a capture lost because Android destroyed the host Activity while the camera app was open. Call once on startup. Returns `LostCaptureResult.empty` on every other platform.

```dart
Future<LostCaptureResult> retrieveLostCapture()
```

```dart
final lost = await XueHuaFileOperations.instance.retrieveLostCapture();
if (!lost.isEmpty) {
  final file = lost.files.first; // lost.type is image or video
}
```

### `pickDirectory`

Pick a directory. Returns `null` if the user cancels.

```dart
Future<DirectoryResult?> pickDirectory({String? dialogTitle})
```

| Parameter     | Type      | Default | Description                                                  |
|---------------|-----------|---------|--------------------------------------------------------------|
| `dialogTitle` | `String?` | `null`  | Optional title for the native folder dialog where supported. |

**Returns:** `DirectoryResult?` — selected directory info, or `null` on cancel.

See [Directory picking](#directory-picking) for platform-specific `path` / `identifier` meaning.

### `saveFile`

Show a save-as dialog and write `bytes`, or copy from `sourcePath`.

```dart
Future<SaveFileResult?> saveFile({
  required String fileName,
  Uint8List? bytes,
  String? sourcePath,
  List<String>? allowedExtensions,
  String? dialogTitle,
})
```

| Parameter           | Type            | Default      | Description                                                                                       |
|---------------------|-----------------|--------------|---------------------------------------------------------------------------------------------------|
| `fileName`          | `String`        | *(required)* | Suggested file name shown in the save dialog / download name on Web.                              |
| `bytes`             | `Uint8List?`    | `null`       | File contents to write. Required on Web. On other platforms, provide `bytes` and/or `sourcePath`. |
| `sourcePath`        | `String?`       | `null`       | Path of an existing file to copy into the chosen destination. Not supported on Web.               |
| `allowedExtensions` | `List<String>?` | `null`       | Optional extension filter / hint for the save dialog where supported.                             |
| `dialogTitle`       | `String?`       | `null`       | Optional title for the native save dialog where supported.                                        |

**Returns:** `SaveFileResult?` — save result, or `null` on cancel.

**Throws:**

- `ErrorCode.invalidArgs` if both `bytes` and `sourcePath` are missing / empty
- `ErrorCode.unsupported` on Web when `bytes` is null (e.g. only `sourcePath` provided)

### `saveToGallery`

Save an image or video to the system gallery (or Pictures/Videos on desktop). On Web this triggers a browser download. There is no cancel dialog; failures throw.

```dart
Future<SaveToGalleryResult> saveToGallery({
  required String fileName,
  Uint8List? bytes,
  String? sourcePath,
  GalleryMediaType? type,
  String? albumName,
})
```

| Parameter    | Type                | Default      | Description                                                                                  |
|--------------|---------------------|--------------|----------------------------------------------------------------------------------------------|
| `fileName`   | `String`            | *(required)* | Display name including extension (used for MIME / type inference).                           |
| `bytes`      | `Uint8List?`        | `null`       | File contents to write. Provide `bytes` and/or `sourcePath`.                                 |
| `sourcePath` | `String?`           | `null`       | Path (or Android `content://` URI) of an existing image/video to copy.                       |
| `type`       | `GalleryMediaType?` | inferred     | `image` or `video`. Inferred from `fileName` / `sourcePath` when omitted.                    |
| `albumName`  | `String?`           | `null`       | Optional album / subdirectory. Custom albums on iOS/macOS require full photo library access. |

**Returns:** `SaveToGalleryResult` — `name`, optional filesystem `path`, and native `identifier`.

**Throws:**

- `ErrorCode.invalidArgs` if both `bytes` and `sourcePath` are missing, or the media type cannot be inferred
- `ErrorCode.permissionDenied` if gallery / storage permission is denied
- `ErrorCode.unsupported` on Web when `bytes` is null (e.g. only `sourcePath` provided)
- `ErrorCode.notFound` / `ErrorCode.ioError` on I/O failures

### `galleryPermissionStatus` / `requestGalleryPermission`

Check or request gallery write access. Status values match
[permission_handler](https://pub.dev/packages/permission_handler) `PermissionStatus`
(without `provisional`). Denial is a status, not an exception.

```dart
Future<GalleryPermissionStatus> galleryPermissionStatus({bool forAlbum = false});
Future<GalleryPermissionStatus> requestGalleryPermission({bool forAlbum = false});
```

| Parameter  | Type   | Default | Description                                                               |
|------------|--------|---------|---------------------------------------------------------------------------|
| `forAlbum` | `bool` | `false` | `true` requests read/write access needed for `saveToGallery(albumName:)`. |

`galleryPermissionStatus` never shows a prompt. `requestGalleryPermission` shows the system dialog **only** while PhotoKit status is still `notDetermined` ([WWDC20 10641](https://developer.apple.com/videos/play/wwdc2020/10641/), [requestAuthorization(for:handler:)](https://developer.apple.com/documentation/photos/phphotolibrary/requestauthorization(for:handler:))).

| PhotoKit `PHAuthorizationStatus` | Plugin status       | Meaning                                                     |
|----------------------------------|---------------------|-------------------------------------------------------------|
| `notDetermined`                  | `denied`            | Not asked yet; a request can still show a dialog            |
| `authorized`                     | `granted`           | Full Photos access                                          |
| `limited`                        | `limited`           | Limited library (iOS 14+); save works, custom albums do not |
| `restricted`                     | `restricted`        | OS blocked access (parental controls / MDM)                 |
| `denied`                         | `permanentlyDenied` | User refused; Apple will not prompt again                   |

Saving without a custom album is allowed when `status.isGranted || status.isLimited`. Custom albums need `status.isGranted`. If `status.isPermanentlyDenied` or `status.isRestricted`, call `openAppSettings()` after a user tap — do not jump to Settings from `requestGalleryPermission` itself.

| Platform        | Typical result                                                                                |
|-----------------|-----------------------------------------------------------------------------------------------|
| iOS             | PhotoKit `addOnly` or `readWrite` (`forAlbum`)                                                |
| macOS           | Always PhotoKit `readWrite` (`forAlbum` ignored; no add-only row in System Settings → Photos) |
| Android 24–28   | `WRITE_EXTERNAL_STORAGE`                                                                      |
| Android 29+     | Always `granted` (no `READ_MEDIA_*`)                                                          |
| Windows / Linux | Always `granted`                                                                              |
| Web             | Always `granted`                                                                              |

### `openAppSettings`

Open the OS settings UI so the user can enable Photos / storage access after a permanent denial.

```dart
Future<void> openAppSettings()
```

| Platform | Behavior                                               |
|----------|--------------------------------------------------------|
| iOS      | App Settings via `UIApplication.openSettingsURLString` |
| macOS    | System Settings → Privacy & Security → Photos          |
| Android  | Application details settings                           |
| Windows  | Windows Settings privacy / apps page                   |
| Linux    | No-op (no app Photos toggle)                           |
| Web      | No-op                                                  |

### `openFile`

Open a file with the system default application.

```dart
Future<void> openFile({String? path, String? identifier})
```

| Parameter    | Type      | Default | Description                                                                    |
|--------------|-----------|---------|--------------------------------------------------------------------------------|
| `path`       | `String?` | `null`  | Filesystem path (or platform-accessible path) to open.                         |
| `identifier` | `String?` | `null`  | Native identifier: Android content URI, iOS bookmark/URL, Web object URL, etc. |

At least one of `path` or `identifier` must be non-empty.

**Throws:**

- `ErrorCode.invalidArgs` if both are missing / empty
- `ErrorCode.unsupported` on Web when only a local `path` is provided (pass an object-URL `identifier` instead)

## Models

### `PlatformFile`

Represents a file selected or produced by the plugin.

| Field        | Type         | Description                                     |
|--------------|--------------|-------------------------------------------------|
| `name`       | `String`     | File name (e.g. `report.pdf`)                   |
| `size`       | `int`        | Size in bytes                                   |
| `path`       | `String?`    | Local path when available; `null` on Web        |
| `bytes`      | `Uint8List?` | File contents when `withData: true` or on Web   |
| `identifier` | `String?`    | Native unique id (URI, bookmark, object URL, …) |
| `hasBytes`   | `bool`       | Convenience getter: `bytes != null`             |

### `DirectoryResult`

Result of `pickDirectory`.

| Field        | Type      | Description                                                                |
|--------------|-----------|----------------------------------------------------------------------------|
| `path`       | `String`  | Display / filesystem path, or tree URI / folder name depending on platform |
| `name`       | `String`  | Directory display name                                                     |
| `identifier` | `String?` | Durable native id when available (e.g. iOS bookmark, Android tree URI)     |

### `SaveFileResult`

Result of `saveFile`.

| Field  | Type      | Description                                    |
|--------|-----------|------------------------------------------------|
| `name` | `String`  | Saved file name (e.g. download name on Web)    |
| `path` | `String?` | Absolute path on mobile/desktop; `null` on Web |

### `SaveToGalleryResult`

Result of `saveToGallery`.

| Field        | Type      | Description                                                                               |
|--------------|-----------|-------------------------------------------------------------------------------------------|
| `name`       | `String`  | Final file name                                                                           |
| `path`       | `String?` | Absolute path on desktop (and Android API 24–28); usually `null` on Android 10+           |
| `identifier` | `String?` | Android `content://` URI, iOS/macOS Photos `localIdentifier`, or `file://` URI on desktop |

### `FileType`

High-level filter for pick dialogs:

| Value             | Meaning                                                |
|-------------------|--------------------------------------------------------|
| `FileType.any`    | No type restriction                                    |
| `FileType.media`  | Images + videos (system photo picker on iOS / Android) |
| `FileType.image`  | Images (system photo picker on iOS / Android)          |
| `FileType.video`  | Videos (system photo picker on iOS / Android)          |
| `FileType.audio`  | Audio                                                  |
| `FileType.custom` | Rely on `allowedExtensions` / `allowedMimeTypes`       |

On iOS / Android, `image` / `video` / `media` without `allowedExtensions` / `allowedMimeTypes` uses the system photo picker (no photo permission required); passing custom filters keeps the document picker. iOS 13 falls back to the document picker.

### `CameraFacing`

`rear` (default) or `front`. A hint for `capturePhoto` / `captureVideo`.

### `LostCaptureResult`

| Field       | Type                       | Description                                        |
|-------------|----------------------------|----------------------------------------------------|
| `files`     | `List<PlatformFile>`       | Recovered capture (at most one file).              |
| `type`      | `GalleryMediaType?`        | `image` or `video`.                                |
| `exception` | `FileOperationsException?` | Set when the lost operation failed.                |
| `isEmpty`   | `bool`                     | `true` when nothing was recovered and no error.    |

### `GalleryMediaType`

| Value                    | Meaning |
|--------------------------|---------|
| `GalleryMediaType.image` | Image   |
| `GalleryMediaType.video` | Video   |

### `GalleryPermissionStatus`

Result of `galleryPermissionStatus` / `requestGalleryPermission`. Getters: `isDenied`, `isGranted`, `isRestricted`, `isLimited`, `isPermanentlyDenied`, `canSave`.

| Value               | Meaning                                                                                                  |
|---------------------|----------------------------------------------------------------------------------------------------------|
| `denied`            | Not requested yet (PhotoKit `notDetermined`), or denied on Android but the dialog can still be shown     |
| `granted`           | Full access to save to the gallery                                                                       |
| `restricted`        | OS restriction (parental controls). iOS / macOS only                                                     |
| `limited`           | Limited Photos Library. iOS 14+; saving still works, custom albums do not                                |
| `permanentlyDenied` | PhotoKit `.denied` or Android "Don't ask again"; dialog will not appear again — call `openAppSettings()` |

## Errors

Hard failures throw `FileOperationsException`:

| Property  | Type        | Description                 |
|-----------|-------------|-----------------------------|
| `code`    | `ErrorCode` | Machine-readable error code |
| `message` | `String`    | Human-readable message      |
| `details` | `Object?`   | Optional extra context      |

### `ErrorCode`

| Code               | Wire value          | Typical meaning                                                 |
|--------------------|---------------------|-----------------------------------------------------------------|
| `cancelled`        | `cancelled`         | Reserved for cancellation (user cancel normally returns `null`) |
| `permissionDenied` | `permission_denied` | Permission / access denied                                      |
| `invalidArgs`      | `invalid_args`      | Invalid method arguments                                        |
| `tooManyFiles`     | `too_many_files`    | Selection exceeded `maxFiles`                                   |
| `notFound`         | `not_found`         | File or resource not found                                      |
| `ioError`          | `io_error`          | I/O failure while reading/writing                               |
| `unsupported`      | `unsupported`       | Operation not supported on this platform / configuration        |
| `unknown`          | `unknown`           | Unexpected / unclassified error                                 |

## Links

- GitHub: [https://github.com/Matkurban/xue_hua_file_operations](https://github.com/Matkurban/xue_hua_file_operations)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Package skills: [Ship skills with packages](https://dart.dev/tools/pub/package-skills)
- License: [LICENSE](LICENSE)
