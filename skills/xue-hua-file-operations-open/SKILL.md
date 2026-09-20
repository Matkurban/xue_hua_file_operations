---
name: xue-hua-file-operations-open
description: >-
  Use when opening a file with XueHuaFileOperations.openFile using a
  filesystem path or native identifier (content URI, bookmark, object URL).
---

# XueHua file operations open

## Guidelines

* Use `XueHuaFileOperations.instance.openFile`.
* Pass a non-empty `path` and/or a non-empty `identifier`. If both are missing, the facade throws `ErrorCode.invalidArgs`.
* On Web, pass the object-URL `identifier` from a previous pick. A local `path` alone throws `ErrorCode.unsupported`.
* On iOS, prefer `DirectoryResult.identifier` (bookmark) when opening a picked directory.
* On Android, a local `path` is shared through the plugin FileProvider. Do not add a host FileProvider for basic use.
* Catch `FileOperationsException` for hard failures.

## Examples

### Open a picked file

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

final ops = XueHuaFileOperations.instance;
final file = await ops.pickFile();
if (file == null) {
  return;
}

try {
  await ops.openFile(path: file.path, identifier: file.identifier);
} on FileOperationsException catch (e) {
  // e.code == ErrorCode.unsupported on Web if only path was set
}
```

### Web: object URL only

```dart
await XueHuaFileOperations.instance.openFile(identifier: file.identifier);
```

## Read when needed

* Full `openFile` signature and per-platform notes: [references/open-api.md](references/open-api.md)
* How pick sets `path` / `identifier`: skill `xue-hua-file-operations-pick`
* Error codes: skill `xue-hua-file-operations-errors`
