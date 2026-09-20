# Platform setup reference

Source of truth: host-app configuration required by `xue_hua_file_operations` 1.3.3.
App code must use `XueHuaFileOperations.instance`. The constructor is private.

```dart
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';

final ops = XueHuaFileOperations.instance;
```

Do not construct `XueHuaFileOperations()`. Do not call `XueHuaFileOperationsPlatform` from app code.

## Installation

```yaml
dependencies:
  xue_hua_file_operations: ^1.3.3
```

```bash
flutter pub get
```

After the dependency is added, install these package skills in the consumer project:

```bash
dart run skills@ get
# or
dart run skills@ get --all
```

## Supported platforms

| Platform | Supported | Native surface |
| --- | --- | --- |
| Android | Yes | SAF / Activity Result; `saveToGallery` uses MediaStore or public Pictures |
| iOS | Yes (13.0+) | `PHPickerViewController` (iOS 14+) for media; otherwise `UIDocumentPicker`; `saveToGallery` uses PhotoKit |
| macOS | Yes | `NSOpenPanel` / `NSSavePanel`; `saveToGallery` uses PhotoKit |
| Windows | Yes | Native file / folder dialogs; `saveToGallery` writes Pictures / Videos |
| Linux | Yes | Native file / folder dialogs; `saveToGallery` writes XDG Pictures / Videos |
| Web | Yes | HTML `<input type="file">` and Blob download; `saveToGallery` downloads |

Minimum iOS version is **13.0** (Flutter default `IPHONEOS_DEPLOYMENT_TARGET`). Host apps do not need to raise it to 14.0.

## Path and identifier

| Platform | `path` | Notes |
| --- | --- | --- |
| Android / iOS / desktop | Usually non-null (cache copy or filesystem path) | `identifier` keeps the native URI / URL / bookmark |
| Web | Always `null` | Picked files always include `bytes`; save downloads; `openFile` needs an object-URL `identifier` |

## Directory picking

| Platform | Result | Notes |
| --- | --- | --- |
| Android | SAF tree URI in `path` / `identifier` | Persistable read permission is taken when possible |
| iOS | Display `path` + security-scoped bookmark in `identifier` | Prefer `identifier` for later access / `openFile`; raw path alone is not durable |
| macOS / Windows / Linux | Real filesystem path | Native folder dialogs |
| Web | Folder name via `webkitdirectory` | Not a real FS path; capability depends on the browser |

## Android

Pick / save-as / open: no dangerous storage permissions (`READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` / media permissions). Those APIs use SAF.

`saveToGallery`:

- API 24–28: plugin declares `WRITE_EXTERNAL_STORAGE` with `maxSdkVersion=28` and requests it at runtime. Denial throws `ErrorCode.permissionDenied`. Call `requestGalleryPermission` first if the app should inspect `GalleryPermissionStatus`.
- API 29+: no storage permission. Insert via MediaStore (`RELATIVE_PATH` + `IS_PENDING`).
- API 33+: do not add `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` for this API.

Do not rely on `requestLegacyExternalStorage`.

The plugin registers its own `FileProvider`. Host apps do not need a FileProvider for basic `openFile` use.

**Required:** the host `Activity` must extend `FlutterFragmentActivity`, not `FlutterActivity`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

## iOS

Pick / save-as / open: no extra Info.plist privacy keys.

`saveToGallery` — add to the host `Info.plist`:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app saves images and videos to your photo library.</string>
```

When passing `albumName`, also add:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>This app saves images and videos to albums in your photo library.</string>
```

PhotoKit shows the system prompt only while status is `notDetermined`. After Don’t Allow, `requestGalleryPermission` returns `permanentlyDenied` with no dialog. Call `openAppSettings()` after a user tap (`UIApplication.openSettingsURLString`).

To re-test the first prompt, delete the app or reset Simulator Privacy settings.

When the user picks a directory, keep `DirectoryResult.identifier` (prefixed security-scoped bookmark). The display `path` is not durable across launches.

## macOS

App Sandbox (typical Flutter macOS / Mac App Store apps) needs:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

For `saveToGallery` also add:

```xml
<key>com.apple.security.personal-information.photos-library</key>
<true/>
```

Add the same `NSPhotoLibraryAddUsageDescription` / `NSPhotoLibraryUsageDescription` keys as iOS in `macos/Runner/Info.plist`.

Without the Photos entitlement, PhotoKit often returns denied immediately and never shows a prompt.

macOS always requests PhotoKit `readWrite`. `forAlbum` is ignored. System Settings → Privacy & Security → Photos only lists read/write clients.

**TCC responsible process:** `flutter run -d macos` from Cursor or VS Code can silently deny Photos and never list this app. Test from system Terminal, or:

```bash
flutter build macos
open build/macos/Build/Products/Debug/<your_app>.app
```

After a recorded denial, `openAppSettings()` opens the Photos pane. To reset during development:

```bash
tccutil reset Photos com.your.bundle.id
```

## Windows

No extra permissions or manifest entries. `saveToGallery` writes the user Pictures or Videos known folder.

## Linux

No extra desktop permissions. `saveToGallery` writes XDG Pictures or Videos. There is no system photo library. `openAppSettings` succeeds without opening a pane.

## Web

No app-level permissions. A user gesture is typically required to open the picker.

- `path` is always `null`
- Picked files always include `bytes`
- `saveFile` requires `bytes` (`sourcePath` is not supported)
- `saveToGallery` triggers a browser download (`bytes` required; `albumName` is ignored)
- `galleryPermissionStatus` / `requestGalleryPermission` always return `granted`
- `openAppSettings` is a no-op
- `openFile` requires an object-URL `identifier`
