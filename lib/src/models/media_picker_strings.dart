/// Localizable UI strings for [MediaPickerMode.custom].
/// [MediaPickerMode.custom] 自定义媒体选择器的可国际化文案配置。
///
/// Any omitted string falls back to a locale-aware default on the native side
/// (Simplified Chinese when the system locale is `zh`, English otherwise).
/// 未提供的文案将在原生端自动回退为与系统语言匹配的默认文案（中文系统显示简体中文，其余显示英文）。
class MediaPickerStrings {
  const MediaPickerStrings({
    this.galleryTitle,
    this.allMedia,
    this.allVideos,
    this.openInOtherApp,
    this.done,
    this.cancel,
    this.maxSelectionReached,
    this.limitedAccessHint,
    this.managePermission,
    this.permissionDeniedMessage,
    this.openSettings,
    this.emptyAlbum,
    this.cameraLabel,
  });

  /// Default title shown in the top album pill (e.g. "Gallery" / "相册").
  /// 顶部相册切换胶囊的默认标题（如“相册”/“Gallery”）。
  final String? galleryTitle;

  /// Label for the aggregated "All Media" virtual album.
  /// “所有媒体”聚合虚拟相册的显示名称。
  final String? allMedia;

  /// Label for the aggregated "All Videos" virtual album.
  /// “所有视频”聚合虚拟相册的显示名称。
  final String? allVideos;

  /// Label for the overflow menu action that falls back to the system picker.
  /// 右上角更多菜单中“使用其它应用打开…”选项的文案。
  final String? openInOtherApp;

  /// Label for the confirm button (e.g. "Done" / "发送").
  /// 底部确认按钮文案（如“发送”/“完成”/“Done”）。
  final String? done;

  /// Label for cancel actions.
  /// 取消操作文案。
  final String? cancel;

  /// Hint shown when the user tries to exceed `maxFiles`. Supports `{max}`
  /// placeholder replacement.
  /// 超过 `maxFiles` 上限时的提示文案，支持 `{max}` 占位符替换。
  final String? maxSelectionReached;

  /// Banner hint shown under Android 14+ / iOS 14+ limited photo access.
  /// Android 14+ / iOS 14+ 部分照片授权状态下的顶部提示文案。
  final String? limitedAccessHint;

  /// Action button label on the limited access banner.
  /// 部分照片授权横幅上的“管理/选择更多”按钮文案。
  final String? managePermission;

  /// Message shown when photo library permission is denied.
  /// 相册读取权限被拒绝时的提示文案。
  final String? permissionDeniedMessage;

  /// Button label to open OS app settings when permission is denied.
  /// 权限被拒绝时跳转系统设置的按钮文案。
  final String? openSettings;

  /// Placeholder label when the selected album contains no media items.
  /// 当前相册无媒体文件时的空态提示文案。
  final String? emptyAlbum;

  /// Accessibility / fallback label for the camera capture tile.
  /// 相机拍摄格的无障碍标签或未授权降级态文字。
  final String? cameraLabel;

  /// Serializes non-null string overrides into a platform-channel map.
  /// 将非空自定义文案序列化为平台通道参数 Map。
  Map<String, Object?> toMap() => <String, Object?>{
    if (galleryTitle != null) 'galleryTitle': galleryTitle,
    if (allMedia != null) 'allMedia': allMedia,
    if (allVideos != null) 'allVideos': allVideos,
    if (openInOtherApp != null) 'openInOtherApp': openInOtherApp,
    if (done != null) 'done': done,
    if (cancel != null) 'cancel': cancel,
    if (maxSelectionReached != null) 'maxSelectionReached': maxSelectionReached,
    if (limitedAccessHint != null) 'limitedAccessHint': limitedAccessHint,
    if (managePermission != null) 'managePermission': managePermission,
    if (permissionDeniedMessage != null)
      'permissionDeniedMessage': permissionDeniedMessage,
    if (openSettings != null) 'openSettings': openSettings,
    if (emptyAlbum != null) 'emptyAlbum': emptyAlbum,
    if (cameraLabel != null) 'cameraLabel': cameraLabel,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaPickerStrings &&
        other.galleryTitle == galleryTitle &&
        other.allMedia == allMedia &&
        other.allVideos == allVideos &&
        other.openInOtherApp == openInOtherApp &&
        other.done == done &&
        other.cancel == cancel &&
        other.maxSelectionReached == maxSelectionReached &&
        other.limitedAccessHint == limitedAccessHint &&
        other.managePermission == managePermission &&
        other.permissionDeniedMessage == permissionDeniedMessage &&
        other.openSettings == openSettings &&
        other.emptyAlbum == emptyAlbum &&
        other.cameraLabel == cameraLabel;
  }

  @override
  int get hashCode => Object.hash(
    galleryTitle,
    allMedia,
    allVideos,
    openInOtherApp,
    done,
    cancel,
    maxSelectionReached,
    limitedAccessHint,
    managePermission,
    permissionDeniedMessage,
    openSettings,
    emptyAlbum,
    cameraLabel,
  );
}
