#include <flutter_linux/flutter_linux.h>
#include <gtest/gtest.h>

#include "include/xue_hua_file_operations/xue_hua_file_operations_plugin.h"
#include "camera_capture.h"
#include "xue_hua_file_operations_plugin_private.h"

namespace xue_hua_file_operations {
namespace test {

TEST(XueHuaFileOperationsPlugin, IsSupported) {
  EXPECT_TRUE(xue_hua_file_operations_plugin_is_supported());
}

TEST(CameraCapture, TargetSizeKeepsAspectRatioAndNeverEnlarges) {
  int w = 0;
  int h = 0;
  xue_hua_camera_target_size(4000, 3000, 1000, 0, &w, &h);
  EXPECT_EQ(w, 1000);
  EXPECT_EQ(h, 750);
  xue_hua_camera_target_size(4000, 3000, 1000, 300, &w, &h);
  EXPECT_EQ(w, 400);
  EXPECT_EQ(h, 300);
  xue_hua_camera_target_size(400, 300, 1000, 1000, &w, &h);
  EXPECT_EQ(w, 400);
  EXPECT_EQ(h, 300);
  xue_hua_camera_target_size(400, 300, 0, 0, &w, &h);
  EXPECT_EQ(w, 400);
  EXPECT_EQ(h, 300);
}

TEST(CameraCapture, ReportsBuildSupport) {
#ifdef XUE_HUA_HAVE_GSTREAMER
  EXPECT_TRUE(xue_hua_camera_is_built_in());
#else
  EXPECT_FALSE(xue_hua_camera_is_built_in());
#endif
}

}  // namespace test
}  // namespace xue_hua_file_operations
