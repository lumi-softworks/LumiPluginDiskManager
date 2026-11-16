#if os(macOS)
// 磁盘清理插件是 macOS 专属能力（AppKit / NSWorkspace / 全盘访问）。
// iOS 目标只需要本模块可编译、不参与插件装配，因此整模块在 iOS 上为空。
import Foundation

extension FileManager {
    /// 用户主目录。整模块在 iOS 上为空，所以这里只保留 macOS 的实现。
    var portableHomeDirectory: URL {
        homeDirectoryForCurrentUser
    }
}

#endif
