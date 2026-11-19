import UIKit

/// Resolved visual theme for the iOS custom media picker.
/// iOS 自定义媒体选择器的已解析视觉主题。
struct CustomMediaPickerTheme {
    let isDark: Bool
    let backgroundColor: UIColor
    let surfaceColor: UIColor
    let primaryColor: UIColor
    let onPrimaryColor: UIColor
    let textColor: UIColor
    let secondaryTextColor: UIColor
    let iconColor: UIColor
    let unselectedBadgeBorderColor: UIColor
    let unselectedBadgeFillColor: UIColor
    let scrimColor: UIColor
    let handleColor: UIColor
    let dateBubbleBackgroundColor: UIColor
    let dateBubbleTextColor: UIColor
    let sheetCornerRadius: CGFloat
    let gridSpacing: CGFloat

    /// Parses a Flutter theme dictionary and fills omitted fields from the
    /// built-in light or dark default palette.
    /// 解析来自 Flutter 的主题字典，并为未传字段填充内置浅色或深色默认配色。
    static func from(dict: [String: Any]?) -> CustomMediaPickerTheme {
        let systemDark = UITraitCollection.current.userInterfaceStyle == .dark
        let isDark: Bool
        switch dict?["brightness"] as? String {
        case "dark": isDark = true
        case "light": isDark = false
        default: isDark = systemDark
        }

        func color(_ key: String, light: UInt32, dark: UInt32) -> UIColor {
            if let num = dict?[key] as? NSNumber {
                return UIColor(argb32: num.uint32Value)
            }
            return UIColor(argb32: isDark ? dark : light)
        }

        func cgFloat(_ key: String, defaultVal: CGFloat) -> CGFloat {
            if let num = dict?[key] as? NSNumber {
                return max(0, CGFloat(num.doubleValue))
            }
            return defaultVal
        }

        return CustomMediaPickerTheme(
            isDark: isDark,
            backgroundColor: color("backgroundColor", light: 0xFFFF_FFFF, dark: 0xFF1C_1C1E),
            surfaceColor: color("surfaceColor", light: 0xF2F3_F4F6, dark: 0xF22C_2C2E),
            primaryColor: color("primaryColor", light: 0xFF2A_ABEE, dark: 0xFF2A_ABEE),
            onPrimaryColor: color("onPrimaryColor", light: 0xFFFF_FFFF, dark: 0xFFFF_FFFF),
            textColor: color("textColor", light: 0xFF11_1111, dark: 0xFFF5_F5F7),
            secondaryTextColor: color("secondaryTextColor", light: 0xFF7A_8089, dark: 0xFF98_989F),
            iconColor: color("iconColor", light: 0xFF1A_1A1A, dark: 0xFFF5_F5F7),
            unselectedBadgeBorderColor: color("unselectedBadgeBorderColor", light: 0xFFFF_FFFF, dark: 0xFFFF_FFFF),
            unselectedBadgeFillColor: color("unselectedBadgeFillColor", light: 0x4000_0000, dark: 0x4000_0000),
            scrimColor: color("scrimColor", light: 0x6600_0000, dark: 0x8000_0000),
            handleColor: color("handleColor", light: 0x408E_8E93, dark: 0x55AE_AEB2),
            dateBubbleBackgroundColor: color("dateBubbleBackgroundColor", light: 0xF2FF_FFFF, dark: 0xF22C_2C2E),
            dateBubbleTextColor: color("dateBubbleTextColor", light: 0xFF11_1111, dark: 0xFFF5_F5F7),
            sheetCornerRadius: cgFloat("sheetCornerRadius", defaultVal: 20),
            gridSpacing: cgFloat("gridSpacing", defaultVal: 2)
        )
    }
}

/// Resolved localized strings for the iOS custom media picker.
/// iOS 自定义媒体选择器的已解析本地化文案。
struct CustomMediaPickerStrings {
    let galleryTitle: String
    let allMedia: String
    let allVideos: String
    let openInOtherApp: String
    let done: String
    let cancel: String
    let maxSelectionReached: String
    let limitedAccessHint: String
    let managePermission: String
    let permissionDeniedMessage: String
    let openSettings: String
    let emptyAlbum: String
    let cameraLabel: String

    /// Parses string overrides from Flutter and falls back to Simplified Chinese
    /// or English defaults based on the system preferred language.
    /// 解析来自 Flutter 的文案覆盖，并根据系统首选语言回退为简体中文或英文默认文案。
    static func from(dict: [String: Any]?) -> CustomMediaPickerStrings {
        let isZh = (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("zh")

        func str(_ key: String, zh: String, en: String) -> String {
            if let value = dict?[key] as? String, !value.isEmpty {
                return value
            }
            return isZh ? zh : en
        }

        return CustomMediaPickerStrings(
            galleryTitle: str("galleryTitle", zh: "相册", en: "Gallery"),
            allMedia: str("allMedia", zh: "所有媒体", en: "All Media"),
            allVideos: str("allVideos", zh: "所有视频", en: "All Videos"),
            openInOtherApp: str("openInOtherApp", zh: "使用其它应用打开…", en: "Open in other app…"),
            done: str("done", zh: "完成", en: "Done"),
            cancel: str("cancel", zh: "取消", en: "Cancel"),
            maxSelectionReached: str(
                "maxSelectionReached",
                zh: "最多只能选择 {max} 个文件",
                en: "You can select up to {max} items"
            ),
            limitedAccessHint: str(
                "limitedAccessHint",
                zh: "已授权访问部分照片和视频",
                en: "Limited access to selected photos and videos"
            ),
            managePermission: str("managePermission", zh: "管理", en: "Manage"),
            permissionDeniedMessage: str(
                "permissionDeniedMessage",
                zh: "需要相册访问权限以浏览图片和视频",
                en: "Photo library permission is required to browse media"
            ),
            openSettings: str("openSettings", zh: "前往设置", en: "Open Settings"),
            emptyAlbum: str("emptyAlbum", zh: "暂无媒体文件", en: "No media found"),
            cameraLabel: str("cameraLabel", zh: "拍摄", en: "Camera")
        )
    }
}

/// Complete runtime configuration for launching the iOS custom media picker.
/// 启动 iOS 自定义媒体选择器的完整运行时配置。
struct CustomMediaPickerConfig {
    let mediaType: String // "image" | "video" | "media"
    let multiple: Bool
    let maxFiles: Int?
    let withData: Bool
    let showCameraTile: Bool
    let allowOpenInOtherApp: Bool
    let crossAxisCount: Int
    let initialExpanded: Bool
    let enablePreview: Bool
    let theme: CustomMediaPickerTheme
    let strings: CustomMediaPickerStrings

    static func from(
        mediaType: String,
        multiple: Bool,
        maxFiles: Int?,
        withData: Bool,
        optionsDict: [String: Any]?
    ) -> CustomMediaPickerConfig {
        let themeDict = optionsDict?["theme"] as? [String: Any]
        let stringsDict = optionsDict?["strings"] as? [String: Any]
        let rawCols = (optionsDict?["crossAxisCount"] as? NSNumber)?.intValue ?? 3
        return CustomMediaPickerConfig(
            mediaType: mediaType,
            multiple: multiple,
            maxFiles: maxFiles,
            withData: withData,
            showCameraTile: (optionsDict?["showCameraTile"] as? Bool) ?? true,
            allowOpenInOtherApp: (optionsDict?["allowOpenInOtherApp"] as? Bool) ?? true,
            crossAxisCount: min(max(rawCols, 2), 6),
            initialExpanded: (optionsDict?["initialExpanded"] as? Bool) ?? false,
            enablePreview: (optionsDict?["enablePreview"] as? Bool) ?? true,
            theme: CustomMediaPickerTheme.from(dict: themeDict),
            strings: CustomMediaPickerStrings.from(dict: stringsDict)
        )
    }
}

extension UIColor {
    /// Initializes a [UIColor] from a Flutter ARGB 32-bit unsigned integer.
    /// 根据 Flutter 传递的 ARGB32 无符号整数创建 [UIColor]。
    convenience init(argb32: UInt32) {
        let a = CGFloat((argb32 >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb32 >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb32 >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb32 & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
