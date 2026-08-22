#if canImport(UIKit)
import UIKit

/// Mac Catalyst /「为 iPad 设计」在 Mac 上默认 `sizeRestrictions` 过紧，窗口几乎只能最大化。
/// 在场景激活时放宽最大尺寸，保留合理最小尺寸，以便拖边框自由缩放。
@MainActor
final class MacWindowSizingAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.applyIfNeeded()
        NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                Self.applyIfNeeded()
            }
        }
        return true
    }

    /// 本 App 唯一的 `UIApplicationDelegate`，顺带承接退出前的剪贴板尽力清除。
    /// Mac ⌘Q 会走到这里；进程随即消失，来不及 `await` `SecureClipboard`，故走同步的
    /// `changeCount` 判定。强制退出与崩溃不会调用本方法，设置页已如实说明。
    func applicationWillTerminate(_ application: UIApplication) {
        ClipboardTerminationGuard.clearIfStillOursOnTerminate()
    }

    private static var runsOnMacDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    static func applyIfNeeded() {
        guard runsOnMacDesktop else { return }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 720, height: 480)
            windowScene.sizeRestrictions?.maximumSize = CGSize(width: 12_000, height: 12_000)
            #if targetEnvironment(macCatalyst)
            // 去掉中栏+右栏共用的系统总顶栏（窗口标题会横跨两栏）。
            if let titlebar = windowScene.titlebar {
                titlebar.titleVisibility = .hidden
                titlebar.toolbar = nil
                titlebar.separatorStyle = .none
            }
            #endif
        }
    }
}
#endif
