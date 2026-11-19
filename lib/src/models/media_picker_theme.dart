import 'dart:ui';

/// Visual styling configuration for [MediaPickerMode.custom].
/// [MediaPickerMode.custom] 自定义媒体选择器的视觉主题配置。
///
/// Every property is optional; omitted fields fall back to built-in light or
/// dark palettes derived from [brightness] (or the system appearance when
/// [brightness] is `null`).
/// 所有字段均为可选；未指定的属性将根据 [brightness]（为空时跟随系统深浅色模式）
/// 自动使用内置的浅色或深色默认配色。
class MediaPickerTheme {
  const MediaPickerTheme({
    this.brightness,
    this.backgroundColor,
    this.surfaceColor,
    this.primaryColor,
    this.onPrimaryColor,
    this.textColor,
    this.secondaryTextColor,
    this.iconColor,
    this.unselectedBadgeBorderColor,
    this.unselectedBadgeFillColor,
    this.scrimColor,
    this.handleColor,
    this.dateBubbleBackgroundColor,
    this.dateBubbleTextColor,
    this.sheetCornerRadius,
    this.gridSpacing,
  });

  /// Optional brightness override (`light` or `dark`). Follows system theme
  /// when `null`.
  /// 可选的深浅色模式覆盖；为 `null` 时跟随系统外观。
  final Brightness? brightness;

  /// Main sheet and media grid background color.
  /// 选择器面板与媒体网格的主背景色。
  final Color? backgroundColor;

  /// Background color for floating top-bar pills, album popover, and menu cards.
  /// 顶部悬浮胶囊按钮、相册下拉浮窗与更多操作菜单卡片的背景色。
  final Color? surfaceColor;

  /// Accent color for selected badges, confirm buttons, and active indicators.
  /// 选中角标、底部确认按钮及高亮状态的主色调。
  final Color? primaryColor;

  /// Foreground color drawn on top of [primaryColor] (badge index, checkmark,
  /// button text).
  /// 绘制在 [primaryColor] 之上的前景色（选中序号、勾选图标、按钮文字）。
  final Color? onPrimaryColor;

  /// Primary text color for titles, album names, and menu items.
  /// 标题、相册名称与菜单项的主文字颜色。
  final Color? textColor;

  /// Secondary text color for album item counts and subtle labels.
  /// 相册数量与辅助提示文案的次级文字颜色。
  final Color? secondaryTextColor;

  /// Tint color for toolbar and menu icons.
  /// 顶部工具栏与菜单图标的着色。
  final Color? iconColor;

  /// Stroke color for unselected circular selection badges.
  /// 未选中态圆形选择框的边框颜色。
  final Color? unselectedBadgeBorderColor;

  /// Translucent fill color inside unselected circular selection badges.
  /// 未选中态圆形选择框内部的半透明填充色。
  final Color? unselectedBadgeFillColor;

  /// Dimmed backdrop color behind the half-expanded sheet.
  /// 半屏抽屉背后的遮罩层颜色。
  final Color? scrimColor;

  /// Color of the top drag-handle pill indicator.
  /// 面板顶部居中拖拽指示条的颜色。
  final Color? handleColor;

  /// Background color of the floating date indicator while fast-scrolling.
  /// 右侧快速滚动时日期浮窗的背景色。
  final Color? dateBubbleBackgroundColor;

  /// Text color of the floating date indicator while fast-scrolling.
  /// 右侧快速滚动时日期浮窗的文字颜色。
  final Color? dateBubbleTextColor;

  /// Top corner radius (in logical pixels) of the bottom sheet container.
  /// 底部抽屉面板顶部的圆角半径（逻辑像素）。
  final double? sheetCornerRadius;

  /// Spacing (in logical pixels) between grid cells.
  /// 媒体网格单元格之间的间距（逻辑像素）。
  final double? gridSpacing;

  /// Creates a copy with the specified fields replaced.
  /// 复制当前主题并替换指定字段。
  MediaPickerTheme copyWith({
    Brightness? brightness,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? primaryColor,
    Color? onPrimaryColor,
    Color? textColor,
    Color? secondaryTextColor,
    Color? iconColor,
    Color? unselectedBadgeBorderColor,
    Color? unselectedBadgeFillColor,
    Color? scrimColor,
    Color? handleColor,
    Color? dateBubbleBackgroundColor,
    Color? dateBubbleTextColor,
    double? sheetCornerRadius,
    double? gridSpacing,
  }) {
    return MediaPickerTheme(
      brightness: brightness ?? this.brightness,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      primaryColor: primaryColor ?? this.primaryColor,
      onPrimaryColor: onPrimaryColor ?? this.onPrimaryColor,
      textColor: textColor ?? this.textColor,
      secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
      iconColor: iconColor ?? this.iconColor,
      unselectedBadgeBorderColor:
          unselectedBadgeBorderColor ?? this.unselectedBadgeBorderColor,
      unselectedBadgeFillColor:
          unselectedBadgeFillColor ?? this.unselectedBadgeFillColor,
      scrimColor: scrimColor ?? this.scrimColor,
      handleColor: handleColor ?? this.handleColor,
      dateBubbleBackgroundColor:
          dateBubbleBackgroundColor ?? this.dateBubbleBackgroundColor,
      dateBubbleTextColor: dateBubbleTextColor ?? this.dateBubbleTextColor,
      sheetCornerRadius: sheetCornerRadius ?? this.sheetCornerRadius,
      gridSpacing: gridSpacing ?? this.gridSpacing,
    );
  }

  /// Serializes non-null styling properties into a platform-channel map.
  /// 将非空主题属性序列化为平台通道参数 Map（颜色统一编码为 ARGB32 整数）。
  Map<String, Object?> toMap() => <String, Object?>{
    if (brightness != null) 'brightness': brightness!.name,
    if (backgroundColor != null) 'backgroundColor': backgroundColor!.toARGB32(),
    if (surfaceColor != null) 'surfaceColor': surfaceColor!.toARGB32(),
    if (primaryColor != null) 'primaryColor': primaryColor!.toARGB32(),
    if (onPrimaryColor != null) 'onPrimaryColor': onPrimaryColor!.toARGB32(),
    if (textColor != null) 'textColor': textColor!.toARGB32(),
    if (secondaryTextColor != null)
      'secondaryTextColor': secondaryTextColor!.toARGB32(),
    if (iconColor != null) 'iconColor': iconColor!.toARGB32(),
    if (unselectedBadgeBorderColor != null)
      'unselectedBadgeBorderColor': unselectedBadgeBorderColor!.toARGB32(),
    if (unselectedBadgeFillColor != null)
      'unselectedBadgeFillColor': unselectedBadgeFillColor!.toARGB32(),
    if (scrimColor != null) 'scrimColor': scrimColor!.toARGB32(),
    if (handleColor != null) 'handleColor': handleColor!.toARGB32(),
    if (dateBubbleBackgroundColor != null)
      'dateBubbleBackgroundColor': dateBubbleBackgroundColor!.toARGB32(),
    if (dateBubbleTextColor != null)
      'dateBubbleTextColor': dateBubbleTextColor!.toARGB32(),
    if (sheetCornerRadius != null) 'sheetCornerRadius': sheetCornerRadius,
    if (gridSpacing != null) 'gridSpacing': gridSpacing,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaPickerTheme &&
        other.brightness == brightness &&
        other.backgroundColor == backgroundColor &&
        other.surfaceColor == surfaceColor &&
        other.primaryColor == primaryColor &&
        other.onPrimaryColor == onPrimaryColor &&
        other.textColor == textColor &&
        other.secondaryTextColor == secondaryTextColor &&
        other.iconColor == iconColor &&
        other.unselectedBadgeBorderColor == unselectedBadgeBorderColor &&
        other.unselectedBadgeFillColor == unselectedBadgeFillColor &&
        other.scrimColor == scrimColor &&
        other.handleColor == handleColor &&
        other.dateBubbleBackgroundColor == dateBubbleBackgroundColor &&
        other.dateBubbleTextColor == dateBubbleTextColor &&
        other.sheetCornerRadius == sheetCornerRadius &&
        other.gridSpacing == gridSpacing;
  }

  @override
  int get hashCode => Object.hash(
    brightness,
    backgroundColor,
    surfaceColor,
    primaryColor,
    onPrimaryColor,
    textColor,
    secondaryTextColor,
    iconColor,
    unselectedBadgeBorderColor,
    unselectedBadgeFillColor,
    scrimColor,
    handleColor,
    dateBubbleBackgroundColor,
    dateBubbleTextColor,
    sheetCornerRadius,
    gridSpacing,
  );
}
