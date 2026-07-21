#include "include/xue_hua_file_operations/xue_hua_file_operations_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "xue_hua_file_operations_plugin.h"

void XueHuaFileOperationsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  xue_hua_file_operations::XueHuaFileOperationsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
