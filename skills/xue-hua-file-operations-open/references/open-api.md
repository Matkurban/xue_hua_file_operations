# Open API reference

Every public member below is from `package:xue_hua_file_operations`.

Import:

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
```

Access the API through `XueHuaFileOperations.instance`.

---

## `XueHuaFileOperations.openFile`

Open `path` or `identifier` with the system default application.

```dart
Future<void> openFile({String? path, String? identifier})
```

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `path` | `String?` | `null` | Filesystem path (or platform-accessible path) to open. |
| `identifier` | `String?` | `null` | Native identifier: Android content URI, iOS bookmark/URL, Web object URL, etc. |

At least one of `path` or `identifier` must be non-null and non-empty.

**Returns:** `void` on success.

**Throws:**

- `ErrorCode.invalidArgs` when both `path` and `identifier` are null or empty. Message: `Either path or identifier must be provided`. This check runs in Dart before the platform call.
- `ErrorCode.unsupported` on Web when only a local `path` is provided. Message: `Opening local paths is not supported on Web; pass identifier (object URL)`. Pass the object-URL `identifier` from a previous pick (Web `pickFile` / `pickFiles` always set `identifier` via `URL.createObjectURL`).
- Other `FileOperationsException` codes from the native side (for example `notFound`, `ioError`).

### Platform notes

| Platform | How to open |
| --- | --- |
| Android | Prefer a local path (plugin shares through its own FileProvider `content://` URI) or a content URI `identifier`. |
| iOS | Local files open via the document interaction controller. For a picked directory, prefer `DirectoryResult.identifier` (security-scoped bookmark). |
| macOS / Windows / Linux | Filesystem `path` or `file://` identifier. |
| Web | `identifier` must be an object URL. `path` alone always throws `unsupported`. |

When both are provided, the platform implementation receives both. On Web only a non-empty `identifier` is used.
