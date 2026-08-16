/// Media kind for [XueHuaFileOperations.saveToGallery].
enum GalleryMediaType {
  image,
  video;

  String get wireName => name;

  static GalleryMediaType? fromWireName(String? name) {
    switch (name) {
      case 'image':
        return GalleryMediaType.image;
      case 'video':
        return GalleryMediaType.video;
      default:
        return null;
    }
  }

  /// Infer from [fileName] extension. Returns `null` if unknown.
  static GalleryMediaType? fromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return null;
    final ext = fileName.substring(dot + 1).toLowerCase();
    if (_imageExtensions.contains(ext)) return GalleryMediaType.image;
    if (_videoExtensions.contains(ext)) return GalleryMediaType.video;
    return null;
  }

  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'bmp',
    'tif',
    'tiff',
    'dng',
    'avif',
    'ico',
  };

  static const Set<String> _videoExtensions = {
    'mp4',
    'mov',
    'm4v',
    'avi',
    'mkv',
    'webm',
    '3gp',
    '3g2',
    'mpeg',
    'mpg',
    'wmv',
    'flv',
    'ts',
    'mts',
    'm2ts',
  };
}
