# Pick API reference

Every public member below is from `package:xue_hua_file_operations`.
Serialization helpers (`fromMap`, `toMap`, `wireName`) are public but are for the method channel. Do not use them in app code.

Import:

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
```

Access the API through `XueHuaFileOperations.instance`.

---

## `XueHuaFileOperations.pickFile`

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

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `withData` | `bool` | `false` | When `true`, load contents into `PlatformFile.bytes`. On Web, bytes are always loaded regardless of this flag. |
| `dialogTitle` | `String?` | `null` | Optional native dialog title where supported (desktop). May be ignored (Android SAF, Web). |
| `type` | `FileType` | `FileType.any` | High-level filter. See `FileType` below. |
| `allowedExtensions` | `List<String>?` | `null` | Extensions with or without a leading `.`, e.g. `['pdf', 'txt']`. Used especially with `FileType.custom` or as an extra filter. |
| `allowedMimeTypes` | `List<String>?` | `null` | MIME types, e.g. `['application/pdf']`. Behavior depends on the platform picker. |

**Returns:** `PlatformFile?` — selected file, or `null` on cancel.

**Throws:** `FileOperationsException` for hard failures (see the errors skill). Cancel is `null`, not an exception.

On iOS / Android, `FileType.image` / `video` / `media` **without** `allowedExtensions` / `allowedMimeTypes` opens the system photo picker (iOS `PHPickerViewController` on 14+, Android Photo Picker). Custom filters keep the document picker. iOS 13 falls back to the document picker.

---

## `XueHuaFileOperations.pickFiles`

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

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `maxFiles` | `int?` | `null` | Maximum files allowed. `null` means unlimited. If provided, must be `>= 1`. If the user selects more than `maxFiles`, throws `FileOperationsException` with `ErrorCode.tooManyFiles`. |
| `withData` | `bool` | `false` | Same as `pickFile`. |
| `dialogTitle` | `String?` | `null` | Same as `pickFile`. |
| `type` | `FileType` | `FileType.any` | Same as `pickFile`. |
| `allowedExtensions` | `List<String>?` | `null` | Same as `pickFile`. |
| `allowedMimeTypes` | `List<String>?` | `null` | Same as `pickFile`. |

**Returns:** `List<PlatformFile>?` — selected files, or `null` on cancel.

**Throws:**

- `ErrorCode.invalidArgs` when `maxFiles` is provided and `< 1` (Dart layer, before the native picker). Message: `maxFiles must be >= 1 when provided`. `details` is `{'maxFiles': maxFiles}`.
- `ErrorCode.tooManyFiles` when the user selects more files than `maxFiles`.

---

## `XueHuaFileOperations.pickDirectory`

Pick a directory. Returns `null` if the user cancels.

```dart
Future<DirectoryResult?> pickDirectory({String? dialogTitle})
```

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `dialogTitle` | `String?` | `null` | Optional title for the native folder dialog where supported. |

**Returns:** `DirectoryResult?` — selected directory, or `null` on cancel.

| Platform | What `path` / `identifier` mean |
| --- | --- |
| Android | SAF tree URI in both; persistable read permission is taken when possible |
| iOS | Display `path` + security-scoped bookmark in `identifier`. Prefer `identifier` for later access / `openFile` |
| macOS / Windows / Linux | Real filesystem path |
| Web | Folder name via `webkitdirectory` (not a real FS path) |

---

## `FileType`

High-level filter for pick dialogs.

```dart
enum FileType {
  any,
  media,
  image,
  video,
  audio,
  custom;
}
```

| Value | Meaning |
| --- | --- |
| `FileType.any` | No type restriction |
| `FileType.media` | Images + videos. On iOS / Android this opens the system photo picker when no custom filters are set. On Web the accept string is `image/*,video/*`. |
| `FileType.image` | Images. Photo picker on iOS / Android without custom filters. |
| `FileType.video` | Videos. Photo picker on iOS / Android without custom filters. |
| `FileType.audio` | Audio |
| `FileType.custom` | Rely on `allowedExtensions` / `allowedMimeTypes` |

### `String get wireName`

Returns `name` (`any`, `media`, `image`, `video`, `audio`, `custom`). Method-channel serialization. Do not use in app code.

---

## `PlatformFile`

A file selected or produced by the plugin.

```dart
const PlatformFile({
  required this.name,
  required this.size,
  this.path,
  this.bytes,
  this.identifier,
});
```

| Member | Type | Description |
| --- | --- | --- |
| `name` | `String` | File name, e.g. `report.pdf` |
| `size` | `int` | Size in bytes |
| `path` | `String?` | Local path when available; **always `null` on Web** |
| `bytes` | `Uint8List?` | File contents when `withData: true`, or **always on Web** |
| `identifier` | `String?` | Native unique id (Android URI, iOS bookmark/URL, Web object URL, …) |

### `bool get hasBytes`

`bytes != null`.

### `factory PlatformFile.fromMap(Map<Object?, Object?> map)`

Deserializes a method-channel map.

- `name`: `map['name'] as String? ?? ''`
- `size`: `(map['size'] as num?)?.toInt() ?? 0`
- `path`: `map['path'] as String?`
- `identifier`: `map['identifier'] as String?`
- `bytes`: `Uint8List` as-is, or `Uint8List.fromList` from a `List`; otherwise `null`

Do not use in app code.

### `Map<String, Object?> toMap()`

Returns `{name, size, path, bytes, identifier}`. Do not use in app code.

### `String toString()`

`PlatformFile(name: …, size: …, path: …, hasBytes: …, identifier: …)`.

---

## `DirectoryResult`

Result of `pickDirectory`.

```dart
const DirectoryResult({
  required this.path,
  required this.name,
  this.identifier,
});
```

| Member | Type | Description |
| --- | --- | --- |
| `path` | `String` | Display / filesystem path, or tree URI / folder name depending on platform |
| `name` | `String` | Directory display name |
| `identifier` | `String?` | Durable native id when available (iOS bookmark, Android tree URI) |

### `factory DirectoryResult.fromMap(Map<Object?, Object?> map)`

- `path`: `map['path'] as String? ?? ''`
- `name`: `map['name'] as String? ?? ''`
- `identifier`: `map['identifier'] as String?`

Do not use in app code.

### `Map<String, Object?> toMap()`

Returns `{path, name, identifier}`. Do not use in app code.
