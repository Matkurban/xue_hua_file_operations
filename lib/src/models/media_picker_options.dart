import 'media_picker_mode.dart';
import 'media_picker_strings.dart';
import 'media_picker_theme.dart';

/// Configuration options for mobile media picking in `pickFile` / `pickFiles`.
/// 移动端 `pickFile` / `pickFiles` 媒体选择器的配置选项。
///
/// Only applies when picking [FileType.image], [FileType.video], or
/// [FileType.media] on Android and iOS without custom MIME/extension filters.
/// Other platforms and file types ignore these options and use their standard
/// native pickers.
/// 仅在 Android 与 iOS 端选择 [FileType.image]、[FileType.video] 或 [FileType.media]
/// 且未指定自定义 MIME/扩展名过滤时生效；其他平台或文件类型会自动回退到标准选择器。
class MediaPickerOptions {
  const MediaPickerOptions({
    this.mode = MediaPickerMode.system,
    this.theme,
    this.strings,
    this.showCameraTile = true,
    this.allowOpenInOtherApp = true,
    this.crossAxisCount = 3,
    this.initialExpanded = false,
    this.enablePreview = true,
  });

  /// Presentation mode ([MediaPickerMode.system] or [MediaPickerMode.custom]).
  /// 选择器展示模式（[MediaPickerMode.system] 系统原生，或 [MediaPickerMode.custom] 自定义抽屉式）。
  final MediaPickerMode mode;

  /// Optional custom color and layout theme for [MediaPickerMode.custom].
  /// [MediaPickerMode.custom] 下的可选颜色与布局主题配置。
  final MediaPickerTheme? theme;

  /// Optional localized UI string overrides for [MediaPickerMode.custom].
  /// [MediaPickerMode.custom] 下的可选多语言文案覆盖。
  final MediaPickerStrings? strings;

  /// Whether to show the 2-row-tall live camera preview tile in the top-left
  /// corner of the "All Media" grid. Gracefully degrades to a static camera
  /// button when camera permission has not been granted.
  /// 是否在“所有媒体”网格左上角显示跨 2 行的实时相机预览格；
  /// 未获得相机权限时自动降级为静态拍照入口按钮。
  final bool showCameraTile;

  /// Whether to show the "Open in other app..." option in the top-right
  /// overflow menu, allowing users to fall back to the system picker.
  /// 是否在右上角更多菜单中显示“使用其它应用打开…”以支持切换到系统选择器。
  final bool allowOpenInOtherApp;

  /// Number of columns in the media grid (valid range: 2..6, default: 3).
  /// 媒体网格列数（有效范围 2..6，默认 3 列）。
  final int crossAxisCount;

  /// Whether to open directly in fullscreen instead of a half-height
  /// expandable bottom sheet.
  /// 是否默认直接全屏打开（`false` 表示默认半屏抽屉，可上拉展开至全屏）。
  final bool initialExpanded;

  /// Whether tapping a media thumbnail opens the full-screen preview page
  /// (where users can swipe, inspect videos/images, and toggle selection).
  /// 点击媒体缩略图主体时是否进入原生全屏预览页（支持滑动浏览、播放视频及勾选切换）。
  final bool enablePreview;

  /// Serializes all options into a platform-channel map.
  /// 将完整配置序列化为平台通道参数 Map。
  Map<String, Object?> toMap() => <String, Object?>{
    'mode': mode.wireName,
    if (theme != null) 'theme': theme!.toMap(),
    if (strings != null) 'strings': strings!.toMap(),
    'showCameraTile': showCameraTile,
    'allowOpenInOtherApp': allowOpenInOtherApp,
    'crossAxisCount': crossAxisCount,
    'initialExpanded': initialExpanded,
    'enablePreview': enablePreview,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaPickerOptions &&
        other.mode == mode &&
        other.theme == theme &&
        other.strings == strings &&
        other.showCameraTile == showCameraTile &&
        other.allowOpenInOtherApp == allowOpenInOtherApp &&
        other.crossAxisCount == crossAxisCount &&
        other.initialExpanded == initialExpanded &&
        other.enablePreview == enablePreview;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    theme,
    strings,
    showCameraTile,
    allowOpenInOtherApp,
    crossAxisCount,
    initialExpanded,
    enablePreview,
  );
}
