# xue_hua_file_operations

English | [中文](README_zh.md)

Cross-platform Flutter plugin for picking files and directories, saving files (save-as), saving images/videos to the gallery, and opening files with the system default application.

**Repository:** [https://github.com/Matkurban/xue_hua_file_operations](https://github.com/Matkurban/xue_hua_file_operations)

## Features

- Pick a single file (`pickFile`) or multiple files (`pickFiles`)
- Filter by high-level `FileType`, file extensions, and/or MIME types
- Optional `maxFiles` limit for multi-select (validated after selection)
- Pick a directory (`pickDirectory`)
- Save-as dialog (`saveFile`) from bytes or by copying a source path
- Save an image or video to the system gallery (`saveToGallery`)
- Query or request gallery permission (`galleryPermissionStatus` / `requestGalleryPermission`)
- Open a file with the system handler (`openFile`)
- Unified `PlatformFile` model and typed `FileOperationsException` / `ErrorCode`

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  xue_hua_file_operations: ^1.1.0
```

Then run:

```bash
flutter pub get
```

## Supported platforms

| Platform | Supported | Notes |
|----------|-----------|--------|
| Android | Yes | Storage Access Framework (SAF) / Activity Result APIs; `saveToGallery` uses MediaStore / public Pictures |
| iOS | Yes | `UIDocumentPicker` / document interaction; `saveToGallery` uses PhotoKit |
| macOS | Yes | Native `NSOpenPanel` / `NSSavePanel`; `saveToGallery` uses PhotoKit |
| Windows | Yes | Native file / folder dialogs; `saveToGallery` writes Pictures / Videos |
| Linux | Yes | Native file / folder dialogs; `saveToGallery` writes XDG Pictures / Videos |
| Web | Yes | HTML `<input type="file">` and Blob download; `saveToGallery` is unsupported |

### Path and identifier behavior

| Platform | `path` | Notes |
|----------|--------|--------|
| Android / iOS / Desktop | Usually non-null (cache copy or filesystem path) | `identifier` keeps the native URI / URL / bookmark |
| Web | Always `null` | `bytes` are always loaded; save triggers a download; open needs an object-URL `identifier` |

### Directory picking

| Platform | What you get | Notes |
|----------|--------------|--------|
| Android | SAF tree URI in `path` / `identifier` | Persistable read permission is taken when possible |
| iOS | Display `path` + security-scoped **bookmark** in `identifier` | Prefer `identifier` for later access / `openFile`; raw path alone is not durable |
| macOS / Windows / Linux | Real filesystem path | Native folder dialogs |
| Web | Folder name via `webkitdirectory` | Not a real FS path; capability depends on the browser |

## Platform setup and permissions

### Android

**Permissions for pick / save-as / open:** No dangerous storage permissions (`READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` / media permissions) are required. Those APIs use the system document picker (SAF).

**Permissions for `saveToGallery`:**

- **API 24–28:** the plugin declares `WRITE_EXTERNAL_STORAGE` with `maxSdkVersion=28` and requests it at runtime. Denial throws `ErrorCode.permissionDenied`. You can also call `requestGalleryPermission` first and inspect `GalleryPermissionStatus`.
- **API 29+:** no storage permission. The plugin inserts via MediaStore (`RELATIVE_PATH` + `IS_PENDING`).
- **API 33+:** do **not** add `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` for this API. Inserting media the app creates does not need them.

Do not rely on `requestLegacyExternalStorage`.

**FileProvider:** The plugin registers its own `FileProvider` for opening files via content URIs. No host-app FileProvider setup is required for basic use.

**Host Activity (required):** The host `Activity` must extend `FlutterFragmentActivity` (not plain `FlutterActivity`), because pickers use Activity Result contracts:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

### iOS

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

See the example app entitlements under `example/macos/Runner/`.

### Windows

**Permissions:** None. Uses native system file and folder dialogs. `saveToGallery` writes to the user Pictures or Videos known folder. No extra manifest entries are required for this plugin.

### Linux

**Permissions:** None. Uses native system file and folder dialogs. `saveToGallery` writes to XDG Pictures or Videos (there is no system photo library). No extra desktop permissions are required for this plugin.

### Web

**Permissions:** None at the app level. The browser shows its own file picker / download UI. A user gesture is typically required to open the picker.

**Limitations:**

- `path` is always `null`
- Picked files always include `bytes`
- `saveFile` requires `bytes` (`sourcePath` is not supported)
- `saveToGallery` is not supported (`ErrorCode.unsupported`)
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
if (status.isPermanentlyDenied) {
  // Direct the user to system Settings; the dialog will not appear again.
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

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `withData` | `bool` | `false` | When `true`, load file contents into `PlatformFile.bytes`. On Web, bytes are always loaded regardless of this flag. |
| `dialogTitle` | `String?` | `null` | Optional title for the native dialog where supported (desktop). May be ignored on some platforms (e.g. Android SAF, Web). |
| `type` | `FileType` | `FileType.any` | High-level filter: `any`, `image`, `video`, `audio`, or `custom`. |
| `allowedExtensions` | `List<String>?` | `null` | Allowed extensions (with or without leading `.`), e.g. `['pdf', 'txt']`. Used especially with `FileType.custom` or as an additional filter. |
| `allowedMimeTypes` | `List<String>?` | `null` | Allowed MIME types, e.g. `['application/pdf']`. Behavior depends on the platform picker. |

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

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `maxFiles` | `int?` | `null` | Maximum number of files allowed. `null` means unlimited. If provided, must be `>= 1`. If the user selects more than `maxFiles`, throws `FileOperationsException` with `ErrorCode.tooManyFiles`. |
| `withData` | `bool` | `false` | Same as `pickFile`. |
| `dialogTitle` | `String?` | `null` | Same as `pickFile`. |
| `type` | `FileType` | `FileType.any` | Same as `pickFile`. |
| `allowedExtensions` | `List<String>?` | `null` | Same as `pickFile`. |
| `allowedMimeTypes` | `List<String>?` | `null` | Same as `pickFile`. |

**Returns:** `List<PlatformFile>?` — selected files, or `null` on cancel.

**Throws:** `FileOperationsException` with `ErrorCode.invalidArgs` if `maxFiles` is provided and `< 1`.

### `pickDirectory`

Pick a directory. Returns `null` if the user cancels.

```dart
Future<DirectoryResult?> pickDirectory({String? dialogTitle})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dialogTitle` | `String?` | `null` | Optional title for the native folder dialog where supported. |

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

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fileName` | `String` | *(required)* | Suggested file name shown in the save dialog / download name on Web. |
| `bytes` | `Uint8List?` | `null` | File contents to write. Required on Web. On other platforms, provide `bytes` and/or `sourcePath`. |
| `sourcePath` | `String?` | `null` | Path of an existing file to copy into the chosen destination. Not supported on Web. |
| `allowedExtensions` | `List<String>?` | `null` | Optional extension filter / hint for the save dialog where supported. |
| `dialogTitle` | `String?` | `null` | Optional title for the native save dialog where supported. |

**Returns:** `SaveFileResult?` — save result, or `null` on cancel.

**Throws:**

- `ErrorCode.invalidArgs` if both `bytes` and `sourcePath` are missing / empty
- `ErrorCode.unsupported` on Web when `bytes` is null (e.g. only `sourcePath` provided)

### `saveToGallery`

Save an image or video to the system gallery (or Pictures/Videos on desktop). There is no cancel dialog; failures throw.

```dart
Future<SaveToGalleryResult> saveToGallery({
  required String fileName,
  Uint8List? bytes,
  String? sourcePath,
  GalleryMediaType? type,
  String? albumName,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fileName` | `String` | *(required)* | Display name including extension (used for MIME / type inference). |
| `bytes` | `Uint8List?` | `null` | File contents to write. Provide `bytes` and/or `sourcePath`. |
| `sourcePath` | `String?` | `null` | Path (or Android `content://` URI) of an existing image/video to copy. |
| `type` | `GalleryMediaType?` | inferred | `image` or `video`. Inferred from `fileName` / `sourcePath` when omitted. |
| `albumName` | `String?` | `null` | Optional album / subdirectory. Custom albums on iOS/macOS require full photo library access. |

**Returns:** `SaveToGalleryResult` — `name`, optional filesystem `path`, and native `identifier`.

**Throws:**

- `ErrorCode.invalidArgs` if both `bytes` and `sourcePath` are missing, or the media type cannot be inferred
- `ErrorCode.permissionDenied` if gallery / storage permission is denied
- `ErrorCode.unsupported` on Web
- `ErrorCode.notFound` / `ErrorCode.ioError` on I/O failures

### `galleryPermissionStatus` / `requestGalleryPermission`

Check or request gallery write access. Status values match
[permission_handler](https://pub.dev/packages/permission_handler) `PermissionStatus`
(without `provisional`). Denial is a status, not an exception.

```dart
Future<GalleryPermissionStatus> galleryPermissionStatus({bool forAlbum = false});
Future<GalleryPermissionStatus> requestGalleryPermission({bool forAlbum = false});
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `forAlbum` | `bool` | `false` | `true` requests read/write access needed for `saveToGallery(albumName:)`. |

`galleryPermissionStatus` never shows a prompt. `requestGalleryPermission` shows one only when the status is still undetermined.

Saving without a custom album is allowed when `status.isGranted || status.isLimited`. Custom albums need `status.isGranted`. If `status.isPermanentlyDenied`, send the user to system Settings.

| Platform | Typical result |
|----------|----------------|
| iOS | PhotoKit `addOnly` or `readWrite` (`forAlbum`) |
| macOS | Always PhotoKit `readWrite` (no add-only toggle) |
| Android 24–28 | `WRITE_EXTERNAL_STORAGE` |
| Android 29+ | Always `granted` (no `READ_MEDIA_*`) |
| Windows / Linux | Always `granted` |
| Web | Throws `ErrorCode.unsupported` |

### `openFile`

Open a file with the system default application.

```dart
Future<void> openFile({String? path, String? identifier})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `path` | `String?` | `null` | Filesystem path (or platform-accessible path) to open. |
| `identifier` | `String?` | `null` | Native identifier: Android content URI, iOS bookmark/URL, Web object URL, etc. |

At least one of `path` or `identifier` must be non-empty.

**Throws:**

- `ErrorCode.invalidArgs` if both are missing / empty
- `ErrorCode.unsupported` on Web when only a local `path` is provided (pass an object-URL `identifier` instead)

## Models

### `PlatformFile`

Represents a file selected or produced by the plugin.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | File name (e.g. `report.pdf`) |
| `size` | `int` | Size in bytes |
| `path` | `String?` | Local path when available; `null` on Web |
| `bytes` | `Uint8List?` | File contents when `withData: true` or on Web |
| `identifier` | `String?` | Native unique id (URI, bookmark, object URL, …) |
| `hasBytes` | `bool` | Convenience getter: `bytes != null` |

### `DirectoryResult`

Result of `pickDirectory`.

| Field | Type | Description |
|-------|------|-------------|
| `path` | `String` | Display / filesystem path, or tree URI / folder name depending on platform |
| `name` | `String` | Directory display name |
| `identifier` | `String?` | Durable native id when available (e.g. iOS bookmark, Android tree URI) |

### `SaveFileResult`

Result of `saveFile`.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Saved file name (e.g. download name on Web) |
| `path` | `String?` | Absolute path on mobile/desktop; `null` on Web |

### `SaveToGalleryResult`

Result of `saveToGallery`.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Final file name |
| `path` | `String?` | Absolute path on desktop (and Android API 24–28); usually `null` on Android 10+ |
| `identifier` | `String?` | Android `content://` URI, iOS/macOS Photos `localIdentifier`, or `file://` URI on desktop |

### `FileType`

High-level filter for pick dialogs:

| Value | Meaning |
|-------|---------|
| `FileType.any` | No type restriction |
| `FileType.image` | Images |
| `FileType.video` | Videos |
| `FileType.audio` | Audio |
| `FileType.custom` | Rely on `allowedExtensions` / `allowedMimeTypes` |

### `GalleryMediaType`

| Value | Meaning |
|-------|---------|
| `GalleryMediaType.image` | Image |
| `GalleryMediaType.video` | Video |

### `GalleryPermissionStatus`

Result of `galleryPermissionStatus` / `requestGalleryPermission`. Getters: `isDenied`, `isGranted`, `isRestricted`, `isLimited`, `isPermanentlyDenied`, `canSave`.

| Value | Meaning |
|-------|---------|
| `denied` | Not requested yet, or denied on Android but the dialog can still be shown |
| `granted` | Full access to save to the gallery |
| `restricted` | OS restriction (parental controls). iOS / macOS only |
| `limited` | Limited Photos Library. iOS 14+; saving still works, custom albums do not |
| `permanentlyDenied` | Dialog will not appear again; user must change Settings |

## Errors

Hard failures throw `FileOperationsException`:

| Property | Type | Description |
|----------|------|-------------|
| `code` | `ErrorCode` | Machine-readable error code |
| `message` | `String` | Human-readable message |
| `details` | `Object?` | Optional extra context |

### `ErrorCode`

| Code | Wire value | Typical meaning |
|------|------------|-----------------|
| `cancelled` | `cancelled` | Reserved for cancellation (user cancel normally returns `null`) |
| `permissionDenied` | `permission_denied` | Permission / access denied |
| `invalidArgs` | `invalid_args` | Invalid method arguments |
| `tooManyFiles` | `too_many_files` | Selection exceeded `maxFiles` |
| `notFound` | `not_found` | File or resource not found |
| `ioError` | `io_error` | I/O failure while reading/writing |
| `unsupported` | `unsupported` | Operation not supported on this platform / configuration |
| `unknown` | `unknown` | Unexpected / unclassified error |

## Links

- GitHub: [https://github.com/Matkurban/xue_hua_file_operations](https://github.com/Matkurban/xue_hua_file_operations)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- License: [LICENSE](LICENSE)
