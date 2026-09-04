#if DEBUG
import Foundation

/// 假剪贴板：只记最后写入的明文，不碰系统 Pasteboard。
actor FakeClipboard: ClipboardServing {
    var journal = FakeJournal()
    private(set) var lastWritten: String?

    func write(_ secret: String, expiresAfter: TimeInterval, localOnly: Bool) async throws {
        _ = expiresAfter
        _ = localOnly
        try journal.record("write")
        lastWritten = secret
    }

    func clearIfStillOurs() async {
        journal.recordNonThrowing("clearIfStillOurs")
        lastWritten = nil
    }
}
#endif
