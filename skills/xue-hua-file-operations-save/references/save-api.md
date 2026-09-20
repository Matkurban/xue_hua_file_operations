# Save API reference

Every public member below is from `package:xue_hua_file_operations`.
Serialization helpers (`fromMap`, `toMap`, `wireName`, `fromWireName`, `fromFileName`) are public but are for the method channel / type inference. App code may call `GalleryMediaType.fromFileName` if it needs the same inference the facade uses; prefer passing `type` explicitly when the extension is not a known media suffix.

Import:

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
```

Access the API through `XueHuaFileOperations.instance`.

The facade method `saveToGallery` takes `GalleryMediaType? type` (optional, inferred). Do not copy the platform-interface signature, where `type` is `required`.

---

## `XueHuaFileOperations.saveFile`

Show a save-as dialog and write `bytes`, or copy from `sourcePath`. Returns `null` if the user cancels.

```dart
Future<SaveFileResult?> saveFile({
  required String fileName,
  Uint8List? bytes,
  String? sourcePath,
  List<String>? allowedExtensions,
  String? dialogTitle,
})
```

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `fileName` | `String` | required | Suggested file name in the save dialog / download name on Web. |
| `bytes` | `Uint8List?` | `null` | File contents to write. **Required on Web.** On other platforms provide `bytes` and/or `sourcePath`. |
| `sourcePath` | `String?` | `null` | Path of an existing file to copy into the chosen destination. **Not supported on Web.** |
| `allowedExtensions` | `List<String>?` | `null` | Optional extension filter / hint for the save dialog where supported. |
| `dialogTitle` | `String?` | `null` | Optional title for the native save dialog where supported. |

**Returns:** `SaveFileResult?` — save result, or `null` on cancel.

**Throws:**

- `ErrorCode.invalidArgs` when `bytes` is null and `sourcePath` is null or empty. Message: `Either bytes or sourcePath must be provided`.
- `ErrorCode.unsupported` on Web when `bytes` is null (for example only `sourcePath` was provided). Message: `Web saveFile requires bytes; sourcePath is not supported`.
- `ErrorCode.notFound` when a native source file is missing (macOS / Windows / Linux).
- `ErrorCode.ioError` on I/O failure.

---

## `XueHuaFileOperations.saveToGallery`

Save an image or video to the system gallery (or Pictures / Videos on desktop). On Web this triggers a browser download. There is **no cancel dialog**; failures throw.

```dart
Future<SaveToGalleryResult> saveToGallery({
  required String fileName,
  Uint8List? bytes,
  String? sourcePath,
  GalleryMediaType? type,
  String? albumName,
})
```

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `fileName` | `String` | required | Display name including extension (used for MIME / type inference). |
| `bytes` | `Uint8List?` | `null` | File contents to write. Provide `bytes` and/or `sourcePath`. **Required on Web.** |
| `sourcePath` | `String?` | `null` | Path (or Android `content://` URI) of an existing image/video to copy. **Not supported on Web.** |
| `type` | `GalleryMediaType?` | inferred | `image` or `video`. When omitted, inferred from `fileName`, then from `sourcePath`, via `GalleryMediaType.fromFileName`. |
| `albumName` | `String?` | `null` | Optional album / subdirectory. Custom albums on iOS/macOS require full photo library access (`status.isGranted`). Ignored on Web. |

Inference order when `type` is omitted:

1. `GalleryMediaType.fromFileName(fileName)`
2. else if `sourcePath != null`, `GalleryMediaType.fromFileName(sourcePath)`
3. else throw `ErrorCode.invalidArgs`

**Returns:** `SaveToGalleryResult` (`name`, optional `path`, optional `identifier`).

**Throws:**

- `ErrorCode.invalidArgs` when `bytes` is null and `sourcePath` is null or empty.
- `ErrorCode.invalidArgs` when media type cannot be inferred. Message: `Unable to infer image/video type from fileName; pass GalleryMediaType or use a media extension`. `details` is `{'fileName': fileName}`.
- `ErrorCode.permissionDenied` if gallery / storage permission is denied.
- `ErrorCode.unsupported` on Web when `bytes` is null. Message: `Web saveToGallery requires bytes; sourcePath is not supported`.
- `ErrorCode.notFound` / `ErrorCode.ioError` on I/O failures.
- `ErrorCode.unknown` if the native side returns no result map.

Saving without a custom album is allowed when `status.canSave` (`isGranted || isLimited`). Custom albums need `status.isGranted`.

---

## `SaveFileResult`

Result of `saveFile`.

```dart
const SaveFileResult({required this.name, this.path});
```

| Member | Type | Description |
| --- | --- | --- |
| `name` | `String` | Saved file name (download name on Web). |
| `path` | `String?` | Absolute path on mobile/desktop; **`null` on Web**. |

### `factory SaveFileResult.fromMap(Map<Object?, Object?> map)`

- `name`: `map['name'] as String? ?? ''`
- `path`: `map['path'] as String?`

Do not use in app code.

### `Map<String, Object?> toMap()`

Returns `{name, path}`. Do not use in app code.

---

## `SaveToGalleryResult`

Result of `saveToGallery`.

```dart
const SaveToGalleryResult({required this.name, this.path, this.identifier});
```

| Member | Type | Description |
| --- | --- | --- |
| `name` | `String` | Final file name in the gallery / Pictures folder. |
| `path` | `String?` | Absolute filesystem path when available. Desktop typically returns a path. On Android API 29+ this is usually `null` (MediaStore scoped storage). |
| `identifier` | `String?` | Android `content://` URI, iOS/macOS Photos `localIdentifier`, or a `file://` URI on desktop. Web returns only `name`. |

### `factory SaveToGalleryResult.fromMap(Map<Object?, Object?> map)`

- `name`: `map['name'] as String? ?? ''`
- `path`: `map['path'] as String?`
- `identifier`: `map['identifier'] as String?`

Do not use in app code.

### `Map<String, Object?> toMap()`

Returns `{name, path, identifier}`. Do not use in app code.

---

## `GalleryMediaType`

Media kind for `saveToGallery`.

```dart
enum GalleryMediaType {
  image,
  video;
}
```

| Value | Meaning |
| --- | --- |
| `GalleryMediaType.image` | Image |
| `GalleryMediaType.video` | Video |

### `String get wireName`

Returns `name` (`image` or `video`). Method-channel serialization. Do not use in app code.

### `static GalleryMediaType? fromWireName(String? name)`

| `name` | Result |
| --- | --- |
| `'image'` | `GalleryMediaType.image` |
| `'video'` | `GalleryMediaType.video` |
| anything else, including `null` | `null` |

Do not use in app code.

### `static GalleryMediaType? fromFileName(String fileName)`

Takes the substring after the last `.`, lowercased. Returns `null` when there is no `.`, when `.` is the last character, or when the extension is unknown.

**Image extensions** (exact set in source):

`jpg`, `jpeg`, `png`, `gif`, `webp`, `heic`, `heif`, `bmp`, `tif`, `tiff`, `dng`, `avif`, `ico`

**Video extensions** (exact set in source):

`mp4`, `mov`, `m4v`, `avi`, `mkv`, `webm`, `3gp`, `3g2`, `mpeg`, `mpg`, `wmv`, `flv`, `ts`, `mts`, `m2ts`
