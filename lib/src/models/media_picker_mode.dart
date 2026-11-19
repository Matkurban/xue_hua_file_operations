/// Presentation mode for mobile image/video picking.
/// 移动端图片/视频选择器的展示模式。
enum MediaPickerMode {
  /// Use the operating system's built-in media picker
  /// (Android Photo Picker / iOS PHPickerViewController).
  /// 使用操作系统内置的原生媒体选择器
  /// （Android Photo Picker / iOS PHPickerViewController）。
  system,

  /// Use the plugin's customizable native sheet-style media picker on Android
  /// and iOS. Automatically falls back to the platform's standard file dialog
  /// on desktop (macOS, Windows, Linux) and Web.
  /// 在 Android 与 iOS 上使用插件内置的可自定义原生抽屉式媒体选择器。
  /// 在桌面端（macOS、Windows、Linux）与 Web 端会自动回退到各平台标准文件选择器。
  custom;

  /// Wire value sent across the platform channel.
  /// 通过平台通道传递的协议字符串值。
  String get wireName => name;
}
