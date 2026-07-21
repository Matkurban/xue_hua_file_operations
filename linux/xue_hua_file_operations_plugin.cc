#include "include/xue_hua_file_operations/xue_hua_file_operations_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>
#include <gtk/gtk.h>

#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "xue_hua_file_operations_plugin_private.h"

#define XUE_HUA_FILE_OPERATIONS_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), xue_hua_file_operations_plugin_get_type(), \
                              XueHuaFileOperationsPlugin))

struct _XueHuaFileOperationsPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
};

G_DEFINE_TYPE(XueHuaFileOperationsPlugin, xue_hua_file_operations_plugin,
              g_object_get_type())

gboolean xue_hua_file_operations_plugin_is_supported(void) { return TRUE; }

static GtkWindow* get_window(XueHuaFileOperationsPlugin* self) {
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) {
    return nullptr;
  }
  return GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static std::string get_string_arg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return "";
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return "";
  }
  return fl_value_get_string(value);
}

static bool get_bool_arg(FlValue* args, const char* key, bool default_value) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return default_value;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return default_value;
  }
  return fl_value_get_bool(value);
}

static bool get_int_arg(FlValue* args, const char* key, int64_t* out) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return false;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) return false;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    *out = fl_value_get_int(value);
    return true;
  }
  return false;
}

static std::vector<std::string> get_string_list_arg(FlValue* args,
                                                    const char* key) {
  std::vector<std::string> out;
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return out;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_LIST) {
    return out;
  }
  size_t length = fl_value_get_length(value);
  for (size_t i = 0; i < length; ++i) {
    FlValue* item = fl_value_get_list_value(value, i);
    if (fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
      out.emplace_back(fl_value_get_string(item));
    }
  }
  return out;
}

static FlValue* file_map_from_path(const char* path, bool with_data) {
  g_autofree gchar* basename = g_path_get_basename(path);
  goffset size = 0;
  GStatBuf st{};
  if (g_stat(path, &st) == 0) {
    size = st.st_size;
  }

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "name", fl_value_new_string(basename));
  fl_value_set_string_take(map, "size",
                           fl_value_new_int(static_cast<int64_t>(size)));
  fl_value_set_string_take(map, "path", fl_value_new_string(path));
  g_autofree gchar* identifier = g_strdup_printf("file://%s", path);
  fl_value_set_string_take(map, "identifier", fl_value_new_string(identifier));

  if (with_data) {
    std::ifstream input(path, std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),
                               std::istreambuf_iterator<char>());
    fl_value_set_string_take(
        map, "size",
        fl_value_new_int(static_cast<int64_t>(bytes.size())));
    fl_value_set_string_take(
        map, "bytes",
        fl_value_new_uint8_list(bytes.data(), bytes.size()));
  } else {
    fl_value_set_string_take(map, "bytes", fl_value_new_null());
  }
  return fl_value_ref(map);
}

static void add_filters(GtkFileChooser* chooser, FlValue* args) {
  auto extensions = get_string_list_arg(args, "allowedExtensions");
  auto mimes = get_string_list_arg(args, "allowedMimeTypes");
  std::string type = get_string_arg(args, "type");

  if (!extensions.empty() || !mimes.empty() ||
      type == "image" || type == "video" || type == "audio") {
    GtkFileFilter* filter = gtk_file_filter_new();
    gtk_file_filter_set_name(filter, "Allowed files");
    for (const auto& ext : extensions) {
      std::string pattern = ext;
      if (!pattern.empty() && pattern[0] != '.') {
        pattern = "*." + pattern;
      } else {
        pattern = "*" + pattern;
      }
      gtk_file_filter_add_pattern(filter, pattern.c_str());
    }
    for (const auto& mime : mimes) {
      gtk_file_filter_add_mime_type(filter, mime.c_str());
    }
    if (type == "image") gtk_file_filter_add_mime_type(filter, "image/*");
    if (type == "video") gtk_file_filter_add_mime_type(filter, "video/*");
    if (type == "audio") gtk_file_filter_add_mime_type(filter, "audio/*");
    gtk_file_chooser_add_filter(chooser, filter);
  }

  GtkFileFilter* all = gtk_file_filter_new();
  gtk_file_filter_set_name(all, "All files");
  gtk_file_filter_add_pattern(all, "*");
  gtk_file_chooser_add_filter(chooser, all);
}

static FlMethodResponse* pick_files(XueHuaFileOperationsPlugin* self,
                                    FlValue* args, bool multiple) {
  bool with_data = get_bool_arg(args, "withData", false);
  int64_t max_files = 0;
  bool has_max = get_int_arg(args, "maxFiles", &max_files);
  std::string title = get_string_arg(args, "dialogTitle");

  GtkFileChooserNative* native = gtk_file_chooser_native_new(
      title.empty() ? "Select files" : title.c_str(), get_window(self),
      GTK_FILE_CHOOSER_ACTION_OPEN, "_Open", "_Cancel");
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(native);
  gtk_file_chooser_set_select_multiple(chooser, multiple);
  add_filters(chooser, args);

  gint response = gtk_native_dialog_run(GTK_NATIVE_DIALOG(native));
  if (response != GTK_RESPONSE_ACCEPT) {
    g_object_unref(native);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  if (!multiple) {
    g_autofree gchar* filename = gtk_file_chooser_get_filename(chooser);
    g_object_unref(native);
    if (filename == nullptr) {
      return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    g_autoptr(FlValue) wrapper = fl_value_new_map();
    fl_value_set_string_take(wrapper, "file",
                             file_map_from_path(filename, with_data));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(wrapper));
  }

  GSList* filenames = gtk_file_chooser_get_filenames(chooser);
  g_object_unref(native);
  if (filenames == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  guint selected = g_slist_length(filenames);
  if (has_max && static_cast<int64_t>(selected) > max_files) {
    g_slist_free_full(filenames, g_free);
    g_autoptr(FlValue) details = fl_value_new_map();
    fl_value_set_string_take(details, "selected",
                             fl_value_new_int(static_cast<int64_t>(selected)));
    fl_value_set_string_take(details, "maxFiles", fl_value_new_int(max_files));
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "too_many_files", "Selected more files than maxFiles allows", details));
  }

  g_autoptr(FlValue) files = fl_value_new_list();
  for (GSList* item = filenames; item != nullptr; item = item->next) {
    const char* path = static_cast<const char*>(item->data);
    fl_value_append_take(files, file_map_from_path(path, with_data));
  }
  g_slist_free_full(filenames, g_free);

  g_autoptr(FlValue) wrapper = fl_value_new_map();
  fl_value_set_string_take(wrapper, "files", fl_value_ref(files));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(wrapper));
}

static FlMethodResponse* pick_directory(XueHuaFileOperationsPlugin* self,
                                        FlValue* args) {
  std::string title = get_string_arg(args, "dialogTitle");
  GtkFileChooserNative* native = gtk_file_chooser_native_new(
      title.empty() ? "Select folder" : title.c_str(), get_window(self),
      GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, "_Open", "_Cancel");

  gint response = gtk_native_dialog_run(GTK_NATIVE_DIALOG(native));
  if (response != GTK_RESPONSE_ACCEPT) {
    g_object_unref(native);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  g_autofree gchar* filename =
      gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(native));
  g_object_unref(native);
  if (filename == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  g_autofree gchar* basename = g_path_get_basename(filename);
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "path", fl_value_new_string(filename));
  fl_value_set_string_take(map, "name", fl_value_new_string(basename));
  g_autofree gchar* identifier = g_strdup_printf("file://%s", filename);
  fl_value_set_string_take(map, "identifier", fl_value_new_string(identifier));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

static FlMethodResponse* save_file(XueHuaFileOperationsPlugin* self,
                                   FlValue* args) {
  std::string file_name = get_string_arg(args, "fileName");
  if (file_name.empty()) file_name = "file";
  std::string source_path = get_string_arg(args, "sourcePath");
  std::string title = get_string_arg(args, "dialogTitle");

  FlValue* bytes_value = nullptr;
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    bytes_value = fl_value_lookup_string(args, "bytes");
  }
  bool has_bytes =
      bytes_value != nullptr &&
      fl_value_get_type(bytes_value) == FL_VALUE_TYPE_UINT8_LIST;
  if (!has_bytes && source_path.empty()) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid_args", "Either bytes or sourcePath must be provided",
        nullptr));
  }

  GtkFileChooserNative* native = gtk_file_chooser_native_new(
      title.empty() ? "Save file" : title.c_str(), get_window(self),
      GTK_FILE_CHOOSER_ACTION_SAVE, "_Save", "_Cancel");
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(native);
  gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
  gtk_file_chooser_set_current_name(chooser, file_name.c_str());
  add_filters(chooser, args);

  gint response = gtk_native_dialog_run(GTK_NATIVE_DIALOG(native));
  if (response != GTK_RESPONSE_ACCEPT) {
    g_object_unref(native);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  g_autofree gchar* filename = gtk_file_chooser_get_filename(chooser);
  g_object_unref(native);
  if (filename == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  try {
    if (has_bytes) {
      size_t length = fl_value_get_length(bytes_value);
      const uint8_t* data = fl_value_get_uint8_list(bytes_value);
      std::ofstream out(filename, std::ios::binary);
      out.write(reinterpret_cast<const char*>(data),
                static_cast<std::streamsize>(length));
    } else {
      std::ifstream input(source_path, std::ios::binary);
      std::ofstream out(filename, std::ios::binary);
      out << input.rdbuf();
    }
  } catch (...) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("io_error", "Failed to write file", nullptr));
  }

  g_autofree gchar* basename = g_path_get_basename(filename);
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "path", fl_value_new_string(filename));
  fl_value_set_string_take(map, "name", fl_value_new_string(basename));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

static FlMethodResponse* open_file(XueHuaFileOperationsPlugin* self,
                                   FlValue* args) {
  std::string path = get_string_arg(args, "path");
  std::string identifier = get_string_arg(args, "identifier");
  if (path.empty() && !identifier.empty()) {
    if (identifier.rfind("file://", 0) == 0) {
      path = identifier.substr(7);
    } else {
      path = identifier;
    }
  }
  if (path.empty()) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid_args", "Either path or identifier must be provided", nullptr));
  }

  g_autofree gchar* uri = g_filename_to_uri(path.c_str(), nullptr, nullptr);
  if (uri == nullptr) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("not_found", "Invalid path", nullptr));
  }

  GError* error = nullptr;
  gboolean ok = gtk_show_uri_on_window(get_window(self), uri,
                                       GDK_CURRENT_TIME, &error);
  if (!ok) {
    g_autofree gchar* message =
        g_strdup(error != nullptr ? error->message : "Unable to open file");
    if (error != nullptr) g_error_free(error);
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("io_error", message, nullptr));
  }
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

static void xue_hua_file_operations_plugin_handle_method_call(
    XueHuaFileOperationsPlugin* self, FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "pickFile") == 0) {
    response = pick_files(self, args, false);
  } else if (strcmp(method, "pickFiles") == 0) {
    response = pick_files(self, args, true);
  } else if (strcmp(method, "pickDirectory") == 0) {
    response = pick_directory(self, args);
  } else if (strcmp(method, "saveFile") == 0) {
    response = save_file(self, args);
  } else if (strcmp(method, "openFile") == 0) {
    response = open_file(self, args);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void xue_hua_file_operations_plugin_dispose(GObject* object) {
  XueHuaFileOperationsPlugin* self = XUE_HUA_FILE_OPERATIONS_PLUGIN(object);
  g_clear_object(&self->registrar);
  G_OBJECT_CLASS(xue_hua_file_operations_plugin_parent_class)->dispose(object);
}

static void xue_hua_file_operations_plugin_class_init(
    XueHuaFileOperationsPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = xue_hua_file_operations_plugin_dispose;
}

static void xue_hua_file_operations_plugin_init(
    XueHuaFileOperationsPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  XueHuaFileOperationsPlugin* plugin = XUE_HUA_FILE_OPERATIONS_PLUGIN(user_data);
  xue_hua_file_operations_plugin_handle_method_call(plugin, method_call);
}

void xue_hua_file_operations_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  XueHuaFileOperationsPlugin* plugin = XUE_HUA_FILE_OPERATIONS_PLUGIN(
      g_object_new(xue_hua_file_operations_plugin_get_type(), nullptr));
  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "xue_hua_file_operations",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);
  g_object_unref(plugin);
}
