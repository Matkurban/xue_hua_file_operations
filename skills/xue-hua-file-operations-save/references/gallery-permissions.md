# Gallery permission API reference

Every public member below is from `package:xue_hua_file_operations`.
`wireName` and `fromWireName` are method-channel helpers. Do not use them in app code.

Denial is a **status**, not an exception. Catch `FileOperationsException` with `ErrorCode.permissionDenied` only when `saveToGallery` itself fails after a denied write.

---

## `XueHuaFileOperations.galleryPermissionStatus`

Current gallery permission **without** showing a system prompt.

```dart
Future<GalleryPermissionStatus> galleryPermissionStatus({
  bool forAlbum = false,
})
```

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `forAlbum` | `bool` | `false` | Pass `true` when the next `saveToGallery` will include `albumName`. **Ignored on macOS** (PhotoKit is always `readWrite`). |

**Returns:** `GalleryPermissionStatus`.

On Web this always returns `GalleryPermissionStatus.granted`.

---

## `XueHuaFileOperations.requestGalleryPermission`

Request gallery permission, showing a system prompt if undetermined.

```dart
Future<GalleryPermissionStatus> requestGalleryPermission({
  bool forAlbum = false,
})
```

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `forAlbum` | `bool` | `false` | `true` requests the read access needed to create or look up a custom album. **Ignored on macOS** (always `readWrite`). |

**Returns:** the new `GalleryPermissionStatus`. Denial is a status, not an exception.

On Web this always returns `GalleryPermissionStatus.granted`.

On iOS / macOS the system dialog appears **only** while PhotoKit status is `notDetermined`. If the result is `permanentlyDenied` or `restricted`, call `openAppSettings()` after a **user tap**. Do not jump to Settings from `requestGalleryPermission` itself.

On macOS, launching via Cursor / VS Code can silently deny Photos (TCC attributes the request to the IDE). Prefer the system Terminal or opening the built `.app`.

---

## `XueHuaFileOperations.openAppSettings`

Open the OS settings UI for this app (or Photos privacy on macOS).

```dart
Future<void> openAppSettings()
```

Does not request permission itself. Use after `GalleryPermissionStatus.permanentlyDenied` or `GalleryPermissionStatus.restricted`.

| Platform | Behavior |
| --- | --- |
| iOS | App Settings via `UIApplication.openSettingsURLString` |
| macOS | System Settings → Privacy & Security → Photos |
| Android | Application details settings |
| Windows | Windows Settings privacy / apps page |
| Linux | No-op success (no app Photos toggle) |
| Web | No-op |

---

## `GalleryPermissionStatus`

Status of gallery / Photos write access. Mirrors `permission_handler` `PermissionStatus` without `provisional`.

```dart
enum GalleryPermissionStatus {
  denied,
  granted,
  restricted,
  limited,
  permanentlyDenied;
}
```

| Value | Meaning |
| --- | --- |
| `denied` | Not requested yet (PhotoKit `notDetermined`), or denied on Android but the dialog can still be shown. |
| `granted` | Full access to save to the gallery. Custom albums allowed. |
| `restricted` | OS restriction (parental controls / MDM). iOS / macOS only. |
| `limited` | Limited Photos Library. iOS 14+ only. Saving still works; creating or looking up a custom album does not. |
| `permanentlyDenied` | The permission dialog will not be shown again. iOS / macOS: PhotoKit `.denied`. Android: "Don't ask again". After a user action, call `openAppSettings()`. |

PhotoKit mapping:

| PhotoKit `PHAuthorizationStatus` | Plugin status | Meaning |
| --- | --- | --- |
| `notDetermined` | `denied` | Not asked yet; a request can still show a dialog |
| `authorized` | `granted` | Full Photos access |
| `limited` | `limited` | Limited library (iOS 14+); save works, custom albums do not |
| `restricted` | `restricted` | OS blocked access |
| `denied` | `permanentlyDenied` | User refused; Apple will not prompt again |

Typical platform results:

| Platform | Typical result |
| --- | --- |
| iOS | PhotoKit `addOnly`, or `readWrite` when `forAlbum` is true |
| macOS | Always PhotoKit `readWrite` (`forAlbum` ignored) |
| Android 24–28 | `WRITE_EXTERNAL_STORAGE` |
| Android 29+ | Always `granted` (no `READ_MEDIA_*`) |
| Windows / Linux | Always `granted` |
| Web | Always `granted` |

### `String get wireName`

Returns `name` (`denied`, `granted`, `restricted`, `limited`, `permanentlyDenied`). Do not use in app code.

### `static GalleryPermissionStatus fromWireName(String? name)`

| `name` | Result |
| --- | --- |
| `'granted'` | `granted` |
| `'restricted'` | `restricted` |
| `'limited'` | `limited` |
| `'permanentlyDenied'` | `permanentlyDenied` |
| `'denied'` or anything else, including `null` | `denied` |

Do not use in app code.

### `bool get canSave`

`isGranted || isLimited`. Use this to decide whether `saveToGallery` without `albumName` is allowed.

### Extension `GalleryPermissionStatusGetters`

Defined on `GalleryPermissionStatus`:

| Getter | True when |
| --- | --- |
| `isDenied` | `this == GalleryPermissionStatus.denied` |
| `isGranted` | `this == GalleryPermissionStatus.granted` |
| `isRestricted` | `this == GalleryPermissionStatus.restricted` |
| `isLimited` | `this == GalleryPermissionStatus.limited` |
| `isPermanentlyDenied` | `this == GalleryPermissionStatus.permanentlyDenied` |
