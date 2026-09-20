---
name: xue-hua-file-operations-errors
description: >-
  Use when handling FileOperationsException or ErrorCode from
  XueHuaFileOperations (invalidArgs, tooManyFiles, permissionDenied,
  unsupported, cancel vs null).
---

# XueHua file operations errors

## Guidelines

* Catch `FileOperationsException`, not a generic `Exception`, for plugin failures.
* Read `e.code` (`ErrorCode`), `e.message` (`String`), and optional `e.details`.
* Treat user cancel on `pickFile`, `pickFiles`, `pickDirectory`, and `saveFile` as `null`. Do not handle those as `ErrorCode.cancelled`.
* `ErrorCode.cancelled` is reserved for native cancellation that surfaces as a thrown exception (for example Android Activity detach).
* Compare enum values (`ErrorCode.invalidArgs`), not wire strings (`invalid_args`). `e.code.code` is the wire string.
* Do not call `ErrorCode.fromCode` in app code unless mapping a raw wire string.

## Examples

### Typed catch

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

final ops = XueHuaFileOperations.instance;

try {
  final files = await ops.pickFiles(maxFiles: 3);
  if (files == null) {
    return; // user cancelled
  }
} on FileOperationsException catch (e) {
  switch (e.code) {
    case ErrorCode.invalidArgs:
      // maxFiles < 1
      break;
    case ErrorCode.tooManyFiles:
      // user selected more than maxFiles
      break;
    case ErrorCode.permissionDenied:
      break;
    case ErrorCode.unsupported:
      break;
    case ErrorCode.notFound:
    case ErrorCode.ioError:
    case ErrorCode.cancelled:
    case ErrorCode.unknown:
      break;
  }
}
```

## Read when needed

* Full `FileOperationsException` / `ErrorCode` members, wire strings, and Dart-layer `invalidArgs` table: [references/error-codes.md](references/error-codes.md)
