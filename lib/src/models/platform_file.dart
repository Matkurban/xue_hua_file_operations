import 'dart:typed_data';

/// A file selected or produced by the plugin.
class PlatformFile {
  const PlatformFile({
    required this.name,
    required this.size,
    this.path,
    this.bytes,
    this.identifier,
  });

  final String name;
  final int size;

  /// Non-null on mobile/desktop; null on Web.
  final String? path;

  /// Non-null only when `withData: true` or on Web.
  final Uint8List? bytes;

  /// Native unique id (Android URI, iOS bookmark/url, etc.).
  final String? identifier;

  bool get hasBytes => bytes != null;

  factory PlatformFile.fromMap(Map<Object?, Object?> map) {
    final rawBytes = map['bytes'];
    Uint8List? bytes;
    if (rawBytes is Uint8List) {
      bytes = rawBytes;
    } else if (rawBytes is List) {
      bytes = Uint8List.fromList(rawBytes.cast<int>());
    }

    return PlatformFile(
      name: map['name'] as String? ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
      path: map['path'] as String?,
      bytes: bytes,
      identifier: map['identifier'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'size': size,
        'path': path,
        'bytes': bytes,
        'identifier': identifier,
      };

  @override
  String toString() =>
      'PlatformFile(name: $name, size: $size, path: $path, '
      'hasBytes: $hasBytes, identifier: $identifier)';
}
