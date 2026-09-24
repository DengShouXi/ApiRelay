import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

#if canImport(UIKit)
/// 盖在现有窗口上，保证 `willResignActive` 返回前图层里已有遮罩。
enum AppSwitcherSnapshotCover {
    static let viewTag = 71_080_301

    static func sync(
        coveredIDs: Set<String>,
        showsLockMark: Bool = false,
        removesUncovered: Bool = true
    ) {
        let scenes = allScenes()
        let coverAll = coveredIDs.contains(WindowPrivacyInput.syntheticProcessID)
        for scene in scenes {
            let shouldShow = coverAll || coveredIDs.contains(scene.session.persistentIdentifier)
            for window in visibleWindows(in: scene) {
                apply(shouldShow: shouldShow, to: window, showsLockMark: showsLockMark, removesUncovered: removesUncovered)
            }
        }
    }

    private static func apply(
        shouldShow: Bool,
        to window: UIWindow,
        showsLockMark: Bool,
        removesUncovered: Bool
    ) {
        let existing = window.viewWithTag(viewTag) as? SnapshotCoverView
        if shouldShow {
            if let existing {
                existing.setShowsLockMark(showsLockMark)
                existing.isHidden = false
                window.bringSubviewToFront(existing)
            } else {
                let cover = SnapshotCoverView(frame: window.bounds)
                cover.setShowsLockMark(showsLockMark)
                window.addSubview(cover)
            }
            window.layoutIfNeeded()
        } else if removesUncovered {
            existing?.removeFromSuperview()
        }
    }

    private static func allScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }

    private static func visibleWindows(in scene: UIWindowScene) -> [UIWindow] {
        let visible = scene.windows.filter { !$0.isHidden }
        if !visible.isEmpty { return visible }
        return scene.windows.filter(\.isKeyWindow)
    }
}

private final class SnapshotCoverView: UIView {
    private let lockView: UIImageView = {
        let image = UIImageView(image: UIImage(systemName: AppSymbols.Settings.appLock))
        image.tintColor = .secondaryLabel
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        image.translatesAutoresizingMaskIntoConstraints = false
        image.isHidden = true
        return image
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        tag = AppSwitcherSnapshotCover.viewTag
        backgroundColor = .systemBackground
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // 只挡系统截屏，不抢触摸。否则回到前台后会盖住 SwiftUI 解锁按钮，点了没反应。
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityLabel = String(localized: "appLock.coverTitle")
        addSubview(lockView)
        NSLayoutConstraint.activate([
            lockView.centerXAnchor.constraint(equalTo: centerXAnchor),
            lockView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func setShowsLockMark(_ shows: Bool) {
        lockView.isHidden = !shows
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
/// 原生 macOS 没有 UIKit 的 scene 快照层；在每扇窗口 contentView 顶部同步放置无交互遮罩。
enum AppSwitcherSnapshotCover {
    static let viewIdentifier = NSUserInterfaceItemIdentifier("ApiRelay.AppSwitcherSnapshotCover")

    static func id(for window: NSWindow) -> String {
        "nswindow:\(window.windowNumber)"
    }

    static func sync(
        coveredIDs: Set<String>,
        showsLockMark: Bool = false,
        removesUncovered: Bool = true
    ) {
        let coverAll = coveredIDs.contains(WindowPrivacyInput.syntheticProcessID)
        for window in NSApplication.shared.windows where window.isVisible && !window.isMiniaturized {
            guard let contentView = window.contentView else { continue }
            // SwiftUI owns NSHostingController.view's subview hierarchy. Put
            // the privacy cover beside that view in their common superview,
            // constrained exactly to the content rect (not the title bar).
            guard let container = contentView.superview else { continue }
            let existing = container.subviews.first { $0.identifier == viewIdentifier } as? SnapshotCoverView
            let shouldShow = coverAll || coveredIDs.contains(id(for: window))
            if shouldShow {
                if let existing {
                    existing.setShowsLockMark(showsLockMark)
                    existing.isHidden = false
                    container.addSubview(existing, positioned: .above, relativeTo: contentView)
                } else {
                    let cover = SnapshotCoverView(frame: contentView.convert(contentView.bounds, to: container))
                    cover.setShowsLockMark(showsLockMark)
                    cover.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(cover, positioned: .above, relativeTo: contentView)
                    NSLayoutConstraint.activate([
                        cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                        cover.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                        cover.topAnchor.constraint(equalTo: contentView.topAnchor),
                        cover.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
                    ])
                }
                container.layoutSubtreeIfNeeded()
            } else if removesUncovered {
                existing?.removeFromSuperview()
            }
        }
    }
}

private final class SnapshotCoverView: NSView {
    private let lockView: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(
            systemSymbolName: AppSymbols.Settings.appLock,
            accessibilityDescription: String(localized: "appLock.coverTitle")
        )
        view.imageScaling = .scaleProportionallyUpOrDown
        view.contentTintColor = .secondaryLabelColor
        view.isHidden = true
        return view
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = AppSwitcherSnapshotCover.viewIdentifier
        autoresizingMask = [.width, .height]
        wantsLayer = true
        updateBackgroundColor()
        addSubview(lockView)
    }

    override func layout() {
        super.layout()
        let side: CGFloat = 52
        lockView.frame = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func setShowsLockMark(_ shows: Bool) {
        lockView.isHidden = !shows
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
#endif
