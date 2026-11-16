#if os(macOS)
// 磁盘清理插件是 macOS 专属能力（AppKit / NSWorkspace / 全盘访问）。
// iOS 目标只需要本模块可编译、不参与插件装配，因此整模块在 iOS 上为空。
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Xcode 清理底部操作栏
struct XcodeCleanerFooter: View {
    @ObservedObject var viewModel: XcodeCleanerViewModel
    @Binding var showCleanConfirmation: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(PluginDiskManagerLocalization.string("Selected:"))\(viewModel.formatBytes(viewModel.selectedSize))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.adaptive(light: "1C1C1E", dark: "FFFFFF"))
                Text("\(PluginDiskManagerLocalization.string("Total:"))\(viewModel.formatBytes(viewModel.totalSize))")
                    .font(.caption)
                    .foregroundColor(Color.adaptive(light: "6B6B7B", dark: "EBEBF5"))
            }

            Spacer()

            if let error = viewModel.errorMessage {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(error)
                        .foregroundColor(Color(hex: "FF453A"))
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                    if viewModel.isPermissionError {
                        Button(action: openFullDiskAccessSettings) {
                            Text(PluginDiskManagerLocalization.string("Open System Settings"))
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }

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
            .disabled(viewModel.selectedSize == 0 || viewModel.isCleaning)
        }
        .padding(.horizontal)
    }

    private func openFullDiskAccessSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

#endif
