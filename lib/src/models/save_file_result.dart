/// Result of [XueHuaFileOperations.saveFile].
class SaveFileResult {
  const SaveFileResult({required this.name, this.path});

  /// Saved file name (e.g. download name on Web).
  final String name;

  /// Absolute path on mobile/desktop; null on Web.
  final String? path;

  factory SaveFileResult.fromMap(Map<Object?, Object?> map) {
    return SaveFileResult(
      name: map['name'] as String? ?? '',
      path: map['path'] as String?,
    );
  }

  Map<String, Object?> toMap() => {'name': name, 'path': path};
}
