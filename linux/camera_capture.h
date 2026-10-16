#ifndef XUE_HUA_FILE_OPERATIONS_CAMERA_CAPTURE_H_
#define XUE_HUA_FILE_OPERATIONS_CAMERA_CAPTURE_H_

#include <gtk/gtk.h>

#include <string>

// Options of one camera capture, decoded from the `capturePhoto` /
// `captureVideo` method call arguments.
struct XueHuaCameraOptions {
  bool is_video = false;
  bool prefer_front = false;
  // 0 means "no limit".
  double max_width = 0;
  double max_height = 0;
  // 0-100, -1 means "not provided".
  int image_quality = -1;
  // 0 means "no limit".
  int max_duration_seconds = 0;
};

struct XueHuaCameraResult {
  enum Status {
    kOk,
    kCancelled,
    kUnsupported,       // no camera / built without GStreamer
    kPermissionDenied,  // the camera device could not be opened (permissions)
    kIoError,
  };
  Status status = kCancelled;
  // Absolute path of the captured file when `status == kOk`.
  std::string path;
  std::string message;
};

// Size of an image after being downscaled to fit `max_width` x `max_height`
// (0 = unconstrained). Keeps the aspect ratio and never enlarges.
void xue_hua_camera_target_size(int width, int height, double max_width,
                                double max_height, int* out_width,
                                int* out_height);

// Whether this build can capture at all (GStreamer found at build time).
bool xue_hua_camera_is_built_in(void);

// Shows a modal preview dialog on top of `parent` and captures a photo or a
// video. Blocks (nested main loop) until the user finishes or cancels.
XueHuaCameraResult xue_hua_camera_capture(GtkWindow* parent,
                                          const XueHuaCameraOptions& options);

#endif  // XUE_HUA_FILE_OPERATIONS_CAMERA_CAPTURE_H_
