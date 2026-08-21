# Changelog

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
