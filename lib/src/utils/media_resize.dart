import 'dart:math' as math;

/// Whether an image needs to be re-encoded for the given constraints.
///
/// Mirrors the native behaviour: a valid [imageQuality] always triggers a
/// re-encode, otherwise only a [maxWidth] / [maxHeight] limit does.
bool mediaResizeNeeded(double? maxWidth, double? maxHeight, int? imageQuality) {
  if (imageQuality != null) return imageQuality >= 0 && imageQuality <= 100;
  return maxWidth != null || maxHeight != null;
}

/// Size of an image after being downscaled to fit [maxWidth] x [maxHeight].
///
/// The aspect ratio is kept and images are never enlarged. A `null` limit
/// means unconstrained on that axis. Returns `(width, height)`.
(int, int) downScaledSize(
  int width,
  int height,
  double? maxWidth,
  double? maxHeight,
) {
  final widthFactor = maxWidth != null && maxWidth > 0 ? width / maxWidth : 1.0;
  final heightFactor = maxHeight != null && maxHeight > 0
      ? height / maxHeight
      : 1.0;
  final factor = math.max(widthFactor, heightFactor);
  if (factor <= 1) return (width, height);
  return (math.max(1, width ~/ factor), math.max(1, height ~/ factor));
}
