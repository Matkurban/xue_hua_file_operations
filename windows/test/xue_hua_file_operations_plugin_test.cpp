#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>

#include <memory>
#include <optional>
#include <string>

#include "camera_capture.h"
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

TEST(CameraCapture, TargetSizeKeepsAspectRatioAndNeverEnlarges) {
  int w = 0, h = 0;
  CameraTargetSize(4000, 3000, 1000, 1000, &w, &h);
  EXPECT_EQ(w, 1000);
  EXPECT_EQ(h, 750);
  CameraTargetSize(4000, 3000, 0, 600, &w, &h);
  EXPECT_EQ(w, 800);
  EXPECT_EQ(h, 600);
  CameraTargetSize(640, 480, 2000, 2000, &w, &h);
  EXPECT_EQ(w, 640);
  EXPECT_EQ(h, 480);
  CameraTargetSize(640, 480, 0, 0, &w, &h);
  EXPECT_EQ(w, 640);
  EXPECT_EQ(h, 480);
}

}  // namespace test
}  // namespace xue_hua_file_operations
