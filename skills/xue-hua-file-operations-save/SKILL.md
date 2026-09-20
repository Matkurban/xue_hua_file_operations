---
name: xue-hua-file-operations-save
description: >-
  Use when saving with XueHuaFileOperations: saveFile, saveToGallery,
  galleryPermissionStatus, requestGalleryPermission, openAppSettings,
  GalleryMediaType, GalleryPermissionStatus.
---

# XueHua file operations save

## Guidelines

* Use `XueHuaFileOperations.instance`.
* Provide at least one of `bytes` or a non-empty `sourcePath` for `saveFile` and `saveToGallery`. Otherwise the facade throws `ErrorCode.invalidArgs`.
* On Web, pass `bytes`. `sourcePath` is not supported and throws `ErrorCode.unsupported`.
* `saveFile` cancel returns `null`. `saveToGallery` has no cancel dialog; failures throw.
* `saveToGallery` takes optional `GalleryMediaType? type`. When omitted, type is inferred from `fileName`, then `sourcePath`. If inference fails, pass `type` or use a known media extension.
* Do not copy the platform-interface signature where `type` is required.
* Query permission with `galleryPermissionStatus` (no prompt). Request with `requestGalleryPermission` (prompt only while PhotoKit is `notDetermined`).
* Denial is a `GalleryPermissionStatus`, not an exception. Call `openAppSettings()` only after a user tap when status is `permanentlyDenied` or `restricted`.
* Save without `albumName` when `status.canSave` (`isGranted || isLimited`). Custom albums require `status.isGranted`. Pass `forAlbum: true` when you will use `albumName`.
* On macOS, `forAlbum` is ignored (always PhotoKit `readWrite`). Do not test Photos via `flutter run` from Cursor / VS Code.
* Catch `FileOperationsException`. `ErrorCode.permissionDenied` means the write was refused.

## Examples

### Save as (prefer path, fall back to bytes)

```dart
import 'dart:typed_data';

import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

final ops = XueHuaFileOperations.instance;
final PlatformFile? source = /* from pickFile */;

try {
  final result = await ops.saveFile(
    fileName: source?.name ?? 'export.txt',
    bytes: source?.path == null ? source?.bytes : null,
    sourcePath: source?.path,
  );
  if (result == null) {
    return; // cancelled
  }
  final savedPath = result.path;
  final savedName = result.name;
} on FileOperationsException catch (e) {
  // e.code, e.message
}
```

### Save to gallery and handle Photos denial

```dart
final ops = XueHuaFileOperations.instance;

final status = await ops.requestGalleryPermission();
if (status.isPermanentlyDenied || status.isRestricted) {
  // After a user tap:
  await ops.openAppSettings();
  return;
}
if (!status.canSave) {
  return;
}

final result = await ops.saveToGallery(
  fileName: 'shot.jpg',
  bytes: jpegBytes,
  sourcePath: existingPath,
);
final id = result.identifier;
```

### Custom album (needs full access)

```dart
final status = await ops.requestGalleryPermission(forAlbum: true);
if (!status.isGranted) {
  return;
}
await ops.saveToGallery(
  fileName: 'clip.mp4',
  sourcePath: videoPath,
  type: GalleryMediaType.video,
  albumName: 'My Album',
);
```

## Read when needed

* `saveFile`, `saveToGallery`, result types, `GalleryMediaType` (including exact extensions): [references/save-api.md](references/save-api.md)
* Permission methods and `GalleryPermissionStatus` members: [references/gallery-permissions.md](references/gallery-permissions.md)
* Host plist / entitlements: skill `xue-hua-file-operations-setup`
* Error codes: skill `xue-hua-file-operations-errors`
