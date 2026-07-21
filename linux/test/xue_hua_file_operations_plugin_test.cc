#include <flutter_linux/flutter_linux.h>
#include <gtest/gtest.h>

#include "include/xue_hua_file_operations/xue_hua_file_operations_plugin.h"
#include "xue_hua_file_operations_plugin_private.h"

namespace xue_hua_file_operations {
namespace test {

TEST(XueHuaFileOperationsPlugin, IsSupported) {
  EXPECT_TRUE(xue_hua_file_operations_plugin_is_supported());
}

}  // namespace test
}  // namespace xue_hua_file_operations
