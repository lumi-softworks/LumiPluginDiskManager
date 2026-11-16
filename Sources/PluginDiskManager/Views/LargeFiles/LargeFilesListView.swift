#if os(macOS)
// 磁盘清理插件是 macOS 专属能力（AppKit / NSWorkspace / 全盘访问）。
// iOS 目标只需要本模块可编译、不参与插件装配，因此整模块在 iOS 上为空。
import SwiftUI

/// 大文件列表视图
struct LargeFilesListView: View {
    @ObservedObject var viewModel: LargeFilesViewModel

    var body: some View {
        VStack(spacing: 16) {
            // 扫描控制区域
            if viewModel.largeFiles.isEmpty == false {
                LargeFilesScanControlBar(viewModel: viewModel)
            }

            VStack {
                // 扫描进度
                if viewModel.isScanning {
                    LargeFilesScanProgressView(viewModel: viewModel)
                }

                // 错误消息
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(Color(hex: "FF453A"))
                        .padding()
                }

                // 文件列表
                if viewModel.largeFiles.isEmpty && !viewModel.isScanning {
                    EmptyLargeFilesView(viewModel: viewModel)
                } else if !viewModel.isScanning {
                    List {
                        ForEach(viewModel.largeFiles) { file in
                            LargeFileRow(item: file, viewModel: viewModel)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - 预览

#endif
