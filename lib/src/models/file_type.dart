/// High-level file type filter for pick dialogs.
enum FileType {
  any,

  /// Images and videos. On iOS / Android this opens the system photo picker.
  media,
  image,
  video,
  audio,
  custom;

  String get wireName => name;
}
