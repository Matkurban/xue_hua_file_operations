#include "xue_hua_file_operations_plugin.h"

#include <windows.h>
#include <shobjidl.h>
#include <shellapi.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <filesystem>
#include <fstream>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace xue_hua_file_operations {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::wstring Utf8ToWide(const std::string &utf8) {
  if (utf8.empty()) return std::wstring();
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  std::wstring wide(len ? len - 1 : 0, L'\0');
  if (len > 1) {
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, wide.data(), len);
  }
  return wide;
}

std::string WideToUtf8(const std::wstring &wide) {
  if (wide.empty()) return std::string();
  int len = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0,
                                nullptr, nullptr);
  std::string utf8(len ? len - 1 : 0, '\0');
  if (len > 1) {
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, utf8.data(), len,
                        nullptr, nullptr);
  }
  return utf8;
}

const EncodableMap *GetArgsMap(const EncodableValue *arguments) {
  if (!arguments || !std::holds_alternative<EncodableMap>(*arguments)) {
    return nullptr;
  }
  return &std::get<EncodableMap>(*arguments);
}

std::string GetStringArg(const EncodableMap *args, const std::string &key) {
  if (!args) return "";
  auto it = args->find(EncodableValue(key));
  if (it == args->end() || !std::holds_alternative<std::string>(it->second)) {
    return "";
  }
  return std::get<std::string>(it->second);
}

bool GetBoolArg(const EncodableMap *args, const std::string &key,
                bool default_value) {
  if (!args) return default_value;
  auto it = args->find(EncodableValue(key));
  if (it == args->end() || !std::holds_alternative<bool>(it->second)) {
    return default_value;
  }
  return std::get<bool>(it->second);
}

std::optional<int64_t> GetIntArg(const EncodableMap *args,
                                 const std::string &key) {
  if (!args) return std::nullopt;
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) return std::nullopt;
  if (std::holds_alternative<int32_t>(it->second)) {
    return static_cast<int64_t>(std::get<int32_t>(it->second));
  }
  if (std::holds_alternative<int64_t>(it->second)) {
    return std::get<int64_t>(it->second);
  }
  return std::nullopt;
}

std::vector<std::string> GetStringListArg(const EncodableMap *args,
                                          const std::string &key) {
  std::vector<std::string> out;
  if (!args) return out;
  auto it = args->find(EncodableValue(key));
  if (it == args->end() || !std::holds_alternative<EncodableList>(it->second)) {
    return out;
  }
  for (const auto &item : std::get<EncodableList>(it->second)) {
    if (std::holds_alternative<std::string>(item)) {
      out.push_back(std::get<std::string>(item));
    }
  }
  return out;
}

const std::vector<uint8_t> *GetBytesArg(const EncodableMap *args,
                                        const std::string &key) {
  if (!args) return nullptr;
  auto it = args->find(EncodableValue(key));
  if (it == args->end() ||
      !std::holds_alternative<std::vector<uint8_t>>(it->second)) {
    return nullptr;
  }
  return &std::get<std::vector<uint8_t>>(it->second);
}

void ApplyExtensionFilters(IFileDialog *dialog,
                           const std::vector<std::string> &extensions) {
  if (extensions.empty()) return;

  std::wstring filter_spec;
  for (size_t i = 0; i < extensions.size(); ++i) {
    std::string ext = extensions[i];
    if (!ext.empty() && ext[0] == '.') ext = ext.substr(1);
    if (i > 0) filter_spec += L";";
    filter_spec += L"*.";
    filter_spec += Utf8ToWide(ext);
  }

  COMDLG_FILTERSPEC spec{};
  spec.pszName = L"Allowed files";
  spec.pszSpec = filter_spec.c_str();
  dialog->SetFileTypes(1, &spec);
  dialog->SetFileTypeIndex(1);
}

EncodableMap FileMapFromPath(const std::wstring &path, bool with_data) {
  namespace fs = std::filesystem;
  fs::path p(path);
  std::string utf8_path = WideToUtf8(path);
  std::string name = WideToUtf8(p.filename().wstring());
  int64_t size = 0;
  std::error_code ec;
  if (fs::exists(p, ec)) {
    size = static_cast<int64_t>(fs::file_size(p, ec));
  }

  EncodableMap map;
  map[EncodableValue("name")] = EncodableValue(name);
  map[EncodableValue("size")] = EncodableValue(static_cast<int32_t>(size));
  map[EncodableValue("path")] = EncodableValue(utf8_path);
  map[EncodableValue("identifier")] =
      EncodableValue(std::string("file:///") + utf8_path);

  if (with_data) {
    std::ifstream input(p, std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),
                               std::istreambuf_iterator<char>());
    map[EncodableValue("size")] =
        EncodableValue(static_cast<int32_t>(bytes.size()));
    map[EncodableValue("bytes")] = EncodableValue(bytes);
  } else {
    map[EncodableValue("bytes")] = EncodableValue();
  }
  return map;
}

HWND GetRootWindow(flutter::PluginRegistrarWindows *registrar) {
  if (!registrar || !registrar->GetView()) {
    return nullptr;
  }
  return GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);
}

void PickFiles(
    flutter::PluginRegistrarWindows *registrar, const EncodableMap *args,
    bool multiple,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  bool with_data = GetBoolArg(args, "withData", false);
  auto max_files = GetIntArg(args, "maxFiles");
  auto extensions = GetStringListArg(args, "allowedExtensions");
  std::string title = GetStringArg(args, "dialogTitle");

  IFileOpenDialog *dialog = nullptr;
  HRESULT hr =
      CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                       IID_PPV_ARGS(&dialog));
  if (FAILED(hr) || !dialog) {
    result->Error("io_error", "Unable to create file open dialog");
    return;
  }

  DWORD options = 0;
  dialog->GetOptions(&options);
  options |= FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST;
  if (multiple) options |= FOS_ALLOWMULTISELECT;
  dialog->SetOptions(options);
  if (!title.empty()) {
    dialog->SetTitle(Utf8ToWide(title).c_str());
  }
  ApplyExtensionFilters(dialog, extensions);

  hr = dialog->Show(GetRootWindow(registrar));
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    dialog->Release();
    result->Success(EncodableValue());
    return;
  }
  if (FAILED(hr)) {
    dialog->Release();
    result->Error("io_error", "File open dialog failed");
    return;
  }

  if (!multiple) {
    IShellItem *item = nullptr;
    hr = dialog->GetResult(&item);
    dialog->Release();
    if (FAILED(hr) || !item) {
      result->Success(EncodableValue());
      return;
    }
    PWSTR path = nullptr;
    item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    EncodableMap wrapper;
    if (path) {
      wrapper[EncodableValue("file")] =
          EncodableValue(FileMapFromPath(path, with_data));
      CoTaskMemFree(path);
    }
    item->Release();
    result->Success(EncodableValue(wrapper));
    return;
  }

  IShellItemArray *items = nullptr;
  hr = dialog->GetResults(&items);
  dialog->Release();
  if (FAILED(hr) || !items) {
    result->Success(EncodableValue());
    return;
  }

  DWORD count = 0;
  items->GetCount(&count);
  if (max_files.has_value() &&
      static_cast<int64_t>(count) > max_files.value()) {
    items->Release();
    EncodableMap details;
    details[EncodableValue("selected")] =
        EncodableValue(static_cast<int32_t>(count));
    details[EncodableValue("maxFiles")] =
        EncodableValue(static_cast<int32_t>(max_files.value()));
    result->Error("too_many_files",
                  "Selected more files than maxFiles allows",
                  EncodableValue(details));
    return;
  }

  EncodableList files;
  for (DWORD i = 0; i < count; ++i) {
    IShellItem *item = nullptr;
    if (FAILED(items->GetItemAt(i, &item)) || !item) continue;
    PWSTR path = nullptr;
    item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    if (path) {
      files.push_back(EncodableValue(FileMapFromPath(path, with_data)));
      CoTaskMemFree(path);
    }
    item->Release();
  }
  items->Release();

  if (files.empty()) {
    result->Success(EncodableValue());
    return;
  }
  EncodableMap wrapper;
  wrapper[EncodableValue("files")] = EncodableValue(files);
  result->Success(EncodableValue(wrapper));
}

void PickDirectory(
    flutter::PluginRegistrarWindows *registrar, const EncodableMap *args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  std::string title = GetStringArg(args, "dialogTitle");
  IFileOpenDialog *dialog = nullptr;
  HRESULT hr =
      CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                       IID_PPV_ARGS(&dialog));
  if (FAILED(hr) || !dialog) {
    result->Error("io_error", "Unable to create directory dialog");
    return;
  }

  DWORD options = 0;
  dialog->GetOptions(&options);
  options |= FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM;
  dialog->SetOptions(options);
  if (!title.empty()) {
    dialog->SetTitle(Utf8ToWide(title).c_str());
  }

  hr = dialog->Show(GetRootWindow(registrar));
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    dialog->Release();
    result->Success(EncodableValue());
    return;
  }
  if (FAILED(hr)) {
    dialog->Release();
    result->Error("io_error", "Directory dialog failed");
    return;
  }

  IShellItem *item = nullptr;
  hr = dialog->GetResult(&item);
  dialog->Release();
  if (FAILED(hr) || !item) {
    result->Success(EncodableValue());
    return;
  }

  PWSTR path = nullptr;
  item->GetDisplayName(SIGDN_FILESYSPATH, &path);
  item->Release();
  if (!path) {
    result->Success(EncodableValue());
    return;
  }

  std::filesystem::path p(path);
  EncodableMap map;
  map[EncodableValue("path")] = EncodableValue(WideToUtf8(path));
  map[EncodableValue("name")] = EncodableValue(WideToUtf8(p.filename().wstring()));
  map[EncodableValue("identifier")] =
      EncodableValue(std::string("file:///") + WideToUtf8(path));
  CoTaskMemFree(path);
  result->Success(EncodableValue(map));
}

void SaveFile(flutter::PluginRegistrarWindows *registrar,
              const EncodableMap *args,
              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  std::string file_name = GetStringArg(args, "fileName");
  if (file_name.empty()) file_name = "file";
  std::string source_path = GetStringArg(args, "sourcePath");
  const auto *bytes = GetBytesArg(args, "bytes");
  auto extensions = GetStringListArg(args, "allowedExtensions");
  std::string title = GetStringArg(args, "dialogTitle");

  if (!bytes && source_path.empty()) {
    result->Error("invalid_args", "Either bytes or sourcePath must be provided");
    return;
  }

  IFileSaveDialog *dialog = nullptr;
  HRESULT hr =
      CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
                       IID_PPV_ARGS(&dialog));
  if (FAILED(hr) || !dialog) {
    result->Error("io_error", "Unable to create save dialog");
    return;
  }

  dialog->SetFileName(Utf8ToWide(file_name).c_str());
  if (!title.empty()) {
    dialog->SetTitle(Utf8ToWide(title).c_str());
  }
  ApplyExtensionFilters(dialog, extensions);

  hr = dialog->Show(GetRootWindow(registrar));
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    dialog->Release();
    result->Success(EncodableValue());
    return;
  }
  if (FAILED(hr)) {
    dialog->Release();
    result->Error("io_error", "Save dialog failed");
    return;
  }

  IShellItem *item = nullptr;
  hr = dialog->GetResult(&item);
  dialog->Release();
  if (FAILED(hr) || !item) {
    result->Success(EncodableValue());
    return;
  }

  PWSTR path = nullptr;
  item->GetDisplayName(SIGDN_FILESYSPATH, &path);
  item->Release();
  if (!path) {
    result->Success(EncodableValue());
    return;
  }

  try {
    std::filesystem::path dest(path);
    if (bytes) {
      std::ofstream out(dest, std::ios::binary);
      out.write(reinterpret_cast<const char *>(bytes->data()),
                static_cast<std::streamsize>(bytes->size()));
    } else {
      std::filesystem::copy_file(
          std::filesystem::path(Utf8ToWide(source_path)), dest,
          std::filesystem::copy_options::overwrite_existing);
    }
    EncodableMap map;
    map[EncodableValue("path")] = EncodableValue(WideToUtf8(path));
    map[EncodableValue("name")] =
        EncodableValue(WideToUtf8(dest.filename().wstring()));
    CoTaskMemFree(path);
    result->Success(EncodableValue(map));
  } catch (const std::exception &e) {
    CoTaskMemFree(path);
    result->Error("io_error", e.what());
  }
}

void OpenFile(const EncodableMap *args,
              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  std::string path = GetStringArg(args, "path");
  std::string identifier = GetStringArg(args, "identifier");
  if (path.empty() && !identifier.empty()) {
    if (identifier.rfind("file:///", 0) == 0) {
      path = identifier.substr(8);
    } else if (identifier.rfind("file://", 0) == 0) {
      path = identifier.substr(7);
    } else {
      path = identifier;
    }
  }
  if (path.empty()) {
    result->Error("invalid_args", "Either path or identifier must be provided");
    return;
  }

  std::wstring wide = Utf8ToWide(path);
  HINSTANCE hi =
      ShellExecuteW(nullptr, L"open", wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
  if (reinterpret_cast<intptr_t>(hi) <= 32) {
    result->Error("io_error", "Unable to open file");
    return;
  }
  result->Success(EncodableValue(true));
}

}  // namespace

void XueHuaFileOperationsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "xue_hua_file_operations",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<XueHuaFileOperationsPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

XueHuaFileOperationsPlugin::XueHuaFileOperationsPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
}

XueHuaFileOperationsPlugin::~XueHuaFileOperationsPlugin() {}

void XueHuaFileOperationsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto *args = GetArgsMap(method_call.arguments());
  const auto &method = method_call.method_name();

  if (method == "pickFile") {
    PickFiles(registrar_, args, false, std::move(result));
  } else if (method == "pickFiles") {
    PickFiles(registrar_, args, true, std::move(result));
  } else if (method == "pickDirectory") {
    PickDirectory(registrar_, args, std::move(result));
  } else if (method == "saveFile") {
    SaveFile(registrar_, args, std::move(result));
  } else if (method == "openFile") {
    OpenFile(args, std::move(result));
  } else {
    result->NotImplemented();
  }
}

}  // namespace xue_hua_file_operations
