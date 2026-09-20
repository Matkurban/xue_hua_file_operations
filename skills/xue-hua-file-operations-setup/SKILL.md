---
name: xue-hua-file-operations-setup
description: >-
  Use when adding xue_hua_file_operations, configuring Android/iOS/macOS
  permissions, FlutterFragmentActivity, Info.plist, entitlements, or accessing
  XueHuaFileOperations.instance.
---

# XueHua file operations setup

## Guidelines

* Import `package:xue_hua_file_operations/xue_hua_file_operations.dart`.
* Call `XueHuaFileOperations.instance`. The constructor is private.
* Do not use `XueHuaFileOperationsPlatform`, `MethodChannelXueHuaFileOperations`, or `XueHuaFileOperationsWeb` from app code.
* On Android, make the host `Activity` extend `FlutterFragmentActivity`.
* For pick / save-as / open on Android, do not add dangerous storage or `READ_MEDIA_*` permissions.
* For `saveToGallery` on iOS, add `NSPhotoLibraryAddUsageDescription`. Add `NSPhotoLibraryUsageDescription` when using `albumName`.
* For sandboxed macOS, add `com.apple.security.files.user-selected.read-write`. For Photos, also add `com.apple.security.personal-information.photos-library` and the same Info.plist keys as iOS.
* Treat Web `path` as always `null`. Load `bytes` from picks. Require `bytes` for save APIs. Open files with an object-URL `identifier`.
* After adding the package, install these skills with `dart run skills@ get`.

## Examples

### Singleton access

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

final ops = XueHuaFileOperations.instance;
```

### Android host Activity

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

## Read when needed

* Full platform checklist, path/identifier table, and plist/entitlement snippets: [references/platform-setup.md](references/platform-setup.md)
* Pick APIs: skill `xue-hua-file-operations-pick`
* Save / gallery APIs: skill `xue-hua-file-operations-save`
* Open API: skill `xue-hua-file-operations-open`
* Exceptions: skill `xue-hua-file-operations-errors`
