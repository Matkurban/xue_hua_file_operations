/// Preferred camera for [MediaSource.camera] captures.
///
/// This is a hint: the platform falls back to whichever camera is available.
/// Android has no public API for it, so the hint is forwarded through the
/// widely supported (but non-standard) intent extras; on Web it maps to the
/// `capture` attribute (`user` / `environment`).
enum CameraFacing {
  /// Back-facing camera (default).
  rear,

  /// Front-facing (selfie) camera.
  front;

  String get wireName => name;
}
