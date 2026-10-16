#ifndef XUE_HUA_FILE_OPERATIONS_WINDOWS_CAMERA_CAPTURE_H_
#define XUE_HUA_FILE_OPERATIONS_WINDOWS_CAMERA_CAPTURE_H_

#include <windows.h>

#include <string>

namespace xue_hua_file_operations {

// Options of one camera capture, decoded from the `capturePhoto` /
// `captureVideo` method call arguments.
struct CameraOptions {
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

struct CameraResult {
  enum class Status {
    kOk,
    kCancelled,
    kUnsupported,       // no camera found
    kPermissionDenied,  // camera access blocked (privacy settings)
    kIoError,
  };
  Status status = Status::kCancelled;
  // Absolute path of the captured file when `status == kOk`.
  std::wstring path;
  std::string message;
};

// Size of an image after being downscaled to fit `max_width` x `max_height`
// (0 = unconstrained). Keeps the aspect ratio and never enlarges.
void CameraTargetSize(int width, int height, double max_width,
                      double max_height, int *out_width, int *out_height);

// Shows a modal preview window on top of `owner` (may be null) and captures a
// photo (JPEG) or a video (H.264/AAC MP4) with Media Foundation's capture
// engine. Blocks (nested message loop) until the user finishes or cancels.
CameraResult CaptureWithCamera(HWND owner, const CameraOptions &options);

}  // namespace xue_hua_file_operations

#endif  // XUE_HUA_FILE_OPERATIONS_WINDOWS_CAMERA_CAPTURE_H_
