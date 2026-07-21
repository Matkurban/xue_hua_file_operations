/// Result of [XueHuaFileOperations.pickDirectory].
class DirectoryResult {
  const DirectoryResult({
    required this.path,
    required this.name,
    this.identifier,
  });

  final String path;
  final String name;
  final String? identifier;

  factory DirectoryResult.fromMap(Map<Object?, Object?> map) {
    return DirectoryResult(
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? '',
      identifier: map['identifier'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'path': path,
    'name': name,
    'identifier': identifier,
  };
}
