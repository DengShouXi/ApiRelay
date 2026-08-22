import Foundation

protocol ClipboardServing: Actor {
    func write(_ secret: String, expiresAfter: TimeInterval, localOnly: Bool) async throws
    /// 仅当剪贴板仍是本产品写入的那一份时才清除。
    func clearIfStillOurs() async
}

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

actor SecureClipboard: ClipboardServing {
    private var lastWritten: String?
    private var clearTask: Task<Void, Never>?

    func write(_ secret: String, expiresAfter: TimeInterval, localOnly: Bool) async throws {
        lastWritten = secret
        clearTask?.cancel()

        let expires = Date().addingTimeInterval(expiresAfter)
        let changeCount = await Self.applyToPasteboard(
            secret: secret,
            expires: expires,
            localOnly: localOnly
        )
        guard let changeCount else {
            lastWritten = nil
            await ClipboardTerminationGuard.disarm()
            throw ApiRelayError.validationFailed(field: "clipboard", reason: "write_failed")
        }
        await ClipboardTerminationGuard.arm(changeCount: changeCount)

        let delay = expiresAfter
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.clearIfStillOurs()
        }
    }

    func clearIfStillOurs() async {
        clearTask?.cancel()
        clearTask = nil
        guard let lastWritten else { return }
        self.lastWritten = nil
        let stillOurs = await Self.pasteboardStillEquals(lastWritten)
        if stillOurs {
            await Self.clearPasteboard()
        }
        await ClipboardTerminationGuard.disarm()
    }

    // MARK: - Pasteboard (must touch UIKit/AppKit on MainActor)

    /// 返回写入成功后的剪贴板 `changeCount`；写入失败返回 `nil`。
    @MainActor
    private static func applyToPasteboard(
        secret: String,
        expires: Date,
        localOnly: Bool
    ) -> Int? {
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        #if targetEnvironment(macCatalyst)
        // Mac Catalyst：`setItems` + `.expirationDate` 常无法被其他 App 粘贴（P07 已知风险），
        // 因此 Mac 端不带系统过期，清除只有应用内计时 + 退出兜底两条路。
        // 这条局限 MUST 在设置页如实披露，MUST NOT 声称到点必然清除。
        if localOnly, setItemsVerifying(pb, secret: secret, options: [.localOnly: true]) {
            return pb.changeCount
        }
        pb.string = secret
        return pb.string == secret ? pb.changeCount : nil
        #else
        var options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: expires
        ]
        if localOnly {
            options[.localOnly] = true
        }
        guard setItemsVerifying(pb, secret: secret, options: options) else { return nil }
        return pb.changeCount
        #endif
        #elseif canImport(AppKit)
        let board = NSPasteboard.general
        board.clearContents()
        guard board.setString(secret, forType: .string) else { return nil }
        return board.changeCount
        #else
        return nil
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
    ) -> Bool {
        for _ in 0..<2 {
            pb.setItems([["public.utf8-plain-text": secret]], options: options)
            if pb.string == secret { return true }
        }
        return false
    }
    #endif

    @MainActor
    private static func pasteboardStillEquals(_ value: String) -> Bool {
        #if canImport(UIKit)
        return UIPasteboard.general.string == value
        #elseif canImport(AppKit)
        return NSPasteboard.general.string(forType: .string) == value
        #else
        return false
        #endif
    }

    @MainActor
    private static func clearPasteboard() {
        #if canImport(UIKit)
        // `string = ""` 会留下一条空字符串条目；置空 items 才是真的清干净。
        UIPasteboard.general.items = []
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        #endif
    }
}

/// 进程退出时来不及 `await` `SecureClipboard` 取明文比对，改用 `changeCount` 判定剪贴板
/// 是否仍是本产品写入的那一份——写入后没人再复制过，`changeCount` 就不会变。
/// 只覆盖正常退出（Mac ⌘Q）。**强制退出与崩溃不会走到这里**，设置页已如实说明。
@MainActor
enum ClipboardTerminationGuard {
    private static var armedChangeCount: Int?

    static func arm(changeCount: Int) {
        armedChangeCount = changeCount
    }

    static func disarm() {
        armedChangeCount = nil
    }

    static func clearIfStillOursOnTerminate() {
        guard let armed = armedChangeCount else { return }
        armedChangeCount = nil
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        guard pb.changeCount == armed else { return }
        pb.items = []
        #elseif canImport(AppKit)
        let board = NSPasteboard.general
        guard board.changeCount == armed else { return }
        board.clearContents()
        #endif
    }
}
