import Foundation
import LocalAuthentication

/// 身份确认门闩（FR-003）。实现 MUST NOT 跨操作缓存确认结果。
nonisolated enum AuthPurpose: Sendable {
    case unlockApp
    case revealSecret
    case destructive
    case settings
    case recovery
}

/// Authentication ownership is deliberately coarser than the business purpose.
/// Content screens may cancel their own prompts, but must never revoke the lock
/// screen or an account-recovery request that happens to be using the same gate.
nonisolated enum AuthenticationRequestOwner: Equatable, Sendable {
    case appUnlock
    case recovery
    case content
}

extension AuthPurpose {
    nonisolated var requestOwner: AuthenticationRequestOwner {
        switch self {
        case .unlockApp:
            return .appUnlock
        case .recovery:
            return .recovery
        case .revealSecret, .destructive, .settings:
            return .content
        }
    }
}

protocol RevealGateServing: Actor {
    func confirm(reason: String, policy: RevealPolicy, purpose: AuthPurpose) async throws
    /// 主密码档：由 UI 采集口令后校验；不经系统「本机密码」框。
    func confirmWithMasterPassword(reason: String, password: String, purpose: AuthPurpose) async throws
    /// 组合档：用户显式点「使用应用密码」后才走；MUST NOT 从生物取消自动调用。
    func confirmCombinationWithAppPassword(reason: String, password: String, purpose: AuthPurpose) async throws
    /// 破坏性操作强制设备主人认证（忽略用户 revealPolicy）。
    func confirmMandatory(reason: String, purpose: AuthPurpose) async throws
    /// 选用主密码门闩前确认本机已设密。
    func ensureMasterPasswordConfigured() async throws
    /// 本机是否已有应用密码校验材料。缺材料不得静默放行。
    func isAppPasswordMaterialSet() async throws -> Bool
    /// 材料三态。读取失败 MUST 为 `unreadable`，MUST NOT 冒充未设。
    func appPasswordMaterialStatus() async -> AppPasswordMaterialStatus
    /// 只取消指定所有者的请求。内容页清理 MUST NOT 取消锁屏或恢复请求。
    nonisolated func cancelAuthentication(owner: AuthenticationRequestOwner)
    /// 整个 App 已离开前台时取消任意请求。
    nonisolated func cancelAllAuthentication()
    /// 系统验证框正在前：同组失焦不得当成闲置去 cancel（FR-072）。
    nonisolated func isAuthenticationInProgress(owner: AuthenticationRequestOwner?) -> Bool
    nonisolated func availableBiometry() -> BiometryKind
}

extension RevealGateServing {
    func confirm(reason: String, policy: RevealPolicy) async throws {
        try await confirm(reason: reason, policy: policy, purpose: .revealSecret)
    }

    func confirmMandatory(reason: String) async throws {
        try await confirmMandatory(reason: reason, purpose: .destructive)
    }

    func confirmWithMasterPassword(reason: String, password: String) async throws {
        try await confirmWithMasterPassword(
            reason: reason,
            password: password,
            purpose: .revealSecret
        )
    }

    func confirmCombinationWithAppPassword(reason: String, password: String) async throws {
        try await confirmCombinationWithAppPassword(reason: reason, password: password, purpose: .revealSecret)
    }

    nonisolated func isAuthenticationInProgress() -> Bool {
        isAuthenticationInProgress(owner: nil)
    }
}

/// 本机应用密码校验材料。读取错误不得当成未设。
nonisolated enum AppPasswordMaterialStatus: Equatable, Sendable {
    case unset
    case set
    case unreadable
}

/// 未设才创建：当前方式（由调用方注入）→ 设备主人 → 写入复查 → persist **原目标**。
/// 每个 await 之后重新读取共享材料状态；已设只 persist，MUST NOT `setPassword`。
/// 读取失败、过期/并发变更 MUST NOT 覆盖或 persist。
nonisolated enum AppPasswordSetup: Sendable {
    nonisolated static func requiresMaterial(_ policy: RevealPolicy) -> Bool {
        switch RevealPolicyPersistence.canonical(policy) {
        case .masterPassword, .biometryOrAppPassword:
            return true
        default:
            return false
        }
    }

    static func createMaterialThenPersistTarget(
        target: RevealPolicy,
        materialStatus: @Sendable () async -> AppPasswordMaterialStatus,
        confirmCurrentIfNeeded: @Sendable () async throws -> Void,
        confirmDeviceOwner: @Sendable () async throws -> Void,
        setAndVerifyMaterial: @Sendable () async throws -> Void,
        persistTarget: @Sendable (RevealPolicy) async throws -> Void,
        materialRevision: @Sendable () async -> UInt64 = { 0 },
        commitPersist: (@Sendable (RevealPolicy, UInt64) async throws -> Void)? = nil,
        authorize: @Sendable () throws -> Void = {}
    ) async throws {
        let canonical = RevealPolicyPersistence.canonical(target)
        guard requiresMaterial(canonical) else {
            throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "not_password_dependent")
        }
        try rejectCreateUnlessUnset(await materialStatus())
        try authorize()
        try await confirmCurrentIfNeeded()
        try authorize()
        try rejectCreateUnlessUnset(await materialStatus())
        try authorize()
        try await confirmDeviceOwner()
        try authorize()
        try rejectCreateUnlessUnset(await materialStatus())
        try authorize()
        try await setAndVerifyMaterial()
        try authorize()
        try rejectPersistUnlessSet(await materialStatus())
        try authorize()
        if let commitPersist {
            let revision = await materialRevision()
            try authorize()
            try await commitPersist(canonical, revision)
        } else {
            try await persistTarget(canonical)
        }
    }

    static func persistExistingMaterialTarget(
        target: RevealPolicy,
        materialStatus: @Sendable () async -> AppPasswordMaterialStatus,
        confirmCurrentIfNeeded: @Sendable () async throws -> Void,
        persistTarget: @Sendable (RevealPolicy) async throws -> Void,
        authorize: @Sendable () throws -> Void = {}
    ) async throws {
        try await persistExistingMaterialTarget(
            target: target,
            materialStatus: materialStatus,
            confirmCurrentIfNeeded: confirmCurrentIfNeeded,
            materialRevision: { 0 },
            commitPersist: { policy, _ in try await persistTarget(policy) },
            authorize: authorize
        )
    }

    static func persistExistingMaterialTarget(
        target: RevealPolicy,
        materialStatus: @Sendable () async -> AppPasswordMaterialStatus,
        confirmCurrentIfNeeded: @Sendable () async throws -> Void,
        materialRevision: @Sendable () async -> UInt64,
        commitPersist: @Sendable (RevealPolicy, UInt64) async throws -> Void,
        authorize: @Sendable () throws -> Void = {}
    ) async throws {
        let canonical = RevealPolicyPersistence.canonical(target)
        guard requiresMaterial(canonical) else {
            throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "not_password_dependent")
        }
        try rejectPersistUnlessSet(await materialStatus())
        try authorize()
        try await confirmCurrentIfNeeded()
        try authorize()
        try rejectPersistUnlessSet(await materialStatus())
        try authorize()
        let revision = await materialRevision()
        try authorize()
        try await commitPersist(canonical, revision)
    }

    nonisolated static func rejectCreateUnlessUnset(_ status: AppPasswordMaterialStatus) throws {
        switch status {
        case .unset:
            return
        case .set:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "already_set")
        case .unreadable:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "material_unreadable")
        }
    }

    nonisolated static func rejectPersistUnlessSet(_ status: AppPasswordMaterialStatus) throws {
        switch status {
        case .set:
            return
        case .unset:
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "master_password_not_configured"
            )
        case .unreadable:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "material_unreadable")
        }
    }
}

/// 忘记/重置应用密码：先设备主人，策略成功落到设备验证后才删 `.masterpw`。MUST NOT 落到不验证。
enum AppPasswordRecovery: Sendable {
    nonisolated static var deviceAuthPatch: PreferencesPatch {
        PreferencesPatch(revealPolicy: .biometricOrPasscode)
    }

    static func recoverToDeviceAuth(
        confirmMandatory: @Sendable () async throws -> Void,
        persistDeviceAuth: @Sendable () async throws -> Void,
        resetMaterial: @Sendable () async throws -> Void,
        materialRevision: @Sendable () async -> UInt64 = { 0 },
        authorize: @Sendable () throws -> Void = {}
    ) async throws {
        let startRevision = await materialRevision()
        try authorize()
        try await confirmMandatory()
        try authorize()
        try rejectUnlessSameRevision(start: startRevision, current: await materialRevision())
        try authorize()
        try await persistDeviceAuth()
        try authorize()
        try rejectUnlessSameRevision(start: startRevision, current: await materialRevision())
        try authorize()
        try await resetMaterial()
    }

    /// 产品恢复：persist 后把预期版本交给材料服务，在同一排他提交里核对并删除。
    /// 不再在 reset 前额外读取 revision。锁屏旧入口仍走上面的 `resetMaterial` 重载。
    static func recoverToDeviceAuth(
        confirmMandatory: @Sendable () async throws -> Void,
        persistDeviceAuth: @Sendable () async throws -> Void,
        resetIfRevision: @Sendable (UInt64) async throws -> Void,
        snapshotRevision: @Sendable () async -> UInt64,
        authorize: @Sendable () throws -> Void = {}
    ) async throws {
        let startRevision = await snapshotRevision()
        try authorize()
        try await confirmMandatory()
        try authorize()
        try rejectUnlessSameRevision(start: startRevision, current: await snapshotRevision())
        try authorize()
        try await persistDeviceAuth()
        try authorize()
        try await resetIfRevision(startRevision)
    }

    nonisolated static func rejectUnlessSameRevision(start: UInt64, current: UInt64) throws {
        guard start == current else {
            throw ApiRelayError.validationFailed(
                field: "masterPassword",
                reason: "stale_concurrent"
            )
        }
    }

    /// 等待非阻塞 `persist` 的成功/失败回调。MUST NOT 在 MainActor 上 `await update()`。
    static func awaitPersist(
        _ preferences: any PreferencesServing,
        _ patch: PreferencesPatch
    ) async throws {
        try await awaitPersist(
            preferences,
            patch,
            authorizing: {},
            committing: { operation in try operation() },
            expectedCurrentPolicy: nil
        )
    }

    static func awaitPersist(
        _ preferences: any PreferencesServing,
        _ patch: PreferencesPatch,
        authorizing: @escaping @Sendable () async throws -> Void,
        committing: @escaping PreferencesCommit = { operation in try operation() },
        expectedCurrentPolicy: RevealPolicy?
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = PersistResumeOnce()
            preferences.persist(
                patch,
                authorizing: authorizing,
                committing: committing,
                expectedCurrentPolicy: expectedCurrentPolicy,
                onFailure: { error in once.resume(cont, throwing: error) },
                onSuccess: { once.resume(cont) }
            )
        }
    }
}

nonisolated private final class PersistResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ cont: CheckedContinuation<Void, Error>) {
        finish(cont, .success(()))
    }

    func resume(_ cont: CheckedContinuation<Void, Error>, throwing error: Error) {
        finish(cont, .failure(error))
    }

    private func finish(_ cont: CheckedContinuation<Void, Error>, _ result: Result<Void, Error>) {
        lock.lock()
        let should = !done
        if should { done = true }
        lock.unlock()
        guard should else { return }
        switch result {
        case .success:
            cont.resume()
        case .failure(let error):
            cont.resume(throwing: error)
        }
    }
}
