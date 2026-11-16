#if os(macOS)
// 磁盘清理插件是 macOS 专属能力（AppKit / NSWorkspace / 全盘访问）。
// iOS 目标只需要本模块可编译、不参与插件装配，因此整模块在 iOS 上为空。
import SwiftUI

/// 项目清理底部操作栏
struct ProjectCleanerFooter: View {
    @ObservedObject var viewModel: ProjectCleanerViewModel
    @Binding var showCleanConfirmation: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(PluginDiskManagerLocalization.string("Selected for Cleanup"))
                    .font(.caption)
                    .foregroundColor(Color.adaptive(light: "6B6B7B", dark: "EBEBF5"))
                Text(viewModel.formatBytes(viewModel.totalSelectedSize))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.adaptive(light: "1C1C1E", dark: "FFFFFF"))
            }

            Spacer()

            Button(action: {
                showCleanConfirmation = true
            }, label: {
                Label(title: { Text(viewModel.isCleaning ? PluginDiskManagerLocalization.string("Cleaning...") : PluginDiskManagerLocalization.string("Clean Now")) }, icon: {
                    Image(systemName: "trash.fill")
                })
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            })
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "FF9F0A"))
            .disabled(viewModel.selectedItemIds.isEmpty || viewModel.isCleaning || viewModel.isScanning)
        }
        .padding(.horizontal)
    }
}

#endif
