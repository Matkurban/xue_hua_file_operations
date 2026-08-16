/// Result of [XueHuaFileOperations.saveToGallery].
class SaveToGalleryResult {
  const SaveToGalleryResult({required this.name, this.path, this.identifier});

  /// Final file name in the gallery / Pictures folder.
  final String name;

  /// Absolute filesystem path when available.
  ///
  /// Desktop platforms typically return a path. On Android API 29+ this is
  /// usually `null` because MediaStore uses scoped storage.
  final String? path;

  /// Native identifier: Android `content://` URI, iOS/macOS Photos
  /// `localIdentifier`, or a `file://` URI on desktop.
  final String? identifier;

  factory SaveToGalleryResult.fromMap(Map<Object?, Object?> map) {
    return SaveToGalleryResult(
      name: map['name'] as String? ?? '',
      path: map['path'] as String?,
      identifier: map['identifier'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'name': name,
    'path': path,
    'identifier': identifier,
  };
}
