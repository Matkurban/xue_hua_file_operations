#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>

#include <memory>
#include <optional>
#include <string>

#include "xue_hua_file_operations_plugin.h"

namespace xue_hua_file_operations {
namespace test {

namespace {

using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(XueHuaFileOperationsPlugin, UnknownMethodIsNotImplemented) {
  XueHuaFileOperationsPlugin plugin(nullptr);
  bool not_implemented = false;
  plugin.HandleMethodCall(
      MethodCall("unknownMethod", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr, nullptr, [&not_implemented]() { not_implemented = true; }));

  EXPECT_TRUE(not_implemented);
}

}  // namespace test
}  // namespace xue_hua_file_operations
