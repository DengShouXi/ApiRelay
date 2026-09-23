import Foundation

/// Final synchronous authorization seam around one concrete pasteboard write.
/// The closure must not suspend while `operation` is running.
typealias ClipboardCommit = @Sendable (_ operation: () throws -> Void) throws -> Void

protocol ClipboardServing: Actor {
    /// `expiresAfter == nil`：不排程、不写系统过期（用户关掉了自动清除）。
    func write(
        _ secret: String,
        expiresAfter: TimeInterval?,
        localOnly: Bool,
        committing: @escaping ClipboardCommit
    ) async throws
    /// 仅当剪贴板仍是本产品写入的那一份时才清除。
    func clearIfStillOurs() async
}

extension ClipboardServing {
    func write(_ secret: String, expiresAfter: TimeInterval?, localOnly: Bool) async throws {
        try await write(
            secret,
            expiresAfter: expiresAfter,
            localOnly: localOnly,
            committing: { operation in try operation() }
        )
    }
}

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

actor SecureClipboard: ClipboardServing {
    enum PasteboardWriteResult: Sendable, Equatable {
        case success(changeCount: Int)
        /// `nil` means the failure happened before the pasteboard was touched.
        /// A count means the write may already have exposed the secret and must
        /// be rolled back if that exact pasteboard generation is still current.
        case failure(lastAttemptChangeCount: Int?)
    }

    typealias PasteboardWriter = @MainActor @Sendable (String, Date?, Bool) -> PasteboardWriteResult
    /// Ownership comparison and deletion must remain one synchronous MainActor
    /// operation. Splitting them across two awaits lets a later pasteboard write
    /// land after the comparison and then be deleted by the stale cleanup.
    typealias PasteboardCompareAndClear = @MainActor @Sendable (Int) -> Bool
    /// Failed read-back can happen after the OS accepted a write. In that case
    /// value comparison is unavailable by definition, so rollback is owned by
    /// the exact `changeCount` produced by the last attempt.
    typealias PasteboardRollback = @MainActor @Sendable (Int) -> Bool

    private var lastWrittenChangeCount: Int?
    /// 每次成功写入都换代。旧计时任务即使已经醒来并排进 actor，也不得清除后一次复制。
    private var writeGeneration: UInt64 = 0
    private var clearTask: Task<Void, Never>?
    private let pasteboardWriter: PasteboardWriter
    private let pasteboardCompareAndClear: PasteboardCompareAndClear
    private let pasteboardRollback: PasteboardRollback
    private let mutationGate: StorageMutationGate
    /// Actor reentrancy around the MainActor pasteboard hop must not let an
    /// older call publish ownership after a newer copy already completed.
    private var writeMutationLocked = false
    private var writeMutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        mutationGate: StorageMutationGate = StorageMutationGate(),
        pasteboardWriter: PasteboardWriter? = nil,
        pasteboardCompareAndClear: PasteboardCompareAndClear? = nil,
        pasteboardRollback: PasteboardRollback? = nil
    ) {
        self.pasteboardWriter = pasteboardWriter ?? { secret, expires, localOnly in
            Self.applyToPasteboard(secret: secret, expires: expires, localOnly: localOnly)
        }
        self.mutationGate = mutationGate
        self.pasteboardCompareAndClear = pasteboardCompareAndClear ?? { changeCount in
            Self.clearPasteboardIfChangeCountEquals(changeCount)
        }
        self.pasteboardRollback = pasteboardRollback ?? { changeCount in
            Self.clearPasteboardIfChangeCountEquals(changeCount)
        }
    }

    func write(
        _ secret: String,
        expiresAfter: TimeInterval?,
        localOnly: Bool,
        committing: @escaping ClipboardCommit
    ) async throws {
        await acquireWriteMutation()
        defer { releaseWriteMutation() }
        let storagePermit = try mutationGate.beginNormal(operation: "clipboard_write")
        defer { storagePermit.finish() }

        // Keep the previous ownership record and cleanup task alive until the
        // replacement write is known to have succeeded. In particular, a
        // Catalyst `.localOnly` failure must not strand the previously copied
        // secret by cancelling its timer before this write commits.
        let expires = expiresAfter.map { Date().addingTimeInterval($0) }
        let writer = pasteboardWriter
        let rollback = pasteboardRollback
        let attempt: PasteboardWriteResult = try await MainActor.run {
            var attempt: PasteboardWriteResult = .failure(lastAttemptChangeCount: nil)
            try committing {
                attempt = writer(secret, expires, localOnly)
                switch attempt {
                case .success:
                    break
                case .failure(let lastAttemptChangeCount):
                    if let lastAttemptChangeCount {
                        // Writer and rollback execute in the same synchronous
                        // MainActor operation. The count check prevents this
                        // failed attempt from deleting a later external write.
                        _ = rollback(lastAttemptChangeCount)
                    }
                }
            }
            return attempt
        }

        let changeCount: Int
        switch attempt {
        case .success(let committedChangeCount):
            changeCount = committedChangeCount
        case .failure(lastAttemptChangeCount: nil):
            // The pasteboard was untouched, so the prior ownership/timer is
            // still valid and remains responsible for the previous secret.
            throw ApiRelayError.validationFailed(field: "clipboard", reason: "write_failed")
        case .failure:
            // The replacement attempt touched the pasteboard. Whether rollback
            // cleared it or a later external write won, the old ownership token
            // can no longer match. Retire its ownership token, timer and exact
            // termination fallback instead of retaining stale plaintext.
            clearTask?.cancel()
            clearTask = nil
            lastWrittenChangeCount = nil
            let supersededGeneration = writeGeneration
            await ClipboardTerminationGuard.disarm(
                ifOwnedByGeneration: supersededGeneration
            )
            throw ApiRelayError.validationFailed(field: "clipboard", reason: "write_failed")
        }

        clearTask?.cancel()
        clearTask = nil
        writeGeneration &+= 1
        let generation = writeGeneration
        lastWrittenChangeCount = changeCount

        guard let delay = expiresAfter else {
            // The user disabled timed cleanup, not authenticated full-erase
            // cleanup. Retain only the opaque generation token (never another
            // plaintext copy) so an erase can still clear this exact item.
            await ClipboardTerminationGuard.disarm(upToGeneration: generation)
            return
        }
        if delay <= 0 {
            // “立即”就是写入成功后立刻清除，不能与“关闭自动清除”的 nil 混为一谈。
            await clearIfStillOurs(expectedGeneration: generation)
            return
        }
        await ClipboardTerminationGuard.arm(changeCount: changeCount, generation: generation)

        let sleepFor = delay
        clearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(sleepFor * 1_000_000_000))
            } catch {
                // 连续复制时旧任务会被取消。取消后必须直接结束，不能把新复制的内容提前清掉。
                return
            }
            guard !Task.isCancelled else { return }
            await self?.clearIfStillOurs(expectedGeneration: generation)
        }
    }

    func clearIfStillOurs() async {
        await clearIfStillOurs(expectedGeneration: nil)
    }

    private func clearIfStillOurs(expectedGeneration: UInt64?) async {
        if let expectedGeneration, expectedGeneration != writeGeneration { return }
        let clearingGeneration = writeGeneration
        guard let lastWrittenChangeCount else { return }
        _ = await pasteboardCompareAndClear(lastWrittenChangeCount)

        // The MainActor hop above is an actor-reentrancy point. A newer write may
        // already own both the pasteboard and the termination guard; stale cleanup
        // must leave all of that state untouched.
        guard clearingGeneration == writeGeneration else { return }
        clearTask?.cancel()
        clearTask = nil
        self.lastWrittenChangeCount = nil
        await ClipboardTerminationGuard.disarm(ifOwnedByGeneration: clearingGeneration)
    }

    // MARK: - Pasteboard (must touch UIKit/AppKit on MainActor)

    /// 返回写入成功后的剪贴板 `changeCount`；写入失败返回 `nil`。
    @MainActor
    private static func applyToPasteboard(
        secret: String,
        expires: Date?,
        localOnly: Bool
    ) -> PasteboardWriteResult {
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        #if targetEnvironment(macCatalyst)
        // Mac Catalyst：`setItems` + `.expirationDate` 常无法被其他 App 粘贴（P07 已知风险），
        // 因此 Mac 端不带系统过期，清除只有应用内计时 + 退出兜底两条路。
        // 这条局限 MUST 在设置页如实披露，MUST NOT 声称到点必然清除。
        if localOnly {
            // 用户明确要求仅本机时，写入失败必须报错；不能悄悄退回普通剪贴板而把明文同步出去。
            return setItemsVerifying(pb, secret: secret, options: [.localOnly: true])
        }
        pb.string = secret
        let changeCount = pb.changeCount
        return pb.string == secret
            ? .success(changeCount: changeCount)
            : .failure(lastAttemptChangeCount: changeCount)
        #else
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        if let expires {
            options[.expirationDate] = expires
        }
        if localOnly {
            options[.localOnly] = true
        }
        return setItemsVerifying(pb, secret: secret, options: options)
        #endif
        #elseif canImport(AppKit)
        let board = NSPasteboard.general
        let item = NSPasteboardItem()
        guard item.setString(secret, forType: .string) else {
            return .failure(lastAttemptChangeCount: nil)
        }
        if localOnly {
            // AppKit 没有 UIKit `.localOnly` 的公开等价 API。原生 macOS 只能给常见的
            // 密码管理器/剪贴板工具标记“敏感、临时”，尽力减少接力与历史留存；设置页必须披露非保证。
            _ = item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            _ = item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }
        board.clearContents()
        let wrote = board.writeObjects([item])
        let changeCount = board.changeCount
        guard wrote, board.string(forType: .string) == secret else {
            return .failure(lastAttemptChangeCount: changeCount)
        }
        return .success(changeCount: changeCount)
        #else
        return .failure(lastAttemptChangeCount: nil)
        #endif
    }

    #if canImport(UIKit)
    /// 个别系统版本 `setItems` 后 `.string` 短暂为空。补写 MUST 重发同一份 `options`：
    /// `pb.string =` 会整份替换 items，把 `.expirationDate` 与 `.localOnly` 一起冲掉。
    @MainActor
    private static func setItemsVerifying(
        _ pb: UIPasteboard,
        secret: String,
        options: [UIPasteboard.OptionsKey: Any]
    ) -> PasteboardWriteResult {
        var lastAttemptChangeCount: Int?
        for _ in 0..<2 {
            pb.setItems([["public.utf8-plain-text": secret]], options: options)
            let changeCount = pb.changeCount
            lastAttemptChangeCount = changeCount
            if pb.string == secret {
                return .success(changeCount: changeCount)
            }
        }
        return .failure(lastAttemptChangeCount: lastAttemptChangeCount)
    }
    #endif

    /// Roll back a write that the OS may have accepted even though immediate
    /// read-back failed. `changeCount` is the only trustworthy ownership token
    /// in that state; checking it and clearing are one synchronous MainActor op.
    @MainActor
    private static func clearPasteboardIfChangeCountEquals(_ changeCount: Int) -> Bool {
        #if canImport(UIKit)
        let board = UIPasteboard.general
        guard board.changeCount == changeCount else { return false }
        board.items = []
        return true
        #elseif canImport(AppKit)
        let board = NSPasteboard.general
        guard board.changeCount == changeCount else { return false }
        board.clearContents()
        return true
        #else
        return false
        #endif
    }

    private func acquireWriteMutation() async {
        if !writeMutationLocked {
            writeMutationLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            writeMutationWaiters.append(continuation)
        }
    }

    private func releaseWriteMutation() {
        guard !writeMutationWaiters.isEmpty else {
            writeMutationLocked = false
            return
        }
        writeMutationWaiters.removeFirst().resume()
    }
}

/// 进程退出时来不及 `await` `SecureClipboard` 取明文比对，改用 `changeCount` 判定剪贴板
/// 是否仍是本产品写入的那一份——写入后没人再复制过，`changeCount` 就不会变。
/// 只覆盖正常退出（Mac ⌘Q）。**强制退出与崩溃不会走到这里**，设置页已如实说明。
@MainActor
enum ClipboardTerminationGuard {
    private struct ArmedWrite {
        let changeCount: Int
        let generation: UInt64
    }

    private static var armedWrite: ArmedWrite?

    static func arm(changeCount: Int, generation: UInt64) {
        if let armedWrite, armedWrite.generation > generation { return }
        armedWrite = ArmedWrite(changeCount: changeCount, generation: generation)
    }

    /// A successful write with auto-clear disabled supersedes any older guard,
    /// but must not erase a newer guard that armed while its actor was suspended.
    static func disarm(upToGeneration generation: UInt64) {
        guard let armedWrite, armedWrite.generation <= generation else { return }
        self.armedWrite = nil
    }

    /// Timer/manual cleanup owns exactly one generation. A stale cleanup must not
    /// disarm the process-termination fallback installed by a later write.
    static func disarm(ifOwnedByGeneration generation: UInt64) {
        guard armedWrite?.generation == generation else { return }
        armedWrite = nil
    }

    static func clearIfStillOursOnTerminate() {
        guard let armed = armedWrite else { return }
        armedWrite = nil
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        guard pb.changeCount == armed.changeCount else { return }
        pb.items = []
        #elseif canImport(AppKit)
        let board = NSPasteboard.general
        guard board.changeCount == armed.changeCount else { return }
        board.clearContents()
        #endif
    }

    #if DEBUG
    static func armedSnapshotForTests() -> (changeCount: Int, generation: UInt64)? {
        armedWrite.map { ($0.changeCount, $0.generation) }
    }

    static func resetForTests() {
        armedWrite = nil
    }
    #endif
}
