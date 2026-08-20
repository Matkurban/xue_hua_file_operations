#include "xue_hua_file_operations_plugin.h"

#include <windows.h>
#include <knownfolders.h>
#include <shlobj.h>
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
#include <utility>
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

const std::vector<std::string> &ImageExtensions() {
  static const std::vector<std::string> kExts = {
      "jpg", "jpeg", "png",  "gif",  "bmp", "webp",
      "tif", "tiff", "heic", "heif", "avif", "ico"};
  return kExts;
}

const std::vector<std::string> &VideoExtensions() {
  static const std::vector<std::string> kExts = {
      "mp4", "mov", "m4v", "avi", "mkv", "webm",
      "wmv", "mpg", "mpeg", "3gp", "3g2"};
  return kExts;
}

const std::vector<std::string> &AudioExtensions() {
  static const std::vector<std::string> kExts = {
      "mp3", "wav", "aac", "m4a", "flac", "ogg", "wma", "opus"};
  return kExts;
}

void AppendExtensions(std::vector<std::string> &target,
                      const std::vector<std::string> &source) {
  target.insert(target.end(), source.begin(), source.end());
}

// Best-effort mapping of a MIME type to filter extensions.
std::vector<std::string> ExtensionsForMime(const std::string &mime) {
  if (mime == "image/*") return ImageExtensions();
  if (mime == "video/*") return VideoExtensions();
  if (mime == "audio/*") return AudioExtensions();

  static const std::pair<const char *, const char *> kMimeToExt[] = {
      {"image/jpeg", "jpg;jpeg"},   {"image/png", "png"},
      {"image/gif", "gif"},         {"image/webp", "webp"},
      {"image/bmp", "bmp"},         {"image/tiff", "tif;tiff"},
      {"image/heic", "heic"},       {"image/heif", "heif"},
      {"image/avif", "avif"},       {"image/x-icon", "ico"},
      {"image/svg+xml", "svg"},     {"video/mp4", "mp4;m4v"},
      {"video/quicktime", "mov"},   {"video/webm", "webm"},
      {"video/x-msvideo", "avi"},   {"video/x-matroska", "mkv"},
      {"video/mpeg", "mpg;mpeg"},   {"video/3gpp", "3gp"},
      {"video/3gpp2", "3g2"},       {"audio/mpeg", "mp3"},
      {"audio/wav", "wav"},         {"audio/x-wav", "wav"},
      {"audio/aac", "aac"},         {"audio/mp4", "m4a"},
      {"audio/flac", "flac"},       {"audio/ogg", "ogg;opus"},
      {"application/pdf", "pdf"},   {"application/zip", "zip"},
      {"application/json", "json"}, {"text/plain", "txt"},
      {"text/csv", "csv"},          {"text/html", "htm;html"},
      {"text/xml", "xml"},          {"application/xml", "xml"},
  };
  std::vector<std::string> out;
  for (const auto &[key, exts] : kMimeToExt) {
    if (mime == key) {
      std::string list(exts);
      size_t start = 0;
      while (start <= list.size()) {
        size_t sep = list.find(';', start);
        if (sep == std::string::npos) {
          out.push_back(list.substr(start));
          break;
        }
        out.push_back(list.substr(start, sep - start));
        start = sep + 1;
      }
      break;
    }
  }
  return out;
}

// Collects filter extensions from allowedExtensions, allowedMimeTypes and
// the high-level type, mirroring the other platforms.
std::vector<std::string> FilterExtensionsFromArgs(const EncodableMap *args) {
  std::vector<std::string> extensions;
  for (auto ext : GetStringListArg(args, "allowedExtensions")) {
    if (!ext.empty() && ext[0] == '.') ext = ext.substr(1);
    if (!ext.empty()) extensions.push_back(ext);
  }
  for (const auto &mime : GetStringListArg(args, "allowedMimeTypes")) {
    AppendExtensions(extensions, ExtensionsForMime(mime));
  }
  if (!extensions.empty()) return extensions;

  std::string type = GetStringArg(args, "type");
  if (type == "image") return ImageExtensions();
  if (type == "video") return VideoExtensions();
  if (type == "audio") return AudioExtensions();
  if (type == "media") {
    AppendExtensions(extensions, ImageExtensions());
    AppendExtensions(extensions, VideoExtensions());
  }
  return extensions;
}

// Backing storage for dialog filters. Per IFileDialog::SetFileTypes the
// strings must stay alive until the dialog is shown, so the caller keeps
// this object in scope until after Show() returns.
struct DialogFilter {
  std::wstring name;
  std::wstring spec;
  COMDLG_FILTERSPEC filter_spec{};
  bool valid = false;
};

DialogFilter BuildFilter(const std::vector<std::string> &extensions) {
  DialogFilter filter;
  if (extensions.empty()) return filter;

  std::wstring spec;
  for (size_t i = 0; i < extensions.size(); ++i) {
    if (i > 0) spec += L";";
    spec += L"*.";
    spec += Utf8ToWide(extensions[i]);
  }
  filter.name = L"Allowed files";
  filter.spec = spec;
  filter.filter_spec.pszName = filter.name.c_str();
  filter.filter_spec.pszSpec = filter.spec.c_str();
  filter.valid = true;
  return filter;
}

void ApplyFilter(IFileDialog *dialog, const DialogFilter &filter) {
  if (!filter.valid) return;
  dialog->SetFileTypes(1, &filter.filter_spec);
  dialog->SetFileTypeIndex(1);
}

std::string FileUriFromWidePath(const std::wstring &path) {
  std::string utf8 = WideToUtf8(path);
  for (auto &ch : utf8) {
    if (ch == '\\') ch = '/';
  }
  return "file:///" + utf8;
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
  map[EncodableValue("size")] = EncodableValue(size);
  map[EncodableValue("path")] = EncodableValue(utf8_path);
  map[EncodableValue("identifier")] = EncodableValue(FileUriFromWidePath(path));

  if (with_data) {
    std::ifstream input(p, std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),
                               std::istreambuf_iterator<char>());
    map[EncodableValue("size")] =
        EncodableValue(static_cast<int64_t>(bytes.size()));
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
  // Filter storage must outlive Show().
  DialogFilter filter = BuildFilter(FilterExtensionsFromArgs(args));
  ApplyFilter(dialog, filter);

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
  map[EncodableValue("identifier")] = EncodableValue(FileUriFromWidePath(path));
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
  // Filter storage must outlive Show().
  DialogFilter filter = BuildFilter(FilterExtensionsFromArgs(args));
  ApplyFilter(dialog, filter);

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
      if (!out) {
        CoTaskMemFree(path);
        result->Error("io_error", "Unable to open destination file");
        return;
      }
      out.write(reinterpret_cast<const char *>(bytes->data()),
                static_cast<std::streamsize>(bytes->size()));
      out.close();
      if (out.fail()) {
        CoTaskMemFree(path);
        result->Error("io_error", "Failed to write destination file");
        return;
      }
    } else {
      std::filesystem::path source(Utf8ToWide(source_path));
      if (!std::filesystem::exists(source)) {
        CoTaskMemFree(path);
        result->Error("not_found", "File not found: " + source_path);
        return;
      }
      std::filesystem::copy_file(
          source, dest, std::filesystem::copy_options::overwrite_existing);
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

void OpenAppSettings(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  HINSTANCE hi = ShellExecuteW(nullptr, L"open", L"ms-settings:privacy-pictures",
                               nullptr, nullptr, SW_SHOWNORMAL);
  if (reinterpret_cast<intptr_t>(hi) <= 32) {
    hi = ShellExecuteW(nullptr, L"open", L"ms-settings:appsfeatures", nullptr,
                       nullptr, SW_SHOWNORMAL);
  }
  if (reinterpret_cast<intptr_t>(hi) <= 32) {
    result->Error("unsupported", "Unable to open Windows Settings");
    return;
  }
  result->Success(EncodableValue(true));
}

std::filesystem::path UniqueDestPath(const std::filesystem::path &dir,
                                     const std::wstring &file_name) {
  std::filesystem::path dest = dir / file_name;
  if (!std::filesystem::exists(dest)) {
    return dest;
  }
  const auto stem = dest.stem().wstring();
  const auto ext = dest.extension().wstring();
  for (int i = 1;; ++i) {
    auto candidate = dir / (stem + L"_" + std::to_wstring(i) + ext);
    if (!std::filesystem::exists(candidate)) {
      return candidate;
    }
  }
}

std::wstring SanitizeAlbumName(const std::string &album) {
  std::wstring wide = Utf8ToWide(album);
  for (auto &ch : wide) {
    if (ch == L'\\' || ch == L'/' || ch == L':' || ch == L'*' || ch == L'?' ||
        ch == L'"' || ch == L'<' || ch == L'>' || ch == L'|') {
      ch = L'_';
    }
  }
  return wide;
}

void SaveToGallery(
    const EncodableMap *args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  std::string file_name = GetStringArg(args, "fileName");
  if (file_name.empty()) file_name = "file";
  std::string source_path = GetStringArg(args, "sourcePath");
  const auto *bytes = GetBytesArg(args, "bytes");
  std::string type = GetStringArg(args, "type");
  std::string album_name = GetStringArg(args, "albumName");

  if (!bytes && source_path.empty()) {
    result->Error("invalid_args", "Either bytes or sourcePath must be provided");
    return;
  }
  if (type != "image" && type != "video") {
    result->Error("invalid_args", "type must be image or video");
    return;
  }

  PWSTR folder = nullptr;
  HRESULT hr = SHGetKnownFolderPath(
      type == "video" ? FOLDERID_Videos : FOLDERID_Pictures, 0, nullptr,
      &folder);
  if (FAILED(hr) || !folder) {
    result->Error("io_error", "Unable to resolve Pictures/Videos folder");
    return;
  }

  std::filesystem::path dest_dir(folder);
  CoTaskMemFree(folder);

  if (!album_name.empty()) {
    dest_dir /= SanitizeAlbumName(album_name);
  }

  std::error_code ec;
  std::filesystem::create_directories(dest_dir, ec);
  if (ec) {
    result->Error("io_error", "Unable to create gallery directory");
    return;
  }

  std::filesystem::path dest =
      UniqueDestPath(dest_dir, Utf8ToWide(file_name));

  try {
    if (bytes) {
      std::ofstream out(dest, std::ios::binary);
      if (!out) {
        result->Error("io_error", "Unable to open destination file");
        return;
      }
      out.write(reinterpret_cast<const char *>(bytes->data()),
                static_cast<std::streamsize>(bytes->size()));
    } else {
      std::filesystem::path source(Utf8ToWide(source_path));
      if (!std::filesystem::exists(source)) {
        result->Error("not_found", "File not found");
        return;
      }
      std::filesystem::copy_file(
          source, dest, std::filesystem::copy_options::overwrite_existing);
    }
  } catch (const std::exception &e) {
    result->Error("io_error", e.what());
    return;
  }

  const std::wstring dest_wide = dest.wstring();
  SHChangeNotify(SHCNE_CREATE, SHCNF_PATHW, dest_wide.c_str(), nullptr);
  SHChangeNotify(SHCNE_UPDATEDIR, SHCNF_PATHW, dest_dir.wstring().c_str(),
                 nullptr);

  EncodableMap map;
  map[EncodableValue("name")] =
      EncodableValue(WideToUtf8(dest.filename().wstring()));
  map[EncodableValue("path")] = EncodableValue(WideToUtf8(dest_wide));
  map[EncodableValue("identifier")] =
      EncodableValue(FileUriFromWidePath(dest_wide));
  result->Success(EncodableValue(map));
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
  } else if (method == "saveToGallery") {
    SaveToGallery(args, std::move(result));
  } else if (method == "galleryPermissionStatus" ||
             method == "requestGalleryPermission") {
    result->Success(flutter::EncodableValue(std::string("granted")));
  } else if (method == "openFile") {
    OpenFile(args, std::move(result));
  } else if (method == "openAppSettings") {
    OpenAppSettings(std::move(result));
  } else {
    result->NotImplemented();
  }
}

}  // namespace xue_hua_file_operations
