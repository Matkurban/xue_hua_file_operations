# xue_hua_file_operations

English | [中文](README_zh.md)

Cross-platform Flutter plugin for picking files and directories, saving files (save-as), and opening files with the system default application.

**Repository:** [https://github.com/Matkurban/xue_hua_file_operations](https://github.com/Matkurban/xue_hua_file_operations)

## Features

- Pick a single file (`pickFile`) or multiple files (`pickFiles`)
- Filter by high-level `FileType`, file extensions, and/or MIME types
- Optional `maxFiles` limit for multi-select (validated after selection)
- Pick a directory (`pickDirectory`)
- Save-as dialog (`saveFile`) from bytes or by copying a source path
- Open a file with the system handler (`openFile`)
- Unified `PlatformFile` model and typed `FileOperationsException` / `ErrorCode`

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  xue_hua_file_operations: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Supported platforms

| Platform | Supported | Notes |
|----------|-----------|--------|
| Android | Yes | Storage Access Framework (SAF) / Activity Result APIs |
| iOS | Yes | `UIDocumentPicker` / document interaction |
| macOS | Yes | Native `NSOpenPanel` / `NSSavePanel` |
| Windows | Yes | Native file / folder dialogs |
| Linux | Yes | Native file / folder dialogs |
| Web | Yes | HTML `<input type="file">` and Blob download |

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

**Permissions:** No dangerous storage permissions (`READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` / media permissions) are required. The plugin uses the system document picker (SAF).

**FileProvider:** The plugin registers its own `FileProvider` for opening files via content URIs. No host-app FileProvider setup is required for basic use.

**Host Activity (required):** The host `Activity` must extend `FlutterFragmentActivity` (not plain `FlutterActivity`), because pickers use Activity Result contracts:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

### iOS

**Permissions:** No extra Info.plist privacy keys (such as photo library usage descriptions) are required for document pick / save / open via this plugin’s document-picker APIs.

**Directory access:** When the user picks a directory, the plugin stores a security-scoped bookmark in `DirectoryResult.identifier` (prefixed). Prefer that identifier for later access or `openFile`; the display `path` alone is not durable across app launches.

### macOS

**Entitlements (App Sandbox):** If your app uses App Sandbox (typical for Mac App Store / Flutter macOS apps), add user-selected file access:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

See the example app entitlements under `example/macos/Runner/`.

### Windows

**Permissions:** None. Uses native system file and folder dialogs. No extra manifest entries are required for this plugin.

### Linux

**Permissions:** None. Uses native system file and folder dialogs. No extra desktop permissions are required for this plugin.

### Web

**Permissions:** None at the app level. The browser shows its own file picker / download UI. A user gesture is typically required to open the picker.

**Limitations:**

- `path` is always `null`
- Picked files always include `bytes`
- `saveFile` requires `bytes` (`sourcePath` is not supported)
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

### `FileType`

High-level filter for pick dialogs:

| Value | Meaning |
|-------|---------|
| `FileType.any` | No type restriction |
| `FileType.image` | Images |
| `FileType.video` | Videos |
| `FileType.audio` | Audio |
| `FileType.custom` | Rely on `allowedExtensions` / `allowedMimeTypes` |

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
