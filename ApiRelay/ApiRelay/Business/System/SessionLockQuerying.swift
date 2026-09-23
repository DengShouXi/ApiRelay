import Foundation

/// 一次敏感业务操作的会话授权租约。
///
/// 数值不对业务层暴露；租约只能由 `SessionLockQuerying` 生成，
/// 并且必须回到同一个会话锁实例验证。
nonisolated struct SessionAuthorizationLease: Sendable {
    fileprivate let sourceID: UUID
    fileprivate let generation: UInt64

    fileprivate init(sourceID: UUID, generation: UInt64) {
        self.sourceID = sourceID
        self.generation = generation
    }
}

/// Opaque ownership token for one externally imported security-policy refresh.
///
/// CloudKit can replace `revealPolicy` / `revealAuthEnabled` while an operation
/// is suspended in authentication. The import callback synchronously opens this
/// fence before any asynchronous UI reload. Only the newest refresh may close
/// it after a successful authoritative persistence read.
nonisolated struct SecurityPolicyRefreshToken: Hashable, Sendable {
    fileprivate let sourceID: UUID
    fileprivate let revision: UInt64

    fileprivate init(sourceID: UUID, revision: UInt64) {
        self.sourceID = sourceID
        self.revision = revision
    }
}

/// 会话锁只读查询。业务入口用它拦敏感动作；界面遮罩不得承担安全职责。
/// MUST NOT 依赖 SwiftUI / `AppPrivacyController`。
protocol SessionLockQuerying: Sendable {
    nonisolated func isSessionLocked() -> Bool
    /// 敏感操作开始时捕获；已锁定则立即拒绝。
    nonisolated func captureAuthorizationLease() throws -> SessionAuthorizationLease
    /// 在认证后、明文返回前和每个不可逆副作用前复核。
    nonisolated func validateAuthorizationLease(_ lease: SessionAuthorizationLease) throws
    /// 将最终同步副作用与租约失效线性化。若提交先取得会话锁，失效会等到
    /// `operation` 完成；若失效先取得锁，副作用不得开始。闭包内 MUST NOT await。
    nonisolated func commitAuthorizationLease(
        _ lease: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws

    /// A pending full-data erase is deliberately resumed while the ordinary
    /// application session remains locked: its preferences and password
    /// material may already have been deleted. Recovery authority is therefore
    /// separate from normal vault authority. It is still generation-bound and
    /// MUST NOT be minted or committed while the app is not user-facing.
    nonisolated func captureEraseRecoveryLease() throws -> SessionAuthorizationLease
    nonisolated func validateEraseRecoveryLease(_ lease: SessionAuthorizationLease) throws
    nonisolated func commitEraseRecoveryLease(
        _ lease: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws
}

extension SessionLockQuerying {
    nonisolated func captureEraseRecoveryLease() throws -> SessionAuthorizationLease {
        try captureAuthorizationLease()
    }

    nonisolated func validateEraseRecoveryLease(_ lease: SessionAuthorizationLease) throws {
        try validateAuthorizationLease(lease)
    }

    nonisolated func commitEraseRecoveryLease(
        _ lease: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws {
        try commitAuthorizationLease(lease, operation: operation)
    }
}

nonisolated struct AlwaysUnlockedSessionLock: SessionLockQuerying {
    private static let sourceID = UUID()

    nonisolated func isSessionLocked() -> Bool { false }

    nonisolated func captureAuthorizationLease() throws -> SessionAuthorizationLease {
        SessionAuthorizationLease(sourceID: Self.sourceID, generation: 0)
    }

    nonisolated func validateAuthorizationLease(_ lease: SessionAuthorizationLease) throws {
        guard lease.sourceID == Self.sourceID, lease.generation == 0 else {
            throw ApiRelayError.sessionLocked
        }
    }

    nonisolated func commitAuthorizationLease(
        _ lease: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws {
        try validateAuthorizationLease(lease)
        try operation()
    }

}

/// App 层写入、Business 层读取。锁态变化时由 `AppPrivacyController` 更新。
nonisolated final class SessionLockBox: SessionLockQuerying, @unchecked Sendable {
    private let lock = NSLock()
    private let sourceID = UUID()
    nonisolated(unsafe) private var locked = false
    /// A grace-period session can remain visually unlocked after leaving the
    /// foreground, but it must not mint fresh authority while nobody is using
    /// this app. This is deliberately distinct from the user-visible lock bit.
    nonisolated(unsafe) private var authorizationSuspended = false
    /// A mobile `willResignActive` frame cannot initially distinguish Home from
    /// Control Center. During that short observation window, deny capture and
    /// commit without advancing `generation`: a confirmed leave is promoted to
    /// formal suspension, while an unconfirmed active return can resume the
    /// exact same lease instead of turning a system overlay into data loss.
    nonisolated(unsafe) private var authorizationProvisionallyFenced = false
    nonisolated(unsafe) private var generation: UInt64 = 0
    /// While a Cloud/imported security policy is being reloaded, old leases are
    /// revoked and new ordinary leases fail closed. A separate monotonic
    /// revision prevents an older overlapping reload from reopening the fence.
    nonisolated(unsafe) private var securityPolicyRefreshRevision: UInt64 = 0
    nonisolated(unsafe) private var pendingSecurityPolicyRefreshRevision: UInt64?

    nonisolated func setLocked(_ value: Bool) {
        lock.lock()
        if value, !locked {
            advanceGenerationOrFailClosed()
        }
        locked = value
        lock.unlock()
    }

    /// 真实离开前台时立即撤销已发出租约，不必等到自动锁定定时器到期。
    /// 该方法只换代，不改变当前 `locked` 状态。
    nonisolated func invalidateAuthorizationLeases() {
        lock.lock()
        advanceGenerationOrFailClosed()
        lock.unlock()
    }

    /// Real loss of the user-facing surface revokes existing leases and blocks
    /// new captures throughout the auto-lock grace period. Returning to a
    /// user-facing active window re-enables capture but never revives old
    /// generations.
    nonisolated func setAuthorizationSuspended(_ value: Bool) {
        lock.lock()
        if value, !authorizationSuspended {
            advanceGenerationOrFailClosed()
        }
        authorizationSuspended = value
        lock.unlock()
    }

    nonisolated func isAuthorizationSuspended() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return authorizationSuspended
    }

    nonisolated func setAuthorizationProvisionallyFenced(_ value: Bool) {
        lock.lock()
        authorizationProvisionallyFenced = value
        lock.unlock()
    }

    nonisolated func isAuthorizationProvisionallyFenced() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return authorizationProvisionallyFenced
    }

    /// Must be called directly from the external-policy notification callback,
    /// before scheduling any Task. NotificationCenter block delivery is
    /// synchronous, so returning from the import notification means no lease
    /// based on the previous policy can still commit.
    nonisolated func beginExternalSecurityPolicyRefresh() -> SecurityPolicyRefreshToken {
        lock.lock()
        defer { lock.unlock() }
        advanceGenerationOrFailClosed()
        guard securityPolicyRefreshRevision < UInt64.max else {
            // The revision cannot be made unique again. Keep the application
            // permanently fail-closed rather than allow an old completion to
            // become current after integer wraparound.
            locked = true
            pendingSecurityPolicyRefreshRevision = UInt64.max
            return SecurityPolicyRefreshToken(sourceID: sourceID, revision: UInt64.max)
        }
        securityPolicyRefreshRevision += 1
        pendingSecurityPolicyRefreshRevision = securityPolicyRefreshRevision
        return SecurityPolicyRefreshToken(
            sourceID: sourceID,
            revision: securityPolicyRefreshRevision
        )
    }

    /// True only for the newest overlapping refresh. Callers use this before
    /// applying a loaded policy so an older async reload cannot overwrite a
    /// newer import in memory.
    nonisolated func isCurrentSecurityPolicyRefresh(
        _ token: SecurityPolicyRefreshToken
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token.sourceID == sourceID
            && token.revision == pendingSecurityPolicyRefreshRevision
    }

    /// Reopens ordinary authorization only after the exact newest refresh has
    /// successfully read the authoritative store. Failure deliberately leaves
    /// the fence pending; no fallback policy may be used for secrets or writes.
    @discardableResult
    nonisolated func completeExternalSecurityPolicyRefresh(
        _ token: SecurityPolicyRefreshToken
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard token.sourceID == sourceID,
              token.revision == pendingSecurityPolicyRefreshRevision else {
            return false
        }
        pendingSecurityPolicyRefreshRevision = nil
        return true
    }

    nonisolated func hasPendingSecurityPolicyRefresh() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingSecurityPolicyRefreshRevision != nil
    }

    nonisolated func currentSecurityPolicyRefreshToken() -> SecurityPolicyRefreshToken? {
        lock.lock()
        defer { lock.unlock() }
        guard let revision = pendingSecurityPolicyRefreshRevision else { return nil }
        return SecurityPolicyRefreshToken(sourceID: sourceID, revision: revision)
    }

    nonisolated func isSessionLocked() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return locked
    }

    nonisolated func captureAuthorizationLease() throws -> SessionAuthorizationLease {
        lock.lock()
        defer { lock.unlock() }
        guard !locked,
              !authorizationSuspended,
              !authorizationProvisionallyFenced,
              pendingSecurityPolicyRefreshRevision == nil else {
            throw ApiRelayError.sessionLocked
        }
        return SessionAuthorizationLease(sourceID: sourceID, generation: generation)
    }

    nonisolated func validateAuthorizationLease(_ lease: SessionAuthorizationLease) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !locked,
              !authorizationSuspended,
              !authorizationProvisionallyFenced,
              pendingSecurityPolicyRefreshRevision == nil,
              lease.sourceID == sourceID,
              lease.generation == generation else {
            throw ApiRelayError.sessionLocked
        }
    }

    nonisolated func commitAuthorizationLease(
        _ lease: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !locked,
              !authorizationSuspended,
              !authorizationProvisionallyFenced,
              pendingSecurityPolicyRefreshRevision == nil,
              lease.sourceID == sourceID,
              lease.generation == generation else {
            throw ApiRelayError.sessionLocked
        }
        try operation()
    }

    nonisolated func captureEraseRecoveryLease() throws -> SessionAuthorizationLease {
        lock.lock()
        defer { lock.unlock() }
        guard !authorizationSuspended,
              !authorizationProvisionallyFenced else {
            throw ApiRelayError.sessionLocked
        }
        return SessionAuthorizationLease(sourceID: sourceID, generation: generation)
    }

    nonisolated func validateEraseRecoveryLease(_ lease: SessionAuthorizationLease) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !authorizationSuspended,
              !authorizationProvisionallyFenced,
              lease.sourceID == sourceID,
              lease.generation == generation else {
            throw ApiRelayError.sessionLocked
        }
    }

    nonisolated func commitEraseRecoveryLease(
        _ lease: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !authorizationSuspended,
              !authorizationProvisionallyFenced,
              lease.sourceID == sourceID,
              lease.generation == generation else {
            throw ApiRelayError.sessionLocked
        }
        try operation()
    }

    /// `UInt64.max` 实际不可达；若真到达则永久锁定，禁止 generation 回绕复活旧租约。
    private nonisolated func advanceGenerationOrFailClosed() {
        guard generation < UInt64.max else {
            locked = true
            return
        }
        generation += 1
    }
}

/// Synchronous notification-to-authorization bridge for externally imported
/// security policy. It deliberately does not know CloudKit types; production
/// injects the pipeline snapshot decoder and tests inject deterministic begin /
/// end signals.
nonisolated final class SecurityPolicyRefreshNotificationFence: @unchecked Sendable {
    enum Signal: Sendable {
        case began
        case ended
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var activeToken: SecurityPolicyRefreshToken?

        func receive(
            _ signal: Signal,
            sessionLock: SessionLockBox
        ) -> SecurityPolicyRefreshToken? {
            lock.lock()
            defer { lock.unlock() }
            switch signal {
            case .began:
                activeToken = sessionLock.beginExternalSecurityPolicyRefresh()
                return nil
            case .ended:
                let current = activeToken
                    ?? sessionLock.beginExternalSecurityPolicyRefresh()
                activeToken = current
                return current
            }
        }

        func clear(ifCurrent token: SecurityPolicyRefreshToken) {
            lock.lock()
            defer { lock.unlock() }
            if activeToken == token {
                activeToken = nil
            }
        }
    }

    private let center: NotificationCenter
    private let observer: NSObjectProtocol
    private let state: State

    init(
        center: NotificationCenter = .default,
        notificationName: Notification.Name,
        sessionLock: SessionLockBox,
        decode: @escaping @Sendable (Notification) -> Signal?,
        bootstrapImportInFlight: @escaping @Sendable () -> Bool = { false },
        reload: @escaping @Sendable (SecurityPolicyRefreshToken) async -> Bool
    ) {
        self.center = center
        let state = State()
        self.state = state
        observer = center.addObserver(
            forName: notificationName,
            object: nil,
            queue: nil
        ) { notification in
            guard let signal = decode(notification) else { return }
            let token = state.receive(signal, sessionLock: sessionLock)
            guard let token else { return }
            Task {
                guard await reload(token) else { return }
                guard sessionLock.completeExternalSecurityPolicyRefresh(token) else { return }
                state.clear(ifCurrent: token)
            }
        }
        // Register first, then sample the process-wide pre-container bridge.
        // If an import starts between these two operations the observer and the
        // snapshot may both report it; opening a newer revision twice is safe,
        // whereas sampling before registration would leave a lost-start gap.
        if bootstrapImportInFlight() {
            _ = state.receive(.began, sessionLock: sessionLock)
        }
    }

    deinit {
        center.removeObserver(observer)
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
                NotificationCenter.default.post(name: .securityPreferencesPersistFailed, object: nil)
            },
            onSuccess: {
                authorization?.finish()
                if !applyNow {
                    NotificationCenter.default.post(name: .securityPreferencesDidPersist, object: nil)
                }
            }
        )
    }
}

/// 组合档显式应用密码：空白必须在调门闩前拒绝；取消/失败不得自动改走另一条认证路径。
enum CombinationExplicitAuth: Sendable {
    /// `nil` = 尚未提交口令，走单次系统设备主人认证。非空才走 `confirmCombinationWithAppPassword`。
    static func normalizedPassword(_ appPassword: String?) throws -> String? {
        guard let appPassword else { return nil }
        let trimmed = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "combination_password_empty"
            )
        }
        return trimmed
    }

    static func isCombination(_ policy: RevealPolicy) -> Bool {
        RevealPolicyPersistence.canonical(policy) == .biometryOrAppPassword
    }

    /// 系统认证取消或旧错误源报告生物不可用/锁定后，界面可显示「使用应用密码」，但不得自动提交应用密码路径。
    static func shouldOfferAppPassword(after error: Error) -> Bool {
        switch error as? ApiRelayError {
        case .authenticationCancelled, .biometryUnavailable, .biometryLockout, .devicePasscodeNotSet:
            return true
        default:
            return false
        }
    }

    /// 只有已经绑定当前待办时才显示入口，禁止无反馈地武装下一次操作。
    static func shouldShowExplicitEntry(hasBoundOperation: Bool, policy: RevealPolicy) -> Bool {
        hasBoundOperation && isCombination(policy)
    }
}

/// 降低或互换验证方式时，按**当前**档确认，不得一律改走设备主人。
enum CurrentRevealPolicyAuth: Sendable {
    static func confirm(
        _ policy: RevealPolicy,
        gate: any RevealGateServing,
        reason: String,
        purpose: AuthPurpose,
        appPassword: String? = nil
    ) async throws {
        switch RevealPolicyPersistence.canonical(policy) {
        case .noVerification:
            return
        case .biometricOrPasscode:
            try await gate.confirm(reason: reason, policy: .biometricOrPasscode, purpose: purpose)
        case .biometryOrAppPassword:
            if let password = try CombinationExplicitAuth.normalizedPassword(appPassword) {
                try await gate.confirmCombinationWithAppPassword(
                    reason: reason,
                    password: password,
                    purpose: purpose
                )
            } else {
                try await gate.confirm(reason: reason, policy: .biometryOrAppPassword, purpose: purpose)
            }
        case .masterPassword:
            let trimmed = appPassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                throw ApiRelayError.validationFailed(
                    field: "revealPolicy",
                    reason: "master_password_prompt_required"
                )
            }
            try await gate.confirmWithMasterPassword(
                reason: reason,
                password: trimmed,
                purpose: purpose
            )
        }
    }
}

/// 应用密码档与组合档：未配置或材料不可读都不得当成可 persist 的当前策略。
enum AppPasswordPolicyGate: Sendable {
    nonisolated static func requiresMaterial(_ policy: RevealPolicy) -> Bool {
        AppPasswordSetup.requiresMaterial(policy)
    }

    nonisolated static func canPersistAsCurrentPolicy(
        _ policy: RevealPolicy,
        material: AppPasswordMaterialStatus
    ) -> Bool {
        guard requiresMaterial(policy) else { return true }
        return material == .set
    }

    nonisolated static func canPersistAsCurrentPolicy(
        _ policy: RevealPolicy,
        materialIsSet: Bool
    ) -> Bool {
        canPersistAsCurrentPolicy(policy, material: materialIsSet ? .set : .unset)
    }

    nonisolated static func canUseAppPasswordEntry(material: AppPasswordMaterialStatus) -> Bool {
        material == .set
    }

    nonisolated static func canUseAppPasswordEntry(materialIsSet: Bool) -> Bool {
        canUseAppPasswordEntry(material: materialIsSet ? .set : .unset)
    }

    /// Only a patch that is about to make an app-password-dependent policy
    /// current needs a Keychain material read. Ordinary security changes (for
    /// example 60 seconds -> immediately) must not await that unrelated read:
    /// the settings scene can become inactive in the gap and cancel a change
    /// the user already selected.
    nonisolated static func requiresMaterialLookup(for patch: PreferencesPatch) -> Bool {
        guard let policy = patch.revealPolicy else { return false }
        return requiresMaterial(policy)
    }

    /// 普通解锁/取用/编辑/删除/备份/降低安全入口不得 `setPassword`。
    nonisolated static func ordinaryEntryMissingMaterialMessage() -> String {
        String(localized: "appLock.combination.notSet")
    }

    /// 普通入口必须保留材料三态。Keychain 暂时不可读不是“从未设置”，
    /// 否则用户会被误导去重复设密或把存储故障当成自己的操作问题。
    nonisolated static func ordinaryEntryUnavailableMessage(
        material: AppPasswordMaterialStatus
    ) -> String {
        switch material {
        case .unreadable:
            String(localized: "settings.appPassword.status.unreadable")
        case .unset, .set:
            ordinaryEntryMissingMaterialMessage()
        }
    }

    nonisolated static func persistRejection(
        _ patch: PreferencesPatch,
        material: AppPasswordMaterialStatus
    ) -> ApiRelayError? {
        guard let policy = patch.revealPolicy else { return nil }
        guard canPersistAsCurrentPolicy(policy, material: material) else {
            if material == .unreadable {
                return ApiRelayError.validationFailed(
                    field: "masterPassword",
                    reason: "material_unreadable"
                )
            }
            return ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "master_password_not_configured"
            )
        }
        return nil
    }

    nonisolated static func persistRejection(
        _ patch: PreferencesPatch,
        materialIsSet: Bool
    ) -> ApiRelayError? {
        persistRejection(patch, material: materialIsSet ? .set : .unset)
    }
}

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
