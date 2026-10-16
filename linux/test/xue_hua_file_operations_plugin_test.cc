#include <flutter_linux/flutter_linux.h>
#include <gtest/gtest.h>

#include "include/xue_hua_file_operations/xue_hua_file_operations_plugin.h"
#include "xue_hua_file_operations_plugin_private.h"

namespace xue_hua_file_operations {
namespace test {

TEST(XueHuaFileOperationsPlugin, IsSupported) {
  EXPECT_TRUE(xue_hua_file_operations_plugin_is_supported());
}

TEST(XueHuaFileOperationsPlugin, CaptureIsUnsupported) {
  g_autoptr(FlMethodResponse) response =
      xue_hua_file_operations_plugin_capture_unsupported();
  ASSERT_TRUE(FL_IS_METHOD_ERROR_RESPONSE(response));
  EXPECT_STREQ(
      fl_method_error_response_get_code(FL_METHOD_ERROR_RESPONSE(response)),
      "unsupported");
}

}  // namespace test
}  // namespace xue_hua_file_operations
