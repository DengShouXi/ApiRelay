import Foundation

/// A queued completion belongs to the page request and the user-visible draft
/// that submitted it. An old result must not reload over a newer local edit.
struct SecurityPreferenceNotificationContext: Sendable {
    let requestRevision: UInt64
    let draftRevision: UInt64
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
        if let localOnly = patch.clipboardLocalOnly, current.clipboardLocalOnly, !localOnly {
            return true
        }
        if let seconds = patch.autoLockSeconds {
            let nextEnabled = patch.appLockEnabled ?? current.appLockEnabled
            if nextEnabled && seconds > current.autoLockSeconds {
                return true
            }
        }
        if let seconds = patch.clipboardClearSeconds {
            let nextEnabled = patch.clipboardClearEnabled ?? current.clipboardClearEnabled
            if nextEnabled && seconds > current.clipboardClearSeconds {
                return true
            }
        }
        if let revealAuth = patch.revealAuthEnabled, current.revealAuthEnabled, !revealAuth {
            return true
        }
        if let policy = patch.revealPolicy {
            let from = RevealPolicyPersistence.canonical(current.revealPolicy)
            let to = RevealPolicyPersistence.canonical(policy)
            if from != to {
                if to == .noVerification { return true }
                if from != .noVerification, to != .noVerification { return true }
            }
        }
        return false
    }

    nonisolated static func rank(_ policy: RevealPolicy) -> Int {
        switch RevealPolicyPersistence.canonical(policy) {
        case .noVerification: return 0
        case .biometricOrPasscode: return 1
        case .masterPassword, .biometryOrAppPassword: return 2
        }
    }
}

/// 降低已同步安全等级：必须等 persist 成功才改内存锁态（FR-069）。
enum SecurityPreferenceCommit: Sendable {
    private nonisolated static let contextKey = "securityPreferenceNotificationContext"

    nonisolated static func isCurrent(
        _ notification: Notification,
        requestRevision: UInt64,
        draftRevision: UInt64
    ) -> Bool {
        guard let context = notification.userInfo?[contextKey]
            as? SecurityPreferenceNotificationContext else { return true }
        return context.requestRevision == requestRevision
            && context.draftRevision == draftRevision
    }

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
        authorization: SecurityPreferenceAuthorization? = nil,
        notificationContext: SecurityPreferenceNotificationContext? = nil,
        applyMemory: (PreferencesDTO) -> Void
    ) {
        let next = current.applying(patch)
        let applyNow = appliesMemoryBeforePersist(patch, relativeTo: current)
        if applyNow {
            applyMemory(next)
        }
        let expectedPolicy = authorization?.openedPolicy
            ?? RevealPolicyPersistence.canonical(current.revealPolicy)
        preferences.persist(
            patch,
            authorizing: {
                try authorization?.authorize()
            },
            committing: { operation in
                if let authorization {
                    try authorization.commit(operation)
                } else {
                    try operation()
                }
            },
            expectedCurrentPolicy: expectedPolicy,
            onFailure: { _ in
                authorization?.finish()
                // The production repository invokes callbacks on one serial
                // write chain. Dispatching onto the serial main queue retains
                // their enqueue order while SwiftUI receives them on main.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .securityPreferencesPersistFailed,
                        object: nil,
                        userInfo: notificationContext.map { [contextKey: $0] }
                    )
                }
            },
            onSuccess: {
                authorization?.finish()
                if !applyNow {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .securityPreferencesDidPersist,
                            object: nil,
                            userInfo: notificationContext.map { [contextKey: $0] }
                        )
                    }
                }
            }
        )
    }
}
