#ifndef FLUTTER_PLUGIN_XUE_HUA_FILE_OPERATIONS_PLUGIN_H_
#define FLUTTER_PLUGIN_XUE_HUA_FILE_OPERATIONS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace xue_hua_file_operations {

class XueHuaFileOperationsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  XueHuaFileOperationsPlugin(flutter::PluginRegistrarWindows *registrar);

  virtual ~XueHuaFileOperationsPlugin();

  XueHuaFileOperationsPlugin(const XueHuaFileOperationsPlugin &) = delete;
  XueHuaFileOperationsPlugin &operator=(const XueHuaFileOperationsPlugin &) =
      delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  flutter::PluginRegistrarWindows *registrar_;
};

}  // namespace xue_hua_file_operations

#endif  // FLUTTER_PLUGIN_XUE_HUA_FILE_OPERATIONS_PLUGIN_H_
