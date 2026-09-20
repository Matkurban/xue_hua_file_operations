# Errors API reference

Every public member below is from `package:xue_hua_file_operations`.
`ErrorCode.fromCode` and `ErrorCode.code` are used to map method-channel `PlatformException.code` strings. App code should read `exception.code` (the enum) and compare to `ErrorCode` values.

Import:

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
```

User cancel on `pickFile`, `pickFiles`, `pickDirectory`, and `saveFile` returns **`null`**. Do not catch `ErrorCode.cancelled` for that case. `cancelled` is reserved for native cancellation that surfaces as a hard failure (for example an Android Activity detach while a picker is in flight).

---

## `FileOperationsException`

Typed exception thrown by `XueHuaFileOperations` on hard failures. Implements `Exception`.

```dart
FileOperationsException(
  this.code, {
  required this.message,
  this.details,
});
```

| Member | Type | Description |
| --- | --- | --- |
| `code` | `ErrorCode` | Machine-readable error code (positional, required). |
| `message` | `String` | Human-readable message (named, required). |
| `details` | `Object?` | Optional extra context (named, optional, default `null`). |

There is no default constructor other than this. `code` is positional; `message` is named and required.

### `String toString()`

```text
FileOperationsException(<wire code>): <message>
```

When `details != null`, appends ` details=<details>`.

Example: `FileOperationsException(invalid_args): maxFiles must be >= 1 when provided details={maxFiles: 0}`.

Catch this type specifically:

```dart
try {
  await XueHuaFileOperations.instance.pickFiles(maxFiles: 5);
} on FileOperationsException catch (e) {
  switch (e.code) {
    case ErrorCode.tooManyFiles:
      break;
    case ErrorCode.invalidArgs:
      break;
    default:
      break;
  }
}
```

---

## `ErrorCode`

Unified error codes for `FileOperationsException` / `PlatformException`.

```dart
enum ErrorCode {
  cancelled('cancelled'),
  permissionDenied('permission_denied'),
  invalidArgs('invalid_args'),
  tooManyFiles('too_many_files'),
  notFound('not_found'),
  ioError('io_error'),
  unsupported('unsupported'),
  unknown('unknown');
}
```

| Enum value | `code` (wire string) | Typical meaning |
| --- | --- | --- |
| `ErrorCode.cancelled` | `cancelled` | Reserved for cancellation. User cancel on pick / save-as normally returns `null`. |
| `ErrorCode.permissionDenied` | `permission_denied` | Permission / access denied (for example gallery write on Android 24–28). |
| `ErrorCode.invalidArgs` | `invalid_args` | Invalid method arguments (Dart-layer checks listed below). |
| `ErrorCode.tooManyFiles` | `too_many_files` | Selection exceeded `maxFiles`. |
| `ErrorCode.notFound` | `not_found` | File or resource not found. |
| `ErrorCode.ioError` | `io_error` | I/O failure while reading or writing. |
| `ErrorCode.unsupported` | `unsupported` | Operation not supported on this platform / configuration (Web `sourcePath`, Web `openFile` with only `path`). |
| `ErrorCode.unknown` | `unknown` | Unexpected / unclassified error, including a null `saveToGallery` native result. |

### `final String code`

Wire value stored on the enum (`permission_denied`, not `permissionDenied`).

### `const ErrorCode(this.code)`

Enum constructor. Do not call from app code.

### `static ErrorCode fromCode(String? code)`

Looks up `value.code == code`. Returns `ErrorCode.unknown` when `code` is `null` or does not match any value. Do not use in app code unless mapping a raw wire string.

---

## Dart-layer `invalidArgs` checks (facade)

These run in `XueHuaFileOperations` before the platform call:

| Call | Condition | Message | `details` |
| --- | --- | --- | --- |
| `pickFiles` | `maxFiles != null && maxFiles < 1` | `maxFiles must be >= 1 when provided` | `{'maxFiles': maxFiles}` |
| `saveFile` | `bytes == null` and `sourcePath` null or empty | `Either bytes or sourcePath must be provided` | none |
| `saveToGallery` | `bytes == null` and `sourcePath` null or empty | `Either bytes or sourcePath must be provided` | none |
| `saveToGallery` | type cannot be inferred from `fileName` / `sourcePath` | `Unable to infer image/video type from fileName; pass GalleryMediaType or use a media extension` | `{'fileName': fileName}` |
| `openFile` | both `path` and `identifier` null or empty | `Either path or identifier must be provided` | none |

Web-only `unsupported` (after the facade check passes):

| Call | Condition | Message |
| --- | --- | --- |
| `saveFile` | `bytes == null` | `Web saveFile requires bytes; sourcePath is not supported` |
| `saveToGallery` | `bytes == null` | `Web saveToGallery requires bytes; sourcePath is not supported` |
| `openFile` | `identifier` is null or empty | `Opening local paths is not supported on Web; pass identifier (object URL)` |
