# xue_hua_file_operations

Cross-platform Flutter plugin for file picking, save-as, and opening with the
system default app. Supports Android, iOS, macOS, Windows, Linux, and Web.

## Features

- `pickFile` / `pickFiles` with extension & MIME filters
- Optional `maxFiles` limit for multi-select (post-selection validation)
- `pickDirectory`
- `saveFile` (bytes or copy from path)
- `openFile` via system handler
- Unified `PlatformFile` model and `FileOperationsException` error codes

## Usage

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

## Platform notes

| Platform | `path` | Notes |
|----------|--------|--------|
| Android / iOS / Desktop | Usually non-null (cache copy or filesystem path) | `identifier` keeps native URI/URL |
| Web | Always `null` | `bytes` always loaded; save triggers download; open needs object URL `identifier` |

### Directory picking

| Platform | What you get | Notes |
|----------|--------------|--------|
| Android | SAF tree URI in `path` / `identifier` | Persistable read permission is taken when possible |
| iOS | Display `path` + security-scoped **bookmark** in `identifier` | Prefer `identifier` for later access/`openFile`; raw path alone is not durable |
| macOS / Windows / Linux | Real filesystem path | Native folder dialogs |
| Web | Folder name via `webkitdirectory` | Not a real FS path; capability depends on the browser |

### Android host activity

File pickers use Activity Result contracts. The host `Activity` must extend
`FlutterFragmentActivity` (not plain `FlutterActivity`).

Cancel returns `null`. Hard failures throw `FileOperationsException`.

## Error codes

`cancelled` (reserved), `permission_denied`, `invalid_args`, `too_many_files`,
`not_found`, `io_error`, `unsupported`, `unknown`.
