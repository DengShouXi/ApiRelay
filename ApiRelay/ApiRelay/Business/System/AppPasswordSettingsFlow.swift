import Foundation

/// 设置页选档：两种密码依赖档进入同一应用密码页并绑定原目标；首页管理行只看已 persist 的当前档。
enum AppPasswordSettingsDestination: Equatable, Sendable {
    case persistPolicy(RevealPolicy)
    case appPasswordPage(target: RevealPolicy)
}

enum AppPasswordSettingsRouting: Sendable {
    nonisolated static func destination(selected: RevealPolicy) -> AppPasswordSettingsDestination {
        let canonical = RevealPolicyPersistence.canonical(selected)
        if AppPasswordSetup.requiresMaterial(canonical) {
            return .appPasswordPage(target: canonical)
        }
        return .persistPolicy(canonical)
    }

    nonisolated static func showsHomeManagementRow(currentPolicy: RevealPolicy) -> Bool {
        AppPasswordSetup.requiresMaterial(RevealPolicyPersistence.canonical(currentPolicy))
    }

    nonisolated static func isManagingCurrent(target: RevealPolicy, current: RevealPolicy) -> Bool {
        let canonicalTarget = RevealPolicyPersistence.canonical(target)
        let canonicalCurrent = RevealPolicyPersistence.canonical(current)
        return AppPasswordSetup.requiresMaterial(canonicalTarget)
            && canonicalTarget == canonicalCurrent
    }

    nonisolated static func homeRowStatus(_ material: AppPasswordMaterialStatus) -> String {
        switch material {
        case .set:
            String(localized: "settings.masterPassword.status.set")
        case .unset:
            String(localized: "settings.masterPassword.status.unset")
        case .unreadable:
            String(localized: "settings.appPassword.status.unreadable")
        }
    }
}

/// 应用密码页：创建 / 当前方式确认 / 改密 / 独立恢复分开建模，不靠「是否在改新密码」决定旧密码能不能输入。
struct AppPasswordPageSurface: Equatable, Sendable {
    var target: RevealPolicy
    var currentPolicy: RevealPolicy
    var material: AppPasswordMaterialStatus?

    var isLoaded: Bool { material != nil }

    var isManagingCurrent: Bool {
        guard isLoaded else { return false }
        return AppPasswordSettingsRouting.isManagingCurrent(target: target, current: currentPolicy)
    }

    var showsLoading: Bool { !isLoaded }
    var showsUnreadableBanner: Bool { material == .unreadable }
    var showsRetry: Bool { material == .unreadable }
    var showsCreateForm: Bool { material == .unset }
    var showsSetStatus: Bool { material == .set }
    var showsKeepExisting: Bool { material == .set && !isManagingCurrent }
    var showsChangePassword: Bool { material == .set }
    var showsRecover: Bool { isLoaded }
    var showsCurrentMasterPasswordField: Bool {
        material == .set
            && RevealPolicyPersistence.canonical(currentPolicy) == .masterPassword
            && showsKeepExisting
    }
    var showsComboExplicitPasswordField: Bool {
        material == .set
            && RevealPolicyPersistence.canonical(currentPolicy) == .biometryOrAppPassword
            && showsKeepExisting
    }
}

enum AppPasswordCurrentConfirmKind: Equatable, Sendable {
    case skip
    case deviceOwner
    case masterPassword
    case combinationBiometry
    case combinationAppPassword
}

enum AppPasswordSettingsFlow: Sendable {
    nonisolated static func confirmKind(
        currentPolicy: RevealPolicy,
        material: AppPasswordMaterialStatus?,
        prefersCombinationAppPassword: Bool
    ) -> AppPasswordCurrentConfirmKind {
        guard let material else { return .skip }
        switch RevealPolicyPersistence.canonical(currentPolicy) {
        case .noVerification:
            return .skip
        case .biometricOrPasscode:
            return .deviceOwner
        case .masterPassword:
            guard material == .set else { return .skip }
            return .masterPassword
        case .biometryOrAppPassword:
            if prefersCombinationAppPassword, material == .set {
                return .combinationAppPassword
            }
            return .combinationBiometry
        }
    }

    static func confirmCurrent(
        gate: any RevealGateServing,
        master: any MasterPasswordServing,
        currentPolicy: RevealPolicy,
        currentPassword: String,
        combinationAppPassword: String?,
        prefersCombinationAppPassword: Bool
    ) async throws {
        let material = await master.materialStatus()
        let kind = confirmKind(
            currentPolicy: currentPolicy,
            material: material,
            prefersCombinationAppPassword: prefersCombinationAppPassword
        )
        let reason = String(localized: "gate.changeSecuritySettings")
        switch kind {
        case .skip:
            return
        case .deviceOwner:
            try await CurrentRevealPolicyAuth.confirm(
                .biometricOrPasscode,
                gate: gate,
                reason: reason,
                purpose: .settings
            )
        case .masterPassword:
            try await CurrentRevealPolicyAuth.confirm(
                .masterPassword,
                gate: gate,
                reason: reason,
                purpose: .settings,
                appPassword: currentPassword
            )
        case .combinationBiometry:
            try await CurrentRevealPolicyAuth.confirm(
                .biometryOrAppPassword,
                gate: gate,
                reason: reason,
                purpose: .settings,
                appPassword: nil
            )
        case .combinationAppPassword:
            try await CurrentRevealPolicyAuth.confirm(
                .biometryOrAppPassword,
                gate: gate,
                reason: reason,
                purpose: .settings,
                appPassword: combinationAppPassword ?? ""
            )
        }
    }
}

/// 页面待办：取消、返回、离前台、当前策略被同步改写时作废旧请求。不能倒转已经落盘的事务。
nonisolated final class AppPasswordPageLease: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var inFlight = false
    private var sceneActive = true
    private let target: RevealPolicy
    private var openedCurrentPolicy: RevealPolicy

    nonisolated init(target: RevealPolicy, currentPolicy: RevealPolicy) {
        self.target = RevealPolicyPersistence.canonical(target)
        self.openedCurrentPolicy = RevealPolicyPersistence.canonical(currentPolicy)
    }

    nonisolated var boundTarget: RevealPolicy { target }

    nonisolated func openedPolicy() -> RevealPolicy {
        lock.lock()
        defer { lock.unlock() }
        return openedCurrentPolicy
    }

    nonisolated func noteOpenedPolicy(_ policy: RevealPolicy) {
        lock.lock()
        openedCurrentPolicy = RevealPolicyPersistence.canonical(policy)
        lock.unlock()
    }

    nonisolated func invalidate(newCurrentPolicy: RevealPolicy? = nil) {
        lock.lock()
        generation += 1
        inFlight = false
        if let newCurrentPolicy {
            openedCurrentPolicy = RevealPolicyPersistence.canonical(newCurrentPolicy)
        }
        lock.unlock()
    }

    nonisolated func begin() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard !inFlight else { return nil }
        generation += 1
        inFlight = true
        return generation
    }

    nonisolated func end(_ token: UInt64) {
        lock.lock()
        if token == generation {
            inFlight = false
        }
        lock.unlock()
    }

    nonisolated func isBusy() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return inFlight
    }

    nonisolated func isFresh(_ token: UInt64, sceneActive: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token == generation && inFlight && self.sceneActive && sceneActive
    }

    nonisolated func matchesOpenedPolicy(_ policy: RevealPolicy) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return RevealPolicyPersistence.canonical(policy) == openedCurrentPolicy
    }

    nonisolated func noteSceneActive(_ active: Bool) {
        lock.lock()
        sceneActive = active
        lock.unlock()
    }

    /// 与 `invalidate` 争同一把锁：此调用返回成功即该步提交许可已线性化。
    /// MUST NOT 在持锁时 await。
    nonisolated func authorize(
        _ token: UInt64,
        step: AppPasswordSubmitStep,
        currentPolicy: RevealPolicy? = nil
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard token == generation, inFlight, sceneActive else {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "stale_page_request"
            )
        }
        if let currentPolicy,
           RevealPolicyPersistence.canonical(currentPolicy) != openedCurrentPolicy
        {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "stale_page_request"
            )
        }
        switch step {
        case .proceed, .materialWrite, .policyPersist, .recoveryDelete:
            break
        }
    }

    /// Linearizes an irreversible synchronous write against `invalidate`.
    /// If resign/background wins the lock, the operation never starts; if this
    /// wins, invalidation waits until the repository save has completed.
    nonisolated func commit(
        _ token: UInt64,
        step: AppPasswordSubmitStep,
        currentPolicy: RevealPolicy? = nil,
        operation: () throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard token == generation, inFlight, sceneActive else {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "stale_page_request"
            )
        }
        if let currentPolicy,
           RevealPolicyPersistence.canonical(currentPolicy) != openedCurrentPolicy
        {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "stale_page_request"
            )
        }
        switch step {
        case .proceed, .materialWrite, .policyPersist, .recoveryDelete:
            try operation()
        }
    }

    nonisolated func requireFreshForConfirm(
        _ token: UInt64,
        currentPolicy: RevealPolicy,
        sceneActive: Bool
    ) throws {
        try authorize(token, step: .proceed, currentPolicy: currentPolicy)
        guard sceneActive else {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "stale_page_request"
            )
        }
    }
}

nonisolated enum AppPasswordSubmitStep: Equatable, Sendable {
    case proceed
    case materialWrite
    case policyPersist
    case recoveryDelete
}

/// 页面/锁屏把同一份 lease+token 交给协调器与真实提交接缝。
nonisolated struct AppPasswordSubmitContext: Sendable {
    let lease: AppPasswordPageLease
    let token: UInt64

    func authorize(
        _ step: AppPasswordSubmitStep,
        currentPolicy: RevealPolicy? = nil
    ) throws {
        try lease.authorize(token, step: step, currentPolicy: currentPolicy)
    }

    func commit(
        _ step: AppPasswordSubmitStep,
        currentPolicy: RevealPolicy? = nil,
        operation: () throws -> Void
    ) throws {
        try lease.commit(
            token,
            step: step,
            currentPolicy: currentPolicy,
            operation: operation
        )
    }
}
