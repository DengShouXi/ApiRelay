import Foundation

/// 会话锁只读查询。业务入口用它拦敏感动作；界面遮罩不得承担安全职责。
/// MUST NOT 依赖 SwiftUI / `AppPrivacyController`。
protocol SessionLockQuerying: Sendable {
    nonisolated func isSessionLocked() -> Bool
}

struct AlwaysUnlockedSessionLock: SessionLockQuerying {
    nonisolated func isSessionLocked() -> Bool { false }
}

/// App 层写入、Business 层读取。锁态变化时由 `AppPrivacyController` 更新。
final class SessionLockBox: SessionLockQuerying, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var locked = false

    nonisolated func setLocked(_ value: Bool) {
        lock.lock()
        locked = value
        lock.unlock()
    }

    nonisolated func isSessionLocked() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return locked
    }
}

/// 哪些同步安全偏好变更算「降低等级」，必须再认证（FR-066）。
enum SecurityPolicyChange: Sendable {
    nonisolated static func weakens(_ patch: PreferencesPatch, relativeTo current: PreferencesDTO) -> Bool {
        if let enabled = patch.appLockEnabled, current.appLockEnabled, !enabled {
            return true
        }
        if let hide = patch.hideInAppSwitcher, current.hideInAppSwitcher, !hide {
            return true
        }
        if let clear = patch.clipboardClearEnabled, current.clipboardClearEnabled, !clear {
            return true
        }
        if let seconds = patch.autoLockSeconds {
            let nextEnabled = patch.appLockEnabled ?? current.appLockEnabled
            if nextEnabled && seconds > current.autoLockSeconds {
                return true
            }
        }
        if let policy = patch.revealPolicy, rank(policy) < rank(current.revealPolicy) {
            return true
        }
        return false
    }

    nonisolated static func rank(_ policy: RevealPolicy) -> Int {
        switch policy {
        case .noVerification: return 0
        case .biometricOrPasscode: return 1
        case .biometricOnly, .masterPassword: return 2
        }
    }
}

/// 降低已同步安全等级：必须等 persist 成功才改内存锁态（FR-069）。
enum SecurityPreferenceCommit: Sendable {
    nonisolated static func appliesMemoryBeforePersist(
        _ patch: PreferencesPatch,
        relativeTo current: PreferencesDTO
    ) -> Bool {
        !SecurityPolicyChange.weakens(patch, relativeTo: current)
    }

    /// 加强：可先改内存。降低：只 enqueue persist，成功后再发 `securityPreferencesDidPersist`。
    /// `applyMemory` 只在「可先改内存」时同步调用，调用方须已在 MainActor。
    @MainActor
    static func persist(
        _ patch: PreferencesPatch,
        relativeTo current: PreferencesDTO,
        using preferences: any PreferencesServing,
        applyMemory: (PreferencesDTO) -> Void
    ) {
        let next = current.applying(patch)
        let applyNow = appliesMemoryBeforePersist(patch, relativeTo: current)
        if applyNow {
            applyMemory(next)
        }
        preferences.persist(patch, onFailure: { _ in
            NotificationCenter.default.post(name: .securityPreferencesPersistFailed, object: nil)
        }, onSuccess: {
            if !applyNow {
                NotificationCenter.default.post(name: .securityPreferencesDidPersist, object: nil)
            }
        })
    }
}
