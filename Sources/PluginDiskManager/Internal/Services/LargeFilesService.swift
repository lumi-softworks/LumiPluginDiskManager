#if os(macOS)
// 磁盘清理插件是 macOS 专属能力（AppKit / NSWorkspace / 全盘访问）。
// iOS 目标只需要本模块可编译、不参与插件装配，因此整模块在 iOS 上为空。
import AppKit
import Foundation

/// Large files service: scan, progress, delete, Finder reveal.
public final class LargeFilesService: @unchecked Sendable {
    public static let shared = LargeFilesService()

    private let coordinator = LargeFilesScanCoordinator()

    private init() {}

    public func scanLargeFiles(atPath path: String, forceRefresh: Bool = true) async throws -> [LargeFileEntry] {
        _ = forceRefresh
        return try await coordinator.scanLargeFiles(path: path)
    }

    public func progressStream() async -> AsyncStream<ScanProgress> {
        await coordinator.progressStream()
    }

    public func cancelScan() async {
        await coordinator.cancelCurrentScan()
    }

    public func deleteFile(atPath path: String) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }.value
        // 删除成功即意味着磁盘用量变化，通知仍在展示的容量文字与环形图刷新。
        await MainActor.run {
            NotificationCenter.default.post(name: .diskManagerDiskUsageDidChange, object: nil)
        }
    }

    @MainActor
    public func revealInFinder(path: String) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        #endif
    }
}

// MARK: - LargeFilesScanCoordinator

actor LargeFilesScanCoordinator {
    private var activeTask: Task<[LargeFileEntry], Error>?

    private var currentProgress: ScanProgress? {
        didSet {
            if let progress = currentProgress {
                for (_, cont) in progressContinuations {
                    cont.yield(progress)
                }
            }
        }
    }

    private var progressContinuations: [UUID: AsyncStream<ScanProgress>.Continuation] = [:]

    private let enumeratorFactory: @Sendable (URL, [URLResourceKey], FileManager.DirectoryEnumerationOptions) throws -> FileManager.DirectoryEnumerator

    init(
        enumeratorFactory: @escaping @Sendable (URL, [URLResourceKey], FileManager.DirectoryEnumerationOptions) throws -> FileManager.DirectoryEnumerator = {
            try ScanRootEnumerator.make(at: $0, includingPropertiesForKeys: $1, options: $2)
        }
    ) {
        self.enumeratorFactory = enumeratorFactory
    }

    func progressStream() -> AsyncStream<ScanProgress> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { await self.addContinuation(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    private func addContinuation(id: UUID, continuation: AsyncStream<ScanProgress>.Continuation) {
        progressContinuations[id] = continuation
        if let progress = currentProgress {
            continuation.yield(progress)
        }
    }

    private func removeContinuation(id: UUID) {
        progressContinuations[id] = nil
    }

    func scanLargeFiles(path: String) async throws -> [LargeFileEntry] {
        activeTask?.cancel()

        currentProgress = ScanProgress(
            path: path,
            currentPath: path,
            scannedFiles: 0,
            scannedDirectories: 0,
            scannedBytes: 0,
            startTime: Date()
        )

        let start = Date()
        // 遍历循环不能占住 actor：同步枚举期间 cancelCurrentScan 只能排在
        // 它后面，Stop 要等扫描自然结束才生效（#227）。遍历放在 nonisolated
        // 静态函数里跑，进度经 await 回传 actor 广播。
        let task = Task {
            try await Self.runEnumeration(
                path: path,
                start: start,
                enumeratorFactory: enumeratorFactory
            ) { progress in
                await self.applyProgress(progress)
            }
        }
        activeTask = task

        do {
            let result = try await task.value
            currentProgress = nil
            return result
        } catch {
            currentProgress = nil
            throw error
        }
    }

    func cancelCurrentScan() {
        activeTask?.cancel()
        activeTask = nil
        currentProgress = nil
    }

    /// 把遍历中间态落回 actor 并向进度订阅者广播。
    private func applyProgress(_ progress: ScanProgress) {
        currentProgress = progress
    }

    /// 纯遍历：nonisolated 异步函数运行在全局执行器上，不占用 actor；
    /// 取消由 cancelCurrentScan → activeTask.cancel() 传播进来，每个
    /// 枚举项后检查一次，命中即抛 CancellationError。
    private nonisolated static func runEnumeration(
        path: String,
        start: Date,
        enumeratorFactory: @Sendable (URL, [URLResourceKey], FileManager.DirectoryEnumerationOptions) throws -> FileManager.DirectoryEnumerator,
        applyProgress: @Sendable (ScanProgress) async -> Void
    ) async throws -> [LargeFileEntry] {
        let rootURL = URL(fileURLWithPath: path)

        let enumerator = try enumeratorFactory(
            rootURL,
            [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey],
            [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var top = MaxHeap<LargeFileEntry>(capacity: 100)
        var lastEmitAt = Date.distantPast
        var scannedFiles = 0
        var scannedDirectories = 0
        var scannedBytes: Int64 = 0
        var currentPath = path

        func snapshot() -> ScanProgress {
            ScanProgress(
                path: path,
                currentPath: currentPath,
                scannedFiles: scannedFiles,
                scannedDirectories: scannedDirectories,
                scannedBytes: scannedBytes,
                startTime: start
            )
        }

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            currentPath = url.path

            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]) else {
                continue
            }

            let isDirectory = values.isDirectory ?? false
            let isPackage = values.isPackage ?? false
            if isDirectory, !isPackage {
                scannedDirectories += 1
            } else {
                let size = Int64(values.fileSize ?? 0)
                scannedFiles += 1
                scannedBytes += size

                if size > 50 * 1024 * 1024 {
                    let entry = LargeFileEntry(
                        id: UUID().uuidString,
                        name: url.lastPathComponent,
                        path: url.path,
                        size: size,
                        modificationDate: values.contentModificationDate ?? Date(),
                        fileType: .from(extension: url.pathExtension)
                    )
                    top.insert(entry)
                }
            }

            let now = Date()
            if now.timeIntervalSince(lastEmitAt) >= 0.5 {
                lastEmitAt = now
                await applyProgress(snapshot())
            }
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        await applyProgress(snapshot())
        return top.elements
    }
}

#endif
