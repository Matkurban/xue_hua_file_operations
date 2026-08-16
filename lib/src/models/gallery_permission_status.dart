/// Status of gallery / Photos write access.
///
/// Mirrors [permission_handler](https://pub.dev/packages/permission_handler)
/// `PermissionStatus` (without `provisional`, which is notification-only).
enum GalleryPermissionStatus {
  /// Not requested yet, or denied on Android but the dialog can still be shown.
  denied,

  /// The user granted access to save to the gallery.
  granted,

  /// The OS denied access (parental controls, MDM). iOS / macOS only.
  restricted,

  /// Limited Photos Library access. iOS 14+ only.
  ///
  /// Saving still works; creating or looking up a custom album does not.
  limited,

  /// The permission dialog will not be shown again; the user must use Settings.
  ///
  /// iOS / macOS: the user denied the prompt. Android: "Don't ask again".
  permanentlyDenied;

  String get wireName => name;

  /// Parses a method-channel wire name. Unknown values map to [denied].
  static GalleryPermissionStatus fromWireName(String? name) {
    switch (name) {
      case 'granted':
        return GalleryPermissionStatus.granted;
      case 'restricted':
        return GalleryPermissionStatus.restricted;
      case 'limited':
        return GalleryPermissionStatus.limited;
      case 'permanentlyDenied':
        return GalleryPermissionStatus.permanentlyDenied;
      case 'denied':
      default:
        return GalleryPermissionStatus.denied;
    }
  }

  /// Whether media can be saved without a custom album.
  bool get canSave => isGranted || isLimited;
}

extension GalleryPermissionStatusGetters on GalleryPermissionStatus {
  bool get isDenied => this == GalleryPermissionStatus.denied;

  bool get isGranted => this == GalleryPermissionStatus.granted;

  bool get isRestricted => this == GalleryPermissionStatus.restricted;

  bool get isLimited => this == GalleryPermissionStatus.limited;

  bool get isPermanentlyDenied =>
      this == GalleryPermissionStatus.permanentlyDenied;
}
