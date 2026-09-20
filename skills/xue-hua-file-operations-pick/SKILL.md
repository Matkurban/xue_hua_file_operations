---
name: xue-hua-file-operations-pick
description: >-
  Use when picking files or directories with XueHuaFileOperations
  (pickFile, pickFiles, pickDirectory, FileType, PlatformFile, DirectoryResult).
---

# XueHua file operations pick

## Guidelines

* Use `XueHuaFileOperations.instance`.
* Treat user cancel as `null`. Do not catch `ErrorCode.cancelled` for cancel.
* Pass `maxFiles` only when it is `>= 1`. A smaller value throws `ErrorCode.invalidArgs` before the picker opens.
* When the user selects more files than `maxFiles`, catch `FileOperationsException` with `ErrorCode.tooManyFiles`.
* On iOS / Android, `FileType.image`, `FileType.video`, and `FileType.media` without `allowedExtensions` / `allowedMimeTypes` open the system photo picker. Pass custom filters to keep the document picker.
* Set `withData: true` only when the app needs `PlatformFile.bytes`. On Web, bytes are always loaded and `path` is always `null`.
* After `pickDirectory` on iOS, keep `DirectoryResult.identifier` (security-scoped bookmark). Do not rely on the display `path` across launches.
* Catch `FileOperationsException` for hard failures.

## Examples

### Single file

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

final ops = XueHuaFileOperations.instance;

try {
  final file = await ops.pickFile(withData: false, type: FileType.any);
  if (file == null) {
    return; // cancelled
  }
  final name = file.name;
  final path = file.path;
  final bytes = file.hasBytes ? file.bytes : null;
} on FileOperationsException catch (e) {
  // e.code, e.message, e.details
}
```

### Multiple files with a limit

```dart
final files = await XueHuaFileOperations.instance.pickFiles(
  maxFiles: 5,
  type: FileType.image,
);
if (files == null) {
  return; // cancelled
}
```

### Directory

```dart
final dir = await XueHuaFileOperations.instance.pickDirectory();
if (dir == null) {
  return; // cancelled
}
final displayPath = dir.path;
final durableId = dir.identifier;
```

## Read when needed

* Full signatures for `pickFile`, `pickFiles`, `pickDirectory`, `FileType`, `PlatformFile`, `DirectoryResult`: [references/pick-api.md](references/pick-api.md)
* Platform path / identifier rules: skill `xue-hua-file-operations-setup`
* Error codes: skill `xue-hua-file-operations-errors`
