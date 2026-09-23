#if DEBUG
import Foundation

/// 假剪贴板：只记最后写入的明文，不碰系统 Pasteboard。
actor FakeClipboard: ClipboardServing {
    var journal = FakeJournal()
    private(set) var lastWritten: String?
    private(set) var lastExpiresAfter: TimeInterval?
    private(set) var lastLocalOnly: Bool?

    func write(
        _ secret: String,
        expiresAfter: TimeInterval?,
        localOnly: Bool,
        committing: @escaping ClipboardCommit
    ) async throws {
        try committing {
            try journal.record("write")
            lastWritten = secret
            lastExpiresAfter = expiresAfter
            lastLocalOnly = localOnly
        }
    }

    func clearIfStillOurs() async {
        journal.recordNonThrowing("clearIfStillOurs")
        lastWritten = nil
    }
}
#endif
