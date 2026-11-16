#if os(macOS)
// 磁盘清理插件是 macOS 专属能力（AppKit / NSWorkspace / 全盘访问）。
// iOS 目标只需要本模块可编译、不参与插件装配，因此整模块在 iOS 上为空。
import Foundation

enum PluginDiskManagerLocalization {
    static let table = "Localizable"
    static let bundle = Bundle.module

    static func string(_ key: String, locale: Locale = .current) -> String {
        pluginLocalization.string(key, locale: locale)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}

#endif
