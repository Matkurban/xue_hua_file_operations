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

TEST(XueHuaFileOperationsPlugin, CapturePhotoIsUnsupported) {
  XueHuaFileOperationsPlugin plugin(nullptr);
  std::string code;
  plugin.HandleMethodCall(
      MethodCall("capturePhoto", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&code](const std::string &error_code, const std::string &,
                  const EncodableValue *) { code = error_code; },
          nullptr));

  EXPECT_EQ(code, "unsupported");
}

}  // namespace test
}  // namespace xue_hua_file_operations
