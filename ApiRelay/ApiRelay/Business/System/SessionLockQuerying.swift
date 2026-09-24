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
