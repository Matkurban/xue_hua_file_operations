/// High-level file type filter for pick dialogs.
enum FileType {
  any,
  image,
  video,
  audio,
  custom;

  String get wireName => name;
}
