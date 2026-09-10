import Foundation

/// 一扇窗相对当前空间的输入。`id` 生产环境用 `UIWindowScene.session.persistentIdentifier`。
struct WindowPrivacyInput: Equatable, Sendable, Identifiable {
    /// 测试把整进程收成一扇窗时用的占位 id。
    static let syntheticProcessID = "process"

    var id: String
    var presence: AppLockScenePresence
}

/// 一扇窗该盖快照还是该出解锁层。锁态仍是进程级。
struct WindowPrivacySurface: Equatable, Sendable {
    var showsSnapshotCover: Bool
    var showsUnlockChrome: Bool
}

/// `reduce(windows:)` 的输出。计时只看进程汇总；遮罩按窗。
struct WindowPrivacyReduction: Equatable, Sendable {
    var processPresence: AppLockScenePresence
    var startIdleTimer: Bool
    var surfaces: [String: WindowPrivacySurface]

    var coveredIDs: Set<String> {
        Set(surfaces.compactMap { $0.value.showsSnapshotCover ? $0.key : nil })
    }

    var unlockChromeIDs: Set<String> {
        Set(surfaces.compactMap { $0.value.showsUnlockChrome ? $0.key : nil })
    }

    func surface(for id: String) -> WindowPrivacySurface {
        surfaces[id] ?? WindowPrivacySurface(showsSnapshotCover: false, showsUnlockChrome: false)
    }
}

/// 窗口级隐私、进程级锁。无 UIKit，便于注入 scene 列表单测。
enum WindowPrivacyReducer {
    static func processPresence(of windows: [WindowPrivacyInput]) -> AppLockScenePresence {
        if windows.contains(where: { $0.presence == .userFacing }) {
            return .userFacing
        }
        if windows.contains(where: { $0.presence == .onScreenIdle }) {
            return .onScreenIdle
        }
        return .offScreen
    }

    static func reduce(
        windows: [WindowPrivacyInput],
        hideInAppSwitcher: Bool,
        isSessionLocked: Bool,
        hasBecomeActiveOnce: Bool
    ) -> WindowPrivacyReduction {
        let process = processPresence(of: windows)
        var surfaces: [String: WindowPrivacySurface] = [:]
        surfaces.reserveCapacity(windows.count)
        for window in windows {
            surfaces[window.id] = surface(
                presence: window.presence,
                hideInAppSwitcher: hideInAppSwitcher,
                isSessionLocked: isSessionLocked,
                hasBecomeActiveOnce: hasBecomeActiveOnce
            )
        }
        return WindowPrivacyReduction(
            processPresence: process,
            startIdleTimer: process == .offScreen,
            surfaces: surfaces
        )
    }

    private static func surface(
        presence: AppLockScenePresence,
        hideInAppSwitcher: Bool,
        isSessionLocked: Bool,
        hasBecomeActiveOnce: Bool
    ) -> WindowPrivacySurface {
        switch presence {
        case .userFacing:
            return WindowPrivacySurface(
                showsSnapshotCover: false,
                showsUnlockChrome: isSessionLocked
            )
        case .onScreenIdle:
            return WindowPrivacySurface(showsSnapshotCover: false, showsUnlockChrome: false)
        case .offScreen:
            let cover = hasBecomeActiveOnce && (hideInAppSwitcher || isSessionLocked)
            return WindowPrivacySurface(showsSnapshotCover: cover, showsUnlockChrome: false)
        }
    }
}
