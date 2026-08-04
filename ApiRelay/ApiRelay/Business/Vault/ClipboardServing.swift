import Foundation

protocol ClipboardServing: Actor {
    func write(_ secret: String, expiresAfter: TimeInterval, localOnly: Bool)
    /// 仅当剪贴板仍是本产品写入的那一份时才清除。
    func clearIfStillOurs()
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

    func write(_ secret: String, expiresAfter: TimeInterval, localOnly: Bool) {
        lastWritten = secret
        clearTask?.cancel()

        #if canImport(UIKit)
        let board = UIPasteboard.general
        board.setValue(secret, forPasteboardType: "public.utf8-plain-text")
        board.string = secret
        if #available(iOS 16.0, macCatalyst 16.0, *) {
            board.expirationDate = Date().addingTimeInterval(expiresAfter)
        }
        // localOnly: set items with localOnly option when available
        if localOnly {
            board.setItems(
                [[UIPasteboard.typeAutomatic: secret]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(expiresAfter)]
            )
        }
        #elseif canImport(AppKit)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(secret, forType: .string)
        #endif

        let delay = expiresAfter
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.clearIfStillOurs()
        }
    }

    func clearIfStillOurs() {
        guard let lastWritten else { return }
        #if canImport(UIKit)
        if UIPasteboard.general.string == lastWritten {
            UIPasteboard.general.string = ""
        }
        #elseif canImport(AppKit)
        if NSPasteboard.general.string(forType: .string) == lastWritten {
            NSPasteboard.general.clearContents()
        }
        #endif
        self.lastWritten = nil
    }
}
