import UIKit

/// 帖子正文阅读设置（字体大小 / 行距），持久化到 UserDefaults。
///
/// ContentFormatter.default 会实时读取这里的值，所以修改后只需
/// 调用 `notifyChange()` 清掉格式化缓存并广播通知，正在显示的帖子详情页
/// 监听该通知即可刷新。
final class ReadingSettings {

    static let shared = ReadingSettings()

    /// 设置变更通知。ThreadDetailViewController 监听后清高度缓存并 reload。
    static let didChangeNotification = Notification.Name("ReadingSettingsDidChange")

    // 取值范围与默认值（默认值与 ContentFormatter.Style 原本的硬编码保持一致）
    static let minFontSize: CGFloat = 12
    static let maxFontSize: CGFloat = 24
    static let defaultFontSize: CGFloat = 15

    static let minLineSpacing: CGFloat = 0
    static let maxLineSpacing: CGFloat = 16
    static let defaultLineSpacing: CGFloat = 6

    private let defaults = UserDefaults.standard
    private let fontSizeKey = "reading_font_size"
    private let lineSpacingKey = "reading_line_spacing"

    private init() {}

    var fontSize: CGFloat {
        get {
            guard let v = defaults.object(forKey: fontSizeKey) as? Double else {
                return Self.defaultFontSize
            }
            return CGFloat(v)
        }
        set {
            let clamped = min(max(newValue, Self.minFontSize), Self.maxFontSize)
            defaults.set(Double(clamped), forKey: fontSizeKey)
        }
    }

    var lineSpacing: CGFloat {
        get {
            guard let v = defaults.object(forKey: lineSpacingKey) as? Double else {
                return Self.defaultLineSpacing
            }
            return CGFloat(v)
        }
        set {
            let clamped = min(max(newValue, Self.minLineSpacing), Self.maxLineSpacing)
            defaults.set(Double(clamped), forKey: lineSpacingKey)
        }
    }

    /// 恢复默认设置
    func reset() {
        defaults.removeObject(forKey: fontSizeKey)
        defaults.removeObject(forKey: lineSpacingKey)
    }

    /// 设置变更后调用：清空内容格式化缓存并广播通知。
    /// 缓存以「内容」为 key（不含样式），所以样式一变必须清缓存才会生效。
    func notifyChange() {
        ContentFormatter.clearFormatCache()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
