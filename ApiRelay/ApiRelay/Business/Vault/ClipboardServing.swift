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
        let ok = await Self.applyToPasteboard(
            secret: secret,
            expires: expires,
            localOnly: localOnly
        )
        guard ok else {
            lastWritten = nil
            throw ApiRelayError.validationFailed(field: "clipboard", reason: "write_failed")
        }

        let delay = expiresAfter
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.clearIfStillOurs()
        }
    }

    func clearIfStillOurs() async {
        guard let lastWritten else { return }
        let stillOurs = await Self.pasteboardStillEquals(lastWritten)
        if stillOurs {
            await Self.clearPasteboard()
        }
        self.lastWritten = nil
    }

    // MARK: - Pasteboard (must touch UIKit/AppKit on MainActor)

    @MainActor
    private static func applyToPasteboard(
        secret: String,
        expires: Date,
        localOnly: Bool
    ) -> Bool {
        #if canImport(UIKit)
        let pb = UIPasteboard.general
        #if targetEnvironment(macCatalyst)
        // Mac Catalyst：`setItems` + `.expirationDate` 常无法被其他 App 粘贴（P07 已知风险）。
        // 先写入 `.string` 保证可粘贴；限时清除靠应用内 Timer 兜底（research §2）。
        pb.string = secret
        if localOnly {
            pb.setItems(
                [["public.utf8-plain-text": secret]],
                options: [.localOnly: true]
            )
            if pb.string != secret {
                pb.string = secret
            }
        }
        #else
        var options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: expires
        ]
        if localOnly {
            options[.localOnly] = true
        }
        pb.setItems(
            [["public.utf8-plain-text": secret]],
            options: options
        )
        // 个别系统版本 setItems 后 `.string` 短暂为空；补一次 string 兜底。
        if pb.string != secret {
            pb.string = secret
        }
        #endif
        return pb.string == secret
        #elseif canImport(AppKit)
        let board = NSPasteboard.general
        board.clearContents()
        return board.setString(secret, forType: .string)
        #else
        return false
        #endif
    }

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
        UIPasteboard.general.string = ""
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        #endif
    }
}
