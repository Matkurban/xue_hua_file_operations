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
