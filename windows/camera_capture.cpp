#ifndef NOMINMAX
#define NOMINMAX  // <windows.h> min/max macros break std::min/std::max
#endif

#include "camera_capture.h"

#include <windows.h>

#include <mfapi.h>
#include <mfcaptureengine.h>
#include <mferror.h>
#include <mfidl.h>
#include <propidl.h>
#include <ocidl.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <deque>
#include <filesystem>
#include <mutex>
#include <string>
#include <vector>

namespace xue_hua_file_operations {

using Microsoft::WRL::ComPtr;

void CameraTargetSize(int width, int height, double max_width,
                      double max_height, int *out_width, int *out_height) {
  double factor = 1.0;
  if (max_width > 0) factor = std::max(factor, width / max_width);
  if (max_height > 0) factor = std::max(factor, height / max_height);
  if (factor <= 1.0) {
    *out_width = width;
    *out_height = height;
    return;
  }
  *out_width = std::max(1, static_cast<int>(std::floor(width / factor)));
  *out_height = std::max(1, static_cast<int>(std::floor(height / factor)));
}

namespace {

constexpr UINT kEventMessage = WM_APP + 1;
constexpr UINT_PTR kMaxDurationTimer = 1;
constexpr UINT_PTR kAutoPressTimer = 2;
constexpr UINT_PTR kAutoStopTimer = 3;
constexpr int kIdCancel = 2;
constexpr int kIdPrimary = 3;
constexpr int kIdStop = 4;
constexpr wchar_t kWindowClass[] = L"XueHuaFileOperationsCameraWindow";

// HRESULTs that mean "the user / the OS privacy settings blocked the camera".
bool IsAccessDenied(HRESULT hr) {
  return hr == E_ACCESSDENIED ||
         hr == HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED) ||
         hr == MF_E_HW_MFT_FAILED_START_STREAMING;
}

// UI-test hook: with XUE_HUA_CAMERA_TEST_AUTO=1 in the environment the
// shutter / Record button is pressed ~1.5 s after the preview started and a
// recording is stopped 2 s after it started. The real camera is still used.
bool AutoTestEnabled() {
  wchar_t value[8] = {};
  DWORD n = GetEnvironmentVariableW(L"XUE_HUA_CAMERA_TEST_AUTO", value, 8);
  return n == 1 && value[0] == L'1';
}

std::string HrMessage(const char *what, HRESULT hr) {
  char buffer[160];
  std::snprintf(buffer, sizeof(buffer), "%s (HRESULT 0x%08lX)", what,
                static_cast<unsigned long>(hr));
  return buffer;
}

std::wstring Lower(std::wstring text) {
  std::transform(text.begin(), text.end(), text.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
  return text;
}

bool Contains(const std::wstring &text, const wchar_t *needle) {
  return text.find(needle) != std::wstring::npos;
}

// Built-in webcams are usually called "Integrated Camera", "Front camera" or
// "Built-in ..."; everything else is treated as an external camera.
bool LooksBuiltIn(const std::wstring &name) {
  const std::wstring lower = Lower(name);
  return Contains(lower, L"integrated") || Contains(lower, L"built-in") ||
         Contains(lower, L"builtin") || Contains(lower, L"internal") ||
         Contains(lower, L"front");
}

bool LooksRear(const std::wstring &name) {
  const std::wstring lower = Lower(name);
  return Contains(lower, L"rear") || Contains(lower, L"back");
}

std::wstring FriendlyName(IMFActivate *activate) {
  WCHAR *name = nullptr;
  UINT32 length = 0;
  std::wstring result;
  if (SUCCEEDED(activate->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME,
                                             &name, &length)) &&
      name) {
    result.assign(name, length);
    CoTaskMemFree(name);
  }
  return result;
}

// Enumerates capture devices of `source_type` (video or audio).
std::vector<ComPtr<IMFActivate>> EnumerateDevices(GUID source_type) {
  std::vector<ComPtr<IMFActivate>> devices;
  ComPtr<IMFAttributes> attributes;
  if (FAILED(MFCreateAttributes(&attributes, 1))) return devices;
  if (FAILED(attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                                 source_type))) {
    return devices;
  }
  IMFActivate **raw = nullptr;
  UINT32 count = 0;
  if (FAILED(MFEnumDeviceSources(attributes.Get(), &raw, &count)) || !raw) {
    return devices;
  }
  for (UINT32 i = 0; i < count; ++i) {
    devices.emplace_back(raw[i]);  // takes over the reference
  }
  CoTaskMemFree(raw);
  return devices;
}

ComPtr<IMFActivate> PickCamera(
    const std::vector<ComPtr<IMFActivate>> &devices, bool prefer_front) {
  if (devices.empty()) return nullptr;
  for (const auto &device : devices) {
    const std::wstring name = FriendlyName(device.Get());
    if (prefer_front ? LooksBuiltIn(name)
                     : (LooksRear(name) || !LooksBuiltIn(name))) {
      return device;
    }
  }
  return devices.front();
}

std::wstring NewCapturePath(bool is_video) {
  wchar_t temp[MAX_PATH + 1];
  DWORD length = GetTempPathW(MAX_PATH, temp);
  std::filesystem::path dir =
      std::filesystem::path(std::wstring(temp, length)) /
      L"xue_hua_file_operations";
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  GUID guid;
  CoCreateGuid(&guid);
  wchar_t id[40];
  StringFromGUID2(guid, id, 40);
  std::wstring name = L"capture_";
  for (const wchar_t *c = id; *c; ++c) {
    if (*c != L'{' && *c != L'}') name += *c;
  }
  name += is_video ? L".mp4" : L".jpg";
  return (dir / name).wstring();
}

// Re-encodes the JPEG at `path` (downscale and/or quality). Keeps the original
// on failure.
bool ReencodeJpeg(const std::wstring &path, const CameraOptions &options) {
  const bool resize = options.max_width > 0 || options.max_height > 0;
  const bool quality = options.image_quality >= 0;
  if (!resize && !quality) return true;

  ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&factory)))) {
    return false;
  }
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromFilename(
          path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand,
          &decoder))) {
    return false;
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame))) return false;
  UINT width = 0, height = 0;
  frame->GetSize(&width, &height);
  int target_w = static_cast<int>(width), target_h = static_cast<int>(height);
  CameraTargetSize(target_w, target_h, options.max_width, options.max_height,
                   &target_w, &target_h);

  ComPtr<IWICBitmapSource> source = frame;
  ComPtr<IWICBitmapScaler> scaler;
  if (target_w != static_cast<int>(width) ||
      target_h != static_cast<int>(height)) {
    if (FAILED(factory->CreateBitmapScaler(&scaler)) ||
        FAILED(scaler->Initialize(frame.Get(), target_w, target_h,
                                  WICBitmapInterpolationModeFant))) {
      return false;
    }
    source = scaler;
  }

  const std::wstring temp_path = path + L".tmp";
  {
    ComPtr<IWICStream> stream;
    if (FAILED(factory->CreateStream(&stream)) ||
        FAILED(stream->InitializeFromFilename(temp_path.c_str(),
                                              GENERIC_WRITE))) {
      return false;
    }
    ComPtr<IWICBitmapEncoder> encoder;
    if (FAILED(factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr,
                                      &encoder)) ||
        FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
      return false;
    }
    ComPtr<IWICBitmapFrameEncode> out_frame;
    ComPtr<IPropertyBag2> bag;
    if (FAILED(encoder->CreateNewFrame(&out_frame, &bag))) return false;
    if (quality) {
      PROPBAG2 option = {};
      option.pstrName = const_cast<LPOLESTR>(L"ImageQuality");
      VARIANT value;
      VariantInit(&value);
      value.vt = VT_R4;
      value.fltVal = std::clamp(options.image_quality, 0, 100) / 100.0f;
      bag->Write(1, &option, &value);
    }
    if (FAILED(out_frame->Initialize(bag.Get())) ||
        FAILED(out_frame->SetSize(target_w, target_h))) {
      return false;
    }
    WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
    out_frame->SetPixelFormat(&format);
    if (FAILED(out_frame->WriteSource(source.Get(), nullptr)) ||
        FAILED(out_frame->Commit()) || FAILED(encoder->Commit())) {
      return false;
    }
  }
  if (!MoveFileExW(temp_path.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING)) {
    DeleteFileW(temp_path.c_str());
    return false;
  }
  return true;
}

// Receives the capture engine's asynchronous events (on MF worker threads) and
// forwards them to the preview window's thread.
class EngineCallback : public IMFCaptureEngineOnEventCallback {
 public:
  struct Event {
    GUID type;
    HRESULT status;
  };

  // IUnknown
  STDMETHODIMP QueryInterface(REFIID riid, void **object) override {
    if (riid == IID_IUnknown || riid == IID_IMFCaptureEngineOnEventCallback) {
      *object = static_cast<IMFCaptureEngineOnEventCallback *>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
  STDMETHODIMP_(ULONG) Release() override {
    ULONG count = --refs_;
    if (count == 0) delete this;
    return count;
  }

  // IMFCaptureEngineOnEventCallback
  STDMETHODIMP OnEvent(IMFMediaEvent *event) override {
    Event e = {};
    if (!event || FAILED(event->GetExtendedType(&e.type))) return S_OK;
    if (FAILED(event->GetStatus(&e.status))) e.status = E_FAIL;
    std::lock_guard<std::mutex> lock(mutex_);
    queue_.push_back(e);
    if (window_) PostMessageW(window_, kEventMessage, 0, 0);
    return S_OK;
  }

  void SetWindow(HWND window) {
    std::lock_guard<std::mutex> lock(mutex_);
    window_ = window;
  }

  bool Pop(Event *event) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (queue_.empty()) return false;
    *event = queue_.front();
    queue_.pop_front();
    return true;
  }

 private:
  ~EngineCallback() = default;
  std::atomic<ULONG> refs_{1};
  std::mutex mutex_;
  HWND window_ = nullptr;
  std::deque<Event> queue_;
};

class CaptureSession {
 public:
  CaptureSession(HWND owner, const CameraOptions &options)
      : owner_(owner), options_(options) {}

  CameraResult Run();

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  bool CreateUi();
  bool InitializeEngine();
  void OnEngineEvents();
  void OnEngineEvent(const EngineCallback::Event &event);
  bool ConfigurePreview();
  void StartCapture();
  bool StartPhoto();
  bool StartRecording();
  void StopRecording();
  void Cancel();
  void Finish(CameraResult::Status status, const std::string &message);
  void FinishWithHr(const char *what, HRESULT hr);
  void ShutdownEngine();

  HWND owner_;
  CameraOptions options_;
  HWND window_ = nullptr;
  HWND preview_ = nullptr;
  HWND primary_button_ = nullptr;
  HWND stop_button_ = nullptr;

  ComPtr<IMFCaptureEngine> engine_;
  ComPtr<EngineCallback> callback_;
  ComPtr<IMFActivate> video_device_;
  ComPtr<IMFActivate> audio_device_;
  bool has_audio_ = false;

  bool preview_running_ = false;
  bool recording_ = false;
  bool cancelling_ = false;
  bool done_ = false;
  std::wstring output_path_;
  CameraResult result_;
};

CameraResult CaptureSession::Run() {
  HRESULT hr = MFStartup(MF_VERSION);
  if (FAILED(hr)) {
    result_.status = CameraResult::Status::kIoError;
    result_.message = HrMessage("Unable to start Media Foundation", hr);
    return result_;
  }

  auto cameras = EnumerateDevices(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  video_device_ = PickCamera(cameras, options_.prefer_front);
  if (!video_device_) {
    MFShutdown();
    result_.status = CameraResult::Status::kUnsupported;
    result_.message = "No camera was found on this computer";
    return result_;
  }
  if (options_.is_video) {
    auto microphones =
        EnumerateDevices(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_AUDCAP_GUID);
    if (!microphones.empty()) {
      audio_device_ = microphones.front();
      has_audio_ = true;
    }
  }

  if (!CreateUi()) {
    MFShutdown();
    result_.status = CameraResult::Status::kIoError;
    result_.message = "Unable to create the camera window";
    return result_;
  }
  if (owner_) EnableWindow(owner_, FALSE);
  ShowWindow(window_, SW_SHOW);
  UpdateWindow(window_);

  if (!InitializeEngine()) {
    // Finish() has already stored the failure.
    done_ = true;
  }

  MSG msg;
  while (!done_) {
    BOOL got = GetMessageW(&msg, nullptr, 0, 0);
    if (got <= 0) {
      if (got == 0) PostQuitMessage(static_cast<int>(msg.wParam));
      break;
    }
    if (!IsDialogMessageW(window_, &msg)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
  }

  ShutdownEngine();
  if (callback_) callback_->SetWindow(nullptr);
  if (owner_) EnableWindow(owner_, TRUE);
  if (window_) {
    DestroyWindow(window_);
    window_ = nullptr;
  }
  if (owner_) SetForegroundWindow(owner_);
  engine_.Reset();
  video_device_.Reset();
  audio_device_.Reset();
  callback_.Reset();
  MFShutdown();

  if (result_.status != CameraResult::Status::kOk && !output_path_.empty()) {
    DeleteFileW(output_path_.c_str());
  }
  return result_;
}

bool CaptureSession::CreateUi() {
  HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSW wc = {};
  wc.lpfnWndProc = &CaptureSession::WindowProc;
  wc.hInstance = instance;
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
  wc.lpszClassName = kWindowClass;
  RegisterClassW(&wc);  // fails harmlessly when already registered

  const int client_w = 640, client_h = 520;
  RECT rect = {0, 0, client_w, client_h};
  const DWORD style = WS_POPUP | WS_CAPTION | WS_SYSMENU;
  AdjustWindowRect(&rect, style, FALSE);
  const wchar_t *title = options_.is_video ? L"Record Video" : L"Take Photo";
  window_ = CreateWindowExW(
      WS_EX_DLGMODALFRAME, kWindowClass, title, style, CW_USEDEFAULT,
      CW_USEDEFAULT, rect.right - rect.left, rect.bottom - rect.top, owner_,
      nullptr, instance, this);
  if (!window_) return false;

  // Center over the owner (or the screen).
  RECT window_rect, bounds;
  GetWindowRect(window_, &window_rect);
  if (owner_) {
    GetWindowRect(owner_, &bounds);
  } else {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &bounds, 0);
  }
  const int w = window_rect.right - window_rect.left;
  const int h = window_rect.bottom - window_rect.top;
  SetWindowPos(window_, nullptr,
               bounds.left + ((bounds.right - bounds.left) - w) / 2,
               bounds.top + ((bounds.bottom - bounds.top) - h) / 2, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER);

  preview_ = CreateWindowExW(0, L"STATIC", nullptr,
                             WS_CHILD | WS_VISIBLE | SS_BLACKRECT, 0, 0,
                             client_w, client_h - 48, window_, nullptr,
                             instance, nullptr);
  CreateWindowExW(0, L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                  16, client_h - 40, 100, 30, window_,
                  reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdCancel)),
                  instance, nullptr);
  primary_button_ = CreateWindowExW(
      0, L"BUTTON", options_.is_video ? L"Record" : L"Take Photo",
      WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_DISABLED | BS_DEFPUSHBUTTON,
      client_w - 136, client_h - 40, 120, 30, window_,
      reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdPrimary)), instance,
      nullptr);
  if (options_.is_video) {
    stop_button_ = CreateWindowExW(
        0, L"BUTTON", L"Stop", WS_CHILD | WS_TABSTOP,
        client_w - 136, client_h - 40, 120, 30, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdStop)), instance,
        nullptr);
  }
  HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
  for (HWND child = GetWindow(window_, GW_CHILD); child;
       child = GetWindow(child, GW_HWNDNEXT)) {
    SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  }
  return true;
}

bool CaptureSession::InitializeEngine() {
  ComPtr<IMFCaptureEngineClassFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_MFCaptureEngineClassFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
  if (SUCCEEDED(hr)) {
    hr = factory->CreateInstance(CLSID_MFCaptureEngine,
                                 IID_PPV_ARGS(&engine_));
  }
  if (FAILED(hr)) {
    FinishWithHr("Unable to create the capture engine", hr);
    return false;
  }

  callback_.Attach(new EngineCallback());
  callback_->SetWindow(window_);

  ComPtr<IMFAttributes> attributes;
  hr = MFCreateAttributes(&attributes, 1);
  if (SUCCEEDED(hr) && !has_audio_) {
    attributes->SetUINT32(MF_CAPTURE_ENGINE_USE_VIDEO_DEVICE_ONLY, TRUE);
  }
  if (SUCCEEDED(hr)) {
    // The engine takes the devices as IUnknown activates.
    hr = engine_->Initialize(callback_.Get(), attributes.Get(),
                             has_audio_ ? audio_device_.Get() : nullptr,
                             video_device_.Get());
  }
  if (FAILED(hr)) {
    FinishWithHr("Unable to open the camera", hr);
    return false;
  }
  // Continues in OnEngineEvent(MF_CAPTURE_ENGINE_INITIALIZED).
  return true;
}

HRESULT SetFrameInfo(IMFMediaType *from, IMFMediaType *to) {
  UINT32 w = 0, h = 0;
  if (SUCCEEDED(MFGetAttributeSize(from, MF_MT_FRAME_SIZE, &w, &h))) {
    MFSetAttributeSize(to, MF_MT_FRAME_SIZE, w, h);
  }
  UINT32 num = 30, den = 1;
  if (SUCCEEDED(MFGetAttributeRatio(from, MF_MT_FRAME_RATE, &num, &den)) &&
      den != 0) {
    MFSetAttributeRatio(to, MF_MT_FRAME_RATE, num, den);
  } else {
    MFSetAttributeRatio(to, MF_MT_FRAME_RATE, 30, 1);
  }
  MFSetAttributeRatio(to, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  to->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  return S_OK;
}

bool CaptureSession::ConfigurePreview() {
  ComPtr<IMFCaptureSource> source;
  ComPtr<IMFCaptureSink> sink;
  HRESULT hr = engine_->GetSource(&source);
  if (SUCCEEDED(hr)) {
    hr = engine_->GetSink(MF_CAPTURE_ENGINE_SINK_TYPE_PREVIEW, &sink);
  }
  ComPtr<IMFCapturePreviewSink> preview;
  if (SUCCEEDED(hr)) hr = sink.As(&preview);
  ComPtr<IMFMediaType> source_type;
  if (SUCCEEDED(hr)) {
    hr = source->GetCurrentDeviceMediaType(
        static_cast<DWORD>(MF_CAPTURE_ENGINE_PREFERRED_SOURCE_STREAM_FOR_VIDEO_PREVIEW),
        &source_type);
  }
  if (SUCCEEDED(hr)) {
    preview->RemoveAllStreams();
    hr = preview->SetRenderHandle(preview_);
  }
  ComPtr<IMFMediaType> type;
  if (SUCCEEDED(hr)) hr = MFCreateMediaType(&type);
  if (SUCCEEDED(hr)) hr = source_type->CopyAllItems(type.Get());
  if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  if (SUCCEEDED(hr)) {
    DWORD index = 0;
    hr = preview->AddStream(
        static_cast<DWORD>(MF_CAPTURE_ENGINE_PREFERRED_SOURCE_STREAM_FOR_VIDEO_PREVIEW),
        type.Get(), nullptr, &index);
  }
  if (SUCCEEDED(hr)) hr = engine_->StartPreview();
  if (FAILED(hr)) {
    FinishWithHr("Unable to show the camera preview", hr);
    return false;
  }
  return true;
}

void CaptureSession::OnEngineEvents() {
  EngineCallback::Event event;
  while (!done_ && callback_ && callback_->Pop(&event)) {
    OnEngineEvent(event);
  }
}

void CaptureSession::OnEngineEvent(const EngineCallback::Event &event) {
  if (event.type == MF_CAPTURE_ENGINE_INITIALIZED) {
    if (FAILED(event.status)) {
      FinishWithHr("Unable to open the camera", event.status);
      return;
    }
    ConfigurePreview();
  } else if (event.type == MF_CAPTURE_ENGINE_PREVIEW_STARTED) {
    preview_running_ = true;
    if (primary_button_) EnableWindow(primary_button_, TRUE);
    if (AutoTestEnabled()) SetTimer(window_, kAutoPressTimer, 1500, nullptr);
  } else if (event.type == MF_CAPTURE_ENGINE_PREVIEW_STOPPED) {
    preview_running_ = false;
  } else if (event.type == MF_CAPTURE_ENGINE_PHOTO_TAKEN) {
    if (cancelling_) {
      Finish(CameraResult::Status::kCancelled, "");
    } else if (FAILED(event.status)) {
      FinishWithHr("Unable to take the photo", event.status);
    } else {
      if (!ReencodeJpeg(output_path_, options_)) {
        // The unmodified JPEG is still a valid photo.
      }
      result_.path = output_path_;
      Finish(CameraResult::Status::kOk, "");
    }
  } else if (event.type == MF_CAPTURE_ENGINE_RECORD_STARTED) {
    recording_ = true;
    if (cancelling_) {
      StopRecording();
      return;
    }
    if (AutoTestEnabled()) SetTimer(window_, kAutoStopTimer, 2000, nullptr);
    if (primary_button_) ShowWindow(primary_button_, SW_HIDE);
    if (stop_button_) ShowWindow(stop_button_, SW_SHOW);
    if (options_.max_duration_seconds > 0) {
      SetTimer(window_, kMaxDurationTimer,
               static_cast<UINT>(options_.max_duration_seconds) * 1000, nullptr);
    }
  } else if (event.type == MF_CAPTURE_ENGINE_RECORD_STOPPED) {
    recording_ = false;
    KillTimer(window_, kMaxDurationTimer);
    if (cancelling_) {
      Finish(CameraResult::Status::kCancelled, "");
    } else if (FAILED(event.status)) {
      FinishWithHr("Unable to record the video", event.status);
    } else {
      result_.path = output_path_;
      Finish(CameraResult::Status::kOk, "");
    }
  } else if (event.type == MF_CAPTURE_ENGINE_ERROR) {
    FinishWithHr("The camera reported an error", event.status);
  }
}

void CaptureSession::StartCapture() {
  if (!preview_running_) return;
  EnableWindow(primary_button_, FALSE);
  const bool started = options_.is_video ? StartRecording() : StartPhoto();
  if (!started && !done_) {
    EnableWindow(primary_button_, TRUE);
  }
}

bool CaptureSession::StartPhoto() {
  ComPtr<IMFCaptureSource> source;
  ComPtr<IMFCaptureSink> sink;
  HRESULT hr = engine_->GetSource(&source);
  if (SUCCEEDED(hr)) hr = engine_->GetSink(MF_CAPTURE_ENGINE_SINK_TYPE_PHOTO, &sink);
  ComPtr<IMFCapturePhotoSink> photo;
  if (SUCCEEDED(hr)) hr = sink.As(&photo);

  // Cameras without a dedicated still stream take the photo from the preview.
  DWORD stream = static_cast<DWORD>(MF_CAPTURE_ENGINE_PREFERRED_SOURCE_STREAM_FOR_PHOTO);
  ComPtr<IMFMediaType> source_type;
  if (SUCCEEDED(hr)) {
    hr = source->GetCurrentDeviceMediaType(stream, &source_type);
    if (FAILED(hr)) {
      stream = static_cast<DWORD>(MF_CAPTURE_ENGINE_PREFERRED_SOURCE_STREAM_FOR_VIDEO_PREVIEW);
      hr = source->GetCurrentDeviceMediaType(stream, &source_type);
    }
  }
  ComPtr<IMFMediaType> type;
  if (SUCCEEDED(hr)) hr = MFCreateMediaType(&type);
  if (SUCCEEDED(hr)) hr = source_type->CopyAllItems(type.Get());
  if (SUCCEEDED(hr)) hr = type->SetGUID(MF_MT_SUBTYPE, MFImageFormat_JPEG);
  if (SUCCEEDED(hr)) {
    photo->RemoveAllStreams();
    DWORD index = 0;
    hr = photo->AddStream(stream, type.Get(), nullptr, &index);
  }
  if (SUCCEEDED(hr)) {
    output_path_ = NewCapturePath(false);
    hr = photo->SetOutputFileName(output_path_.c_str());
  }
  if (SUCCEEDED(hr)) hr = engine_->TakePhoto();
  if (FAILED(hr)) {
    FinishWithHr("Unable to take the photo", hr);
    return false;
  }
  return true;
}

bool CaptureSession::StartRecording() {
  ComPtr<IMFCaptureSource> source;
  ComPtr<IMFCaptureSink> sink;
  HRESULT hr = engine_->GetSource(&source);
  if (SUCCEEDED(hr)) hr = engine_->GetSink(MF_CAPTURE_ENGINE_SINK_TYPE_RECORD, &sink);
  ComPtr<IMFCaptureRecordSink> record;
  if (SUCCEEDED(hr)) hr = sink.As(&record);

  const DWORD video_stream =
      static_cast<DWORD>(MF_CAPTURE_ENGINE_PREFERRED_SOURCE_STREAM_FOR_VIDEO_RECORD);
  ComPtr<IMFMediaType> source_type;
  if (SUCCEEDED(hr)) hr = source->GetCurrentDeviceMediaType(video_stream, &source_type);
  ComPtr<IMFMediaType> video_type;
  if (SUCCEEDED(hr)) hr = MFCreateMediaType(&video_type);
  if (SUCCEEDED(hr)) {
    video_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    video_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    video_type->SetUINT32(MF_MT_AVG_BITRATE, 8000000);
    SetFrameInfo(source_type.Get(), video_type.Get());
    record->RemoveAllStreams();
    DWORD index = 0;
    hr = record->AddStream(video_stream, video_type.Get(), nullptr, &index);
  }
  if (SUCCEEDED(hr) && has_audio_) {
    ComPtr<IMFMediaType> audio_type;
    if (SUCCEEDED(MFCreateMediaType(&audio_type))) {
      audio_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
      audio_type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
      audio_type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
      audio_type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 44100);
      audio_type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
      audio_type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 16000);
      audio_type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 1);
      DWORD index = 0;
      // A microphone problem must not prevent recording the picture.
      record->AddStream(
          static_cast<DWORD>(MF_CAPTURE_ENGINE_PREFERRED_SOURCE_STREAM_FOR_AUDIO),
          audio_type.Get(), nullptr, &index);
    }
  }
  if (SUCCEEDED(hr)) {
    output_path_ = NewCapturePath(true);
    hr = record->SetOutputFileName(output_path_.c_str());
  }
  if (SUCCEEDED(hr)) hr = engine_->StartRecord();
  if (FAILED(hr)) {
    FinishWithHr("Unable to record the video", hr);
    return false;
  }
  // Continues in OnEngineEvent(MF_CAPTURE_ENGINE_RECORD_STARTED).
  return true;
}

void CaptureSession::StopRecording() {
  if (!recording_ || !engine_) return;
  if (stop_button_) EnableWindow(stop_button_, FALSE);
  HRESULT hr = engine_->StopRecord(TRUE, FALSE);
  if (FAILED(hr)) FinishWithHr("Unable to stop the recording", hr);
  // Continues in OnEngineEvent(MF_CAPTURE_ENGINE_RECORD_STOPPED).
}

void CaptureSession::Cancel() {
  if (done_) return;
  cancelling_ = true;
  if (recording_) {
    StopRecording();  // finishes (and deletes the file) once stopped
    return;
  }
  Finish(CameraResult::Status::kCancelled, "");
}

void CaptureSession::Finish(CameraResult::Status status,
                            const std::string &message) {
  if (done_) return;
  result_.status = status;
  result_.message = message;
  if (status != CameraResult::Status::kOk) result_.path.clear();
  done_ = true;
  // Wake the message loop even when nothing else is queued.
  if (window_) PostMessageW(window_, WM_NULL, 0, 0);
}

void CaptureSession::FinishWithHr(const char *what, HRESULT hr) {
  Finish(IsAccessDenied(hr) ? CameraResult::Status::kPermissionDenied
                            : CameraResult::Status::kIoError,
         IsAccessDenied(hr)
             ? "Camera access is blocked. Allow desktop apps to use the camera "
               "in Windows Settings > Privacy & security > Camera."
             : HrMessage(what, hr));
}

void CaptureSession::ShutdownEngine() {
  if (!engine_) return;
  if (recording_) {
    engine_->StopRecord(TRUE, FALSE);
  }
  if (preview_running_) {
    engine_->StopPreview();
    // Give the engine a moment to deliver MF_CAPTURE_ENGINE_PREVIEW_STOPPED.
    for (int i = 0; i < 40 && preview_running_; ++i) {
      EngineCallback::Event event;
      while (callback_ && callback_->Pop(&event)) {
        if (event.type == MF_CAPTURE_ENGINE_PREVIEW_STOPPED) {
          preview_running_ = false;
        } else if (event.type == MF_CAPTURE_ENGINE_RECORD_STOPPED) {
          recording_ = false;
        }
      }
      if (preview_running_) Sleep(25);
    }
  }
}

LRESULT CALLBACK CaptureSession::WindowProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto *create = reinterpret_cast<CREATESTRUCTW *>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto *self = reinterpret_cast<CaptureSession *>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) return self->HandleMessage(hwnd, message, wparam, lparam);
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT CaptureSession::HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  switch (message) {
    case kEventMessage:
      OnEngineEvents();
      return 0;
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kIdCancel:
          Cancel();
          return 0;
        case kIdPrimary:
          StartCapture();
          return 0;
        case kIdStop:
          StopRecording();
          return 0;
      }
      break;
    case WM_TIMER:
      if (wparam == kAutoPressTimer) {
        KillTimer(hwnd, kAutoPressTimer);
        StartCapture();
        return 0;
      }
      if (wparam == kAutoStopTimer) {
        KillTimer(hwnd, kAutoStopTimer);
        StopRecording();
        return 0;
      }
      if (wparam == kMaxDurationTimer) {
        KillTimer(hwnd, kMaxDurationTimer);
        StopRecording();
        return 0;
      }
      break;
    case WM_SIZE:
      if (engine_ && preview_running_) {
        ComPtr<IMFCaptureSink> sink;
        ComPtr<IMFCapturePreviewSink> preview;
        if (SUCCEEDED(engine_->GetSink(MF_CAPTURE_ENGINE_SINK_TYPE_PREVIEW,
                                       &sink)) &&
            SUCCEEDED(sink.As(&preview))) {
          preview->UpdateVideo(nullptr, nullptr, nullptr);
        }
      }
      break;
    case WM_CLOSE:
      Cancel();
      return 0;  // the window is destroyed by Run()
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace

CameraResult CaptureWithCamera(HWND owner, const CameraOptions &options) {
  CaptureSession session(owner, options);
  return session.Run();
}

}  // namespace xue_hua_file_operations
