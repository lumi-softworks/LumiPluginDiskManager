#if os(macOS)
// 磁盘清理插件是 macOS 专属能力（AppKit / NSWorkspace / 全盘访问）。
// iOS 目标只需要本模块可编译、不参与插件装配，因此整模块在 iOS 上为空。
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct XcodeCleanerView: View {
    @ObservedObject var viewModel: XcodeCleanerViewModel
    @State private var showCleanConfirmation = false

    init(viewModel: XcodeCleanerViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 16) {
            // 扫描控制区域
            if viewModel.itemsByCategory.isEmpty == false && viewModel.isScanning == false {
                XcodeScanControlBar(viewModel: viewModel)
            }

            VStack {
                // 扫描进度
                if viewModel.isScanning {
                    XcodeScanProgressView(viewModel: viewModel)
                }

                // 内容列表
                if viewModel.itemsByCategory.isEmpty && !viewModel.isScanning {
                    XcodeEmptyStateView(viewModel: viewModel)
                } else if !viewModel.isScanning {
                    List {
                        ForEach(XcodeCleanCategory.allCases) { category in
                            if let items = viewModel.itemsByCategory[category], !items.isEmpty {
                                XcodeCategorySection(category: category, items: items, viewModel: viewModel)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxHeight: .infinity)

            // 底部操作栏
            if !viewModel.isScanning {
                XcodeCleanerFooter(viewModel: viewModel, showCleanConfirmation: $showCleanConfirmation)
            }
        }
        .onAppear {
            Task { await viewModel.scanAllIfNeeded() }
        }
        .alert(Text(PluginDiskManagerLocalization.string("Confirm Cleanup")), isPresented: $showCleanConfirmation) {
            Button(role: .cancel) {} label: {
                Text(PluginDiskManagerLocalization.string("Cancel"))
            }
            Button(role: .destructive) {
                Task { await viewModel.cleanSelected() }
            } label: {
                Text(PluginDiskManagerLocalization.string("Clean"))
            }
        } message: {
            let template = PluginDiskManagerLocalization.string("Are you sure you want to clean %@ of Xcode cache? This action cannot be undone.")
            Text(String(format: template, viewModel.formatBytes(viewModel.selectedSize)))
        }
    }
}

#endif
