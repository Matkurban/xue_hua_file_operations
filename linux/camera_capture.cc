#include "camera_capture.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <glib/gstdio.h>

#include <cstring>
#include <vector>

#ifdef XUE_HUA_HAVE_GSTREAMER
#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/video/video.h>
#endif

void xue_hua_camera_target_size(int width, int height, double max_width,
                                double max_height, int* out_width,
                                int* out_height) {
  double factor = 1.0;
  if (max_width > 0 && width > 0) {
    factor = std::max(factor, width / max_width);
  }
  if (max_height > 0 && height > 0) {
    factor = std::max(factor, height / max_height);
  }
  if (factor <= 1.0) {
    *out_width = width;
    *out_height = height;
    return;
  }
  *out_width = std::max(1, static_cast<int>(std::floor(width / factor)));
  *out_height = std::max(1, static_cast<int>(std::floor(height / factor)));
}

#ifndef XUE_HUA_HAVE_GSTREAMER

bool xue_hua_camera_is_built_in(void) { return false; }

XueHuaCameraResult xue_hua_camera_capture(GtkWindow*,
                                          const XueHuaCameraOptions&) {
  XueHuaCameraResult result;
  result.status = XueHuaCameraResult::kUnsupported;
  result.message =
      "Camera capture is unavailable: the plugin was built without GStreamer "
      "(install the GStreamer development packages and rebuild)";
  return result;
}

#else  // XUE_HUA_HAVE_GSTREAMER

namespace {

// Environment variables used by automated tests (no camera hardware):
//   XUE_HUA_CAMERA_TEST_SOURCE=videotestsrc  use GStreamer's test pattern
//   XUE_HUA_CAMERA_TEST_AUTO=1               press the buttons automatically
const char kTestSourceEnv[] = "XUE_HUA_CAMERA_TEST_SOURCE";
const char kTestAutoEnv[] = "XUE_HUA_CAMERA_TEST_AUTO";

enum Response {
  kResponseShutter = 1,
  kResponseRecord = 2,
  kResponseStop = 3,
};

struct Candidate {
  std::string description;  // gst-launch source element description
  std::string name;
};

bool factory_exists(const char* name) {
  GstElementFactory* factory = gst_element_factory_find(name);
  if (factory == nullptr) return false;
  gst_object_unref(factory);
  return true;
}

// Lists the available video sources, best candidate for `prefer_front` first.
std::vector<Candidate> find_sources(bool prefer_front) {
  std::vector<Candidate> sources;
  const char* test_source = g_getenv(kTestSourceEnv);
  if (test_source != nullptr && test_source[0] != '\0') {
    sources.push_back(
        {std::string(test_source) + " is-live=true", "test source"});
    return sources;
  }
  if (!factory_exists("v4l2src")) return sources;

  GstDeviceMonitor* monitor = gst_device_monitor_new();
  gst_device_monitor_add_filter(monitor, "Video/Source", nullptr);
  GList* devices = gst_device_monitor_get_devices(monitor);
  std::vector<Candidate> front;
  std::vector<Candidate> other;
  for (GList* it = devices; it != nullptr; it = it->next) {
    GstDevice* device = GST_DEVICE(it->data);
    g_autofree gchar* name = gst_device_get_display_name(device);
    GstStructure* props = gst_device_get_properties(device);
    const gchar* path =
        props != nullptr ? gst_structure_get_string(props, "device.path")
                         : nullptr;
    if (path == nullptr) {
      if (props != nullptr) gst_structure_free(props);
      continue;
    }
    Candidate candidate;
    candidate.description = std::string("v4l2src device=") + path;
    candidate.name = name != nullptr ? name : path;
    std::string lower = candidate.name;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    const bool is_front = lower.find("front") != std::string::npos ||
                          lower.find("user") != std::string::npos ||
                          lower.find("integrated") != std::string::npos ||
                          lower.find("built-in") != std::string::npos;
    (is_front ? front : other).push_back(candidate);
    gst_structure_free(props);
  }
  g_list_free_full(devices, g_object_unref);
  g_object_unref(monitor);

  // Laptops expose a single integrated (front) camera; external USB cameras
  // act as the "rear" one.
  const std::vector<Candidate>& first = prefer_front ? front : other;
  const std::vector<Candidate>& second = prefer_front ? other : front;
  sources.insert(sources.end(), first.begin(), first.end());
  sources.insert(sources.end(), second.begin(), second.end());
  return sources;
}

struct VideoEncoder {
  std::string chain;  // "x264enc ... ! h264parse ! mp4mux name=mux"
  std::string extension;
};

bool pick_video_encoder(VideoEncoder* out) {
  if (factory_exists("x264enc") && factory_exists("h264parse") &&
      factory_exists("mp4mux")) {
    *out = {"x264enc tune=zerolatency speed-preset=veryfast ! h264parse ! "
            "mp4mux name=mux",
            ".mp4"};
    return true;
  }
  if (factory_exists("openh264enc") && factory_exists("h264parse") &&
      factory_exists("mp4mux")) {
    *out = {"openh264enc ! h264parse ! mp4mux name=mux", ".mp4"};
    return true;
  }
  if (factory_exists("vp8enc") && factory_exists("webmmux")) {
    *out = {"vp8enc deadline=1 cpu-used=8 ! webmmux name=mux", ".webm"};
    return true;
  }
  return false;
}

class CaptureSession {
 public:
  explicit CaptureSession(const XueHuaCameraOptions& options)
      : options_(options) {}

  ~CaptureSession() { Teardown(); }

  // Builds and starts the pipeline for `source`. Returns false and fills
  // `result` on failure.
  bool Start(const Candidate& source, XueHuaCameraResult* result) {
    std::string description =
        source.description +
        " ! videoconvert ! tee name=t "
        "t. ! queue leaky=downstream max-size-buffers=2 ! videoconvert ! "
        "video/x-raw,format=RGB ! appsink name=preview max-buffers=1 "
        "drop=true sync=false";
    if (options_.is_video) {
      if (!pick_video_encoder(&encoder_)) {
        result->status = XueHuaCameraResult::kUnsupported;
        result->message =
            "No video encoder found; install the GStreamer 'good' plugins "
            "(vp8enc / webmmux) or 'ugly' plugins (x264enc)";
        return false;
      }
      g_autofree gchar* tmp_dir = g_build_filename(
          g_get_tmp_dir(), "xue_hua_file_operations", nullptr);
      g_mkdir_with_parents(tmp_dir, 0755);
      g_autofree gchar* uuid = g_uuid_string_random();
      g_autofree gchar* file = g_strdup_printf("%s/capture_%s%s", tmp_dir,
                                               uuid, encoder_.extension.c_str());
      output_path_ = file;
      description +=
          " t. ! queue ! valve name=rv drop=true ! videoconvert ! " +
          encoder_.chain + " ! filesink name=out location=\"" + output_path_ +
          "\"";
    }

    GError* error = nullptr;
    pipeline_ = gst_parse_launch(description.c_str(), &error);
    if (pipeline_ == nullptr || error != nullptr) {
      result->status = XueHuaCameraResult::kIoError;
      result->message = error != nullptr ? error->message : "Invalid pipeline";
      if (error != nullptr) g_error_free(error);
      Teardown();
      return false;
    }
    preview_sink_ = gst_bin_get_by_name(GST_BIN(pipeline_), "preview");
    valve_ = options_.is_video
                 ? gst_bin_get_by_name(GST_BIN(pipeline_), "rv")
                 : nullptr;

    if (gst_element_set_state(pipeline_, GST_STATE_PLAYING) ==
        GST_STATE_CHANGE_FAILURE) {
      FillErrorFromBus(result);
      Teardown();
      return false;
    }
    GstState state;
    GstStateChangeReturn change =
        gst_element_get_state(pipeline_, &state, nullptr, 5 * GST_SECOND);
    if (change == GST_STATE_CHANGE_FAILURE) {
      FillErrorFromBus(result);
      Teardown();
      return false;
    }
    return true;
  }

  // Latest preview frame as an owned pixbuf (full camera resolution), or
  // nullptr when no frame arrived yet.
  GdkPixbuf* PullFrame() {
    if (preview_sink_ == nullptr) return nullptr;
    GstSample* sample =
        gst_app_sink_try_pull_sample(GST_APP_SINK(preview_sink_), 0);
    if (sample == nullptr) return nullptr;
    GdkPixbuf* pixbuf = nullptr;
    GstCaps* caps = gst_sample_get_caps(sample);
    GstBuffer* buffer = gst_sample_get_buffer(sample);
    GstVideoInfo info;
    GstMapInfo map;
    if (caps != nullptr && buffer != nullptr &&
        gst_video_info_from_caps(&info, caps) &&
        gst_buffer_map(buffer, &map, GST_MAP_READ)) {
      const int width = GST_VIDEO_INFO_WIDTH(&info);
      const int height = GST_VIDEO_INFO_HEIGHT(&info);
      const int src_stride = GST_VIDEO_INFO_PLANE_STRIDE(&info, 0);
      pixbuf = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, width, height);
      if (pixbuf != nullptr) {
        guchar* dst = gdk_pixbuf_get_pixels(pixbuf);
        const int dst_stride = gdk_pixbuf_get_rowstride(pixbuf);
        for (int y = 0; y < height; ++y) {
          if (static_cast<gsize>(y) * src_stride + width * 3 > map.size) {
            break;
          }
          memcpy(dst + y * dst_stride, map.data + y * src_stride, width * 3);
        }
      }
      gst_buffer_unmap(buffer, &map);
    }
    gst_sample_unref(sample);
    return pixbuf;
  }

  void StartRecording() {
    if (valve_ != nullptr) g_object_set(valve_, "drop", FALSE, NULL);
  }

  // Finalizes the recording file: EOS must reach the muxer before shutdown.
  bool StopRecording() {
    if (pipeline_ == nullptr) return false;
    // The valve must stay open: a closed valve swallows the EOS event too.
    gst_element_send_event(pipeline_, gst_event_new_eos());
    GstBus* bus = gst_element_get_bus(pipeline_);
    bool ok = false;
    const gint64 deadline = g_get_monotonic_time() + 30 * G_USEC_PER_SEC;
    while (g_get_monotonic_time() < deadline) {
      // An appsink only posts its EOS message after the application pulled
      // the last sample, so keep draining the preview branch while waiting.
      if (preview_sink_ != nullptr) {
        while (GstSample* sample = gst_app_sink_try_pull_sample(
                   GST_APP_SINK(preview_sink_), 0)) {
          gst_sample_unref(sample);
        }
      }
      GstMessage* message = gst_bus_timed_pop_filtered(
          bus, 20 * GST_MSECOND,
          static_cast<GstMessageType>(GST_MESSAGE_EOS | GST_MESSAGE_ERROR));
      if (message == nullptr) continue;
      if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS) {
        ok = true;
      } else {
        GError* error = nullptr;
        gchar* debug = nullptr;
        gst_message_parse_error(message, &error, &debug);
        g_printerr("xue_hua_file_operations: GStreamer error while finalizing: %s (%s)\n",
                   error != nullptr ? error->message : "?",
                   debug != nullptr ? debug : "");
        if (error != nullptr) g_error_free(error);
        g_free(debug);
      }
      gst_message_unref(message);
      if (ok) break;
    }
    if (!ok) g_printerr("xue_hua_file_operations: no EOS within 30 s\n");
    gst_object_unref(bus);
    return ok;
  }

  const std::string& output_path() const { return output_path_; }

 private:
  void FillErrorFromBus(XueHuaCameraResult* result) {
    result->status = XueHuaCameraResult::kIoError;
    result->message = "Unable to start the camera";
    GstBus* bus = gst_element_get_bus(pipeline_);
    GstMessage* message =
        gst_bus_timed_pop_filtered(bus, 2 * GST_SECOND, GST_MESSAGE_ERROR);
    if (message != nullptr) {
      GError* error = nullptr;
      gchar* debug = nullptr;
      gst_message_parse_error(message, &error, &debug);
      if (error != nullptr) {
        result->message = error->message;
        const bool denied =
            g_error_matches(error, GST_RESOURCE_ERROR,
                            GST_RESOURCE_ERROR_NOT_AUTHORIZED) ||
            (debug != nullptr && (strstr(debug, "Permission denied") != nullptr ||
                                  strstr(debug, "permission denied") != nullptr));
        if (denied) result->status = XueHuaCameraResult::kPermissionDenied;
        g_error_free(error);
      }
      g_free(debug);
      gst_message_unref(message);
    }
    gst_object_unref(bus);
  }

  void Teardown() {
    if (pipeline_ != nullptr) {
      gst_element_set_state(pipeline_, GST_STATE_NULL);
    }
    if (preview_sink_ != nullptr) {
      gst_object_unref(preview_sink_);
      preview_sink_ = nullptr;
    }
    if (valve_ != nullptr) {
      gst_object_unref(valve_);
      valve_ = nullptr;
    }
    if (pipeline_ != nullptr) {
      gst_object_unref(pipeline_);
      pipeline_ = nullptr;
    }
  }

  XueHuaCameraOptions options_;
  GstElement* pipeline_ = nullptr;
  GstElement* preview_sink_ = nullptr;
  GstElement* valve_ = nullptr;
  VideoEncoder encoder_;
  std::string output_path_;
};

struct Ui {
  GtkWidget* dialog = nullptr;
  GtkWidget* image = nullptr;
  GtkWidget* shutter = nullptr;
  GtkWidget* record = nullptr;
  GtkWidget* stop = nullptr;
  GdkPixbuf* last_frame = nullptr;  // owned, full resolution
  CaptureSession* session = nullptr;
  std::vector<guint> timers;  // pending one-shot timers
};

gboolean update_preview(gpointer user_data) {
  Ui* ui = static_cast<Ui*>(user_data);
  GdkPixbuf* frame = ui->session->PullFrame();
  if (frame == nullptr) return G_SOURCE_CONTINUE;
  if (ui->last_frame != nullptr) g_object_unref(ui->last_frame);
  ui->last_frame = frame;

  int width = gdk_pixbuf_get_width(frame);
  int height = gdk_pixbuf_get_height(frame);
  int view_width = 0;
  int view_height = 0;
  xue_hua_camera_target_size(width, height, 640, 480, &view_width,
                             &view_height);
  GdkPixbuf* scaled =
      view_width == width
          ? static_cast<GdkPixbuf*>(g_object_ref(frame))
          : gdk_pixbuf_scale_simple(frame, view_width, view_height,
                                    GDK_INTERP_NEAREST);
  gtk_image_set_from_pixbuf(GTK_IMAGE(ui->image), scaled);
  g_object_unref(scaled);
  return G_SOURCE_CONTINUE;
}

gboolean auto_respond(gpointer user_data) {
  Ui* ui = static_cast<Ui*>(user_data);
  gtk_dialog_response(GTK_DIALOG(ui->dialog),
                      GPOINTER_TO_INT(g_object_get_data(
                          G_OBJECT(ui->dialog), "auto-response")));
  return G_SOURCE_REMOVE;
}

gboolean timed_stop(gpointer user_data) {
  Ui* ui = static_cast<Ui*>(user_data);
  gtk_dialog_response(GTK_DIALOG(ui->dialog), kResponseStop);
  return G_SOURCE_REMOVE;
}

XueHuaCameraResult save_photo(const XueHuaCameraOptions& options,
                              GdkPixbuf* frame) {
  XueHuaCameraResult result;
  int width = gdk_pixbuf_get_width(frame);
  int height = gdk_pixbuf_get_height(frame);
  int target_width = width;
  int target_height = height;
  xue_hua_camera_target_size(width, height, options.max_width,
                             options.max_height, &target_width,
                             &target_height);
  GdkPixbuf* output =
      (target_width == width && target_height == height)
          ? static_cast<GdkPixbuf*>(g_object_ref(frame))
          : gdk_pixbuf_scale_simple(frame, target_width, target_height,
                                    GDK_INTERP_BILINEAR);

  g_autofree gchar* tmp_dir =
      g_build_filename(g_get_tmp_dir(), "xue_hua_file_operations", nullptr);
  g_mkdir_with_parents(tmp_dir, 0755);
  g_autofree gchar* uuid = g_uuid_string_random();
  g_autofree gchar* path =
      g_strdup_printf("%s/capture_%s.jpg", tmp_dir, uuid);
  const int quality = options.image_quality >= 0 ? options.image_quality : 95;
  g_autofree gchar* quality_text = g_strdup_printf("%d", quality);
  GError* error = nullptr;
  if (!gdk_pixbuf_save(output, path, "jpeg", &error, "quality", quality_text,
                       nullptr)) {
    result.status = XueHuaCameraResult::kIoError;
    result.message = error != nullptr ? error->message : "Unable to save photo";
    if (error != nullptr) g_error_free(error);
  } else {
    result.status = XueHuaCameraResult::kOk;
    result.path = path;
  }
  g_object_unref(output);
  return result;
}

}  // namespace

bool xue_hua_camera_is_built_in(void) { return true; }

XueHuaCameraResult xue_hua_camera_capture(GtkWindow* parent,
                                          const XueHuaCameraOptions& options) {
  XueHuaCameraResult result;
  static bool gst_ready = false;
  if (!gst_ready) {
    gst_init(nullptr, nullptr);
    gst_ready = true;
  }

  std::vector<Candidate> sources = find_sources(options.prefer_front);
  if (sources.empty()) {
    result.status = XueHuaCameraResult::kUnsupported;
    result.message = "No camera was found on this device";
    return result;
  }

  CaptureSession session(options);
  XueHuaCameraResult start_error;
  bool started = false;
  for (const Candidate& source : sources) {
    XueHuaCameraResult attempt;
    if (session.Start(source, &attempt)) {
      started = true;
      break;
    }
    start_error = attempt;
    if (attempt.status == XueHuaCameraResult::kUnsupported) break;
  }
  if (!started) return start_error;

  Ui ui;
  ui.session = &session;
  ui.dialog = gtk_dialog_new_with_buttons(
      options.is_video ? "Record video" : "Take photo", parent,
      static_cast<GtkDialogFlags>(GTK_DIALOG_MODAL |
                                  GTK_DIALOG_DESTROY_WITH_PARENT),
      "_Cancel", GTK_RESPONSE_CANCEL, nullptr);
  GtkWidget* content = gtk_dialog_get_content_area(GTK_DIALOG(ui.dialog));
  ui.image = gtk_image_new();
  gtk_widget_set_size_request(ui.image, 320, 240);
  gtk_box_pack_start(GTK_BOX(content), ui.image, TRUE, TRUE, 0);
  if (options.is_video) {
    ui.record = gtk_dialog_add_button(GTK_DIALOG(ui.dialog), "_Record",
                                      kResponseRecord);
    ui.stop = gtk_dialog_add_button(GTK_DIALOG(ui.dialog), "_Stop",
                                    kResponseStop);
  } else {
    ui.shutter = gtk_dialog_add_button(GTK_DIALOG(ui.dialog), "_Take photo",
                                       kResponseShutter);
  }
  gtk_widget_show_all(content);
  if (ui.stop != nullptr) gtk_widget_hide(ui.stop);

  guint preview_id = g_timeout_add(33, update_preview, &ui);
  const bool auto_mode = g_getenv(kTestAutoEnv) != nullptr;
  if (auto_mode) {
    g_object_set_data(
        G_OBJECT(ui.dialog), "auto-response",
        GINT_TO_POINTER(options.is_video ? kResponseRecord : kResponseShutter));
    ui.timers.push_back(g_timeout_add(1500, auto_respond, &ui));
  }
  gtk_widget_show(ui.dialog);

  bool recording = false;
  bool done = false;
  while (!done) {
    gint response = gtk_dialog_run(GTK_DIALOG(ui.dialog));
    switch (response) {
      case kResponseShutter: {
        if (ui.last_frame == nullptr) break;  // no frame yet, keep waiting
        result = save_photo(options, ui.last_frame);
        done = true;
        break;
      }
      case kResponseRecord:
        session.StartRecording();
        recording = true;
        gtk_widget_hide(ui.record);
        gtk_widget_show(ui.stop);
        if (options.max_duration_seconds > 0) {
          ui.timers.push_back(g_timeout_add_seconds(
              options.max_duration_seconds, timed_stop, &ui));
        }
        if (auto_mode) {
          g_object_set_data(G_OBJECT(ui.dialog), "auto-response",
                            GINT_TO_POINTER(kResponseStop));
          ui.timers.push_back(g_timeout_add(2000, auto_respond, &ui));
        }
        break;
      case kResponseStop:
        if (!recording) break;  // stale timer after the user stopped
        if (session.StopRecording()) {
          result.status = XueHuaCameraResult::kOk;
          result.path = session.output_path();
        } else {
          result.status = XueHuaCameraResult::kIoError;
          result.message = "Unable to finalize the recorded video";
        }
        done = true;
        break;
      default:
        // Cancel / window closed.
        result.status = XueHuaCameraResult::kCancelled;
        if (recording && !session.output_path().empty()) {
          session.StopRecording();
          g_remove(session.output_path().c_str());
        }
        done = true;
        break;
    }
  }

  g_source_remove(preview_id);
  for (guint id : ui.timers) {
    if (g_main_context_find_source_by_id(nullptr, id) != nullptr) {
      g_source_remove(id);
    }
  }
  gtk_widget_destroy(ui.dialog);
  if (ui.last_frame != nullptr) g_object_unref(ui.last_frame);
  return result;
}

#endif  // XUE_HUA_HAVE_GSTREAMER
