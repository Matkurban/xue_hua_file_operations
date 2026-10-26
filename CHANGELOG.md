## 1.5.3

* macOS: add the same automated dialog test hooks as Linux/Windows (`XUE_HUA_TEST_PICK_FILE` / `PICK_FILES` / `PICK_DIR` / `SAVE_FILE` / `OPEN_FILE=skip`, literal `CANCEL`) so `flutter_driver` can cover pick / save / open without native choosers. Multi-file paths are colon-separated (like Linux).
* Example: Debug App Sandbox temporary exceptions for `/tmp` and `/var/folders` so dialog hooks can read driver fixtures; skip the Photos Settings dialog under automation envs so later taps are not blocked; `flutter_driver` dismisses the dialog when it still appears and accepts `permission_denied` for `saveToGallery` when Photos TCC is denied for the launch parent.
* iOS / macOS: short-circuit `requestGalleryPermission` / gallery save when PhotoKit status is already determined — calling `PHPhotoLibrary.requestAuthorization` again could hang on some iOS Simulator / TCC automation setups.
* Docs: document macOS dialog hooks in English and Chinese READMEs; mention macOS colon-separated multi-file paths in the example driver header.

## 1.5.2

* Windows: add the same automated dialog test hooks as Linux (`XUE_HUA_TEST_PICK_FILE` / `PICK_FILES` / `PICK_DIR` / `SAVE_FILE` / `OPEN_FILE=skip`, literal `CANCEL`) so `flutter_driver` can cover pick / save / open without native choosers. Multi-file paths are semicolon-separated on Windows.
* Docs: document Windows dialog hooks in English and Chinese READMEs; mention Windows in the example `flutter_driver` header.

## 1.5.1

* Linux: add automated dialog test hooks for `pickFile` / `pickFiles` / `pickDirectory` / `saveFile` / `openFile` (`XUE_HUA_TEST_PICK_*`, `XUE_HUA_TEST_SAVE_FILE`, `XUE_HUA_TEST_OPEN_FILE=skip`, literal `CANCEL`) so `flutter_driver` can cover non-camera APIs without interacting with GTK choosers.
* Example: give every demo action a `ValueKey`, expand `flutter_driver` coverage (gallery permission, pick / save / open, camera, save-to-gallery), and add cancel / tooManyFiles / unsupported edge-case drivers.

## 1.5.0

* **Camera capture.** Add `capturePhoto` (take a photo) and `captureVideo` (record a video) with `preferredCamera` (`CameraFacing.rear` / `front`), photo `maxWidth` / `maxHeight` / `imageQuality`, video `maxDuration` and `withData`. Both return a `PlatformFile?` (`null` on cancel).
* Add `retrieveLostCapture` + `LostCaptureResult` to recover a capture when Android destroys the host Activity while the camera app is open (other platforms return an empty result).
* Android: camera intents through `FileProvider`, runtime `CAMERA` permission when the host manifest declares it (`ErrorCode.permissionDenied` on refusal, `ErrorCode.unsupported` without a camera app), EXIF-preserving resize / recompress. Add the `androidx.exifinterface` dependency and camera `<queries>`.
* iOS: `UIImagePickerController` camera with permission check, front / rear selection and video duration limit; requires `NSCameraUsageDescription` (and `NSMicrophoneUsageDescription` for video).
* Web: uses the HTML `capture` attribute (mobile browsers) and resizes photos on a canvas; desktop browsers fall back to the file chooser.
* macOS: AVFoundation capture with a native preview sheet, built-in / external camera selection, camera + microphone authorization (`ErrorCode.permissionDenied`), photo resize / quality and video duration limit. Requires the `com.apple.security.device.camera` / `device.audio-input` entitlements and `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`.
* Windows: Media Foundation capture engine with a native preview window, JPEG photos (WIC resize / quality) and H.264/AAC MP4 videos; `E_ACCESSDENIED` maps to `ErrorCode.permissionDenied`, no camera to `ErrorCode.unsupported`. Verified on Windows 11 with a USB webcam; `XUE_HUA_CAMERA_TEST_AUTO=1` auto-presses the shutter for UI tests.
* Linux: GStreamer + GTK preview dialog (JPEG photos, MP4/H.264 or WebM videos). GStreamer is detected through pkg-config at build time; without it the capture methods throw `ErrorCode.unsupported`. `XUE_HUA_CAMERA_TEST_SOURCE` / `XUE_HUA_CAMERA_TEST_AUTO` environment variables allow camera-less testing.
* Add `NOTICE` with the attribution for code adapted from the Flutter `image_picker` packages (BSD-3-Clause).

## 1.4.0

- update `com.android.tools.build:gradle` to `9.1.0` version
- this version build need `compileSdk` = `37`
- update example android project version

## 1.3.3

* Ship Package Skills under `skills/` for AI agents (`dart run skills@ get`).
* Fix English and Chinese README: replace `^lasted` with `^1.3.3`, add a Package skills section, and translate the iOS minimum-version note in the English README.

## 1.3.2 

- update android package version

## 1.3.1

- The Gradle tool version has been downgraded to 8.13.2.

## 1.3.0

* **iOS: fix picking photos/videos.** `FileType.image` / `video` (without custom extension / MIME filters) now opens `PHPickerViewController` (iOS 14+) instead of the Files document picker, which cannot browse the photo library. iOS 13 falls back to the document picker.
* **Android: use the system Photo Picker** (`PickVisualMedia` / `PickMultipleVisualMedia`) for `FileType.image` / `video` instead of the SAF document UI.
* Add `FileType.media` (images + videos) mapped to the photo picker on iOS / Android, `image/*,video/*` on Web, and combined image/video filters on desktop.
* Android: fail in-flight operations with `cancelled` when the Activity detaches so Dart Futures no longer hang; report `size` as 64-bit; merge `allowedMimeTypes` with extension-derived MIME types (matching iOS); move pick/save file I/O off the main thread.
* iOS: move picked-file copying and `withData` reads off the main thread; `openFile` opens local files directly via the document interaction controller (skipping a doomed `UIApplication.open` round trip); balance security-scoped access in delegate callbacks.
* macOS: security-scoped access around picked-file reads and `saveFile` source copies (sandbox); `saveFile` reports `not_found` for missing sources; file reads run off the main thread.
* Windows: fix `IFileDialog::SetFileTypes` dangling-pointer filter (undefined behavior); implement `type` / `allowedMimeTypes` filtering; report `size` as 64-bit (no >2GB overflow); normalize `file:///` identifiers to forward slashes; validate save-file writes; `saveFile` reports `not_found` for missing sources.
* Linux: validate stream states in `saveFile` / `withData` reads and report `not_found` / `io_error` instead of silently succeeding; add `media` filter; hide the "All files" bypass when a specific type filter is requested.
* Update iOS / macOS podspec metadata to match the package version.

## 1.2.1

* Require Flutter 3.44+ (Dart 3.12+) to match Swift Package Manager plugin support with `FlutterFramework`.
* iOS: declare the plugin minimum as 13.0 (Flutter's default) so host apps no longer need to raise `IPHONEOS_DEPLOYMENT_TARGET` to 14.0. `UTType` document pickers and PhotoKit access levels still run on iOS 14+ with iOS 13 fallbacks.

## 1.2.0

* iOS / macOS: always call `PHPhotoLibrary.requestAuthorization` so TCC can record this app (do not skip when `authorizationStatus` is already `.denied`).
* macOS gallery permission always uses PhotoKit `readWrite` (`forAlbum` is ignored). System Settings → Photos only lists read/write clients.
* Copy gallery media into the app temp directory before PhotoKit import (security-scoped read on macOS).
* Add `openAppSettings()` to open the app or Photos privacy settings after `permanentlyDenied` / `restricted`.
* Document that `flutter run -d macos` from Cursor/VS Code can silently deny Photos (TCC responsible process).

## 1.1.1

* Web: `saveToGallery` triggers a browser download instead of throwing `unsupported`.
* Web: `galleryPermissionStatus` / `requestGalleryPermission` return `granted`.

## 1.1.0

* Add `saveToGallery` to save images and videos to the system gallery (Android, iOS, macOS, Windows, Linux).
* Add `galleryPermissionStatus` / `requestGalleryPermission` returning `GalleryPermissionStatus` (`denied`, `granted`, `restricted`, `limited`, `permanentlyDenied`).
* Android: API 24–28 writes the public Pictures/Movies folders and scans with `MediaScannerConnection`; API 29+ uses MediaStore `RELATIVE_PATH` / `IS_PENDING` without storage permissions.
* iOS / macOS: PhotoKit (`PHAccessLevel.addOnly`, or `readWrite` when `albumName` is set). macOS permission requests always use `readWrite`.
* Windows / Linux: write to the user Pictures or Videos folder with unique filenames. Gallery permission APIs return `granted`.
* Web: `saveToGallery` and gallery permission APIs throw `ErrorCode.unsupported`.

## 1.0.2

* Fix Android `FileUriExposedException` when opening files via `openFile` (`exposed beyond app through ClipData.Item.getUri()`).
* Stop falling back to `file://` URIs when `FileProvider.getUriForFile` fails; surface the real error instead.
* Normalize `file://` identifiers to local `File` paths and share them through `FileProvider` `content://` URIs.
* Set `ClipData` on the view chooser Intent and grant read-only URI permission for more reliable cross-app opens.
* Register a dedicated `XueHuaFileOperationsFileProvider` subclass instead of `androidx.core.content.FileProvider`, avoiding manifest collisions with the host app or other plugins that previously caused `Couldn't find meta-data for provider with authority`.

## 1.0.1

* Fix `openFile` failure on Android 11+ (API Level 30/31+) by adding `<queries>` declarations for `ACTION_VIEW` in plugin `AndroidManifest.xml`.
* Optimize Android `openFile` logic to prioritize local `FileProvider` URIs for picked files.
* Improve MIME type inference from file extensions when ContentResolver returns null or generic MIME types.
* Add `Intent.createChooser` and fallback mechanism for opening files across all Android versions.

## 1.0.0

* Initial stable release.
* Singleton API via `XueHuaFileOperations.instance`.
* File operations: `pickFile`, `pickFiles`, `pickDirectory`, `saveFile`, `openFile`.
* Models: `PlatformFile`, `DirectoryResult`, `SaveFileResult`, `FileType`.
* Typed errors: `FileOperationsException` with unified `ErrorCode` values.
* Supported platforms: Android, iOS, macOS, Windows, Linux, and Web.
