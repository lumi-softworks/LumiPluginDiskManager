import Foundation
import Testing
@testable import PluginDiskManager

/// #227：同步目录枚举占住 actor 时，Stop 的 cancelCurrentScan 只能排在
/// 它后面，扫描要等自然结束才能停。修复后遍历在 nonisolated 上下文运行，
/// cancelCurrentScan 随时可入并立即取消枚举任务。
struct LargeFilesScanCancellationTests {
    /// 每次取下一项都同步阻塞 10ms 的假枚举器：让一次扫描确定性地耗时
    /// 数秒，复现「枚举占住 actor」的旧症状。
    private final class SlowEnumerator: FileManager.DirectoryEnumerator {
        private let urls: [URL]
        private let itemDelay: TimeInterval
        private var index = 0

        init(urls: [URL], itemDelay: TimeInterval) {
            self.urls = urls
            self.itemDelay = itemDelay
        }

        override func nextObject() -> Any? {
            Thread.sleep(forTimeInterval: itemDelay)
            guard index < urls.count else { return nil }
            defer { index += 1 }
            return urls[index]
        }
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test("枚举进行中 cancelCurrentScan 立即生效并终止遍历")
    func cancelInterruptsEnumerationPromptly() async throws {
        final class EventBox: @unchecked Sendable {
            var events: [Date] = []
            var sawFiles = false
        }
        let box = EventBox()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-scan-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let sampleFile = tempDir.appendingPathComponent("sample.txt")
        try Data("sample".utf8).write(to: sampleFile)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let coordinator = LargeFilesScanCoordinator(
            enumeratorFactory: { _, _, _ in
                SlowEnumerator(urls: Array(repeating: sampleFile, count: 300), itemDelay: 0.01)
            }
        )

        let stream = await coordinator.progressStream()
        // 单一消费者：记录每次进度广播，并标记「已看到文件进度」作为
        // 枚举进行中的就绪信号。
        let consumer = Task {
            for await progress in stream {
                box.events.append(Date())
                if progress.scannedFiles > 0 {
                    box.sawFiles = true
                }
            }
        }

        async let result = coordinator.scanLargeFiles(path: tempDir.path)
        await waitUntil { box.sawFiles }

        let cancelStart = Date()
        await coordinator.cancelCurrentScan()
        let cancelDuration = Date().timeIntervalSince(cancelStart)

        // 修复前：cancelCurrentScan 排在同步枚举后面，要等遍历自然结束
        // （剩余约 2.5s）才能返回；修复后毫秒级。
        #expect(cancelDuration < 1.0)

        do {
            _ = try await result
            Issue.record("cancelled scan should not return results")
        } catch {
            #expect(error is CancellationError)
        }

        // 取消之后不得再有进度广播（旧实现会在取消后继续广播直至遍历结束）。
        let eventCountAtCancel = box.events.count
        try? await Task.sleep(nanoseconds: 600_000_000)
        #expect(box.events.count == eventCountAtCancel)

        consumer.cancel()
    }
}
