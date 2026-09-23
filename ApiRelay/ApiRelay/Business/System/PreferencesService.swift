import Foundation
import SwiftData

extension Notification.Name {
    /// 安全偏好非阻塞写入失败。设置页回滚内存并提示。
    nonisolated static let securityPreferencesPersistFailed = Notification.Name("com.apirelay.securityPreferencesPersistFailed")
    /// 降低安全等级的写入已落盘。设置页此时才改内存锁态。
    nonisolated static let securityPreferencesDidPersist = Notification.Name("com.apirelay.securityPreferencesDidPersist")
}

/// The last, synchronous authorization seam around the repository save itself.
/// Implementations must not suspend while `operation` is running.
typealias PreferencesCommit = @Sendable (_ operation: () throws -> Void) throws -> Void

/// A single settings-page authorization transaction. The page generation and
/// the unlocked-session generation are both captured before authentication and
/// are both held across the final synchronous repository save.
///
/// This closes the gap where authentication succeeds, the app/window stops
/// being user-facing, and an already queued security downgrade writes later.
nonisolated final class SecurityPreferenceAuthorization: @unchecked Sendable {
    let openedPolicy: RevealPolicy

    private let request: AppPasswordSubmitContext
    private let sessionLock: any SessionLockQuerying
    private let sessionAuthorization: SessionAuthorizationLease

    nonisolated init(
        currentPolicy: RevealPolicy,
        targetPolicy: RevealPolicy? = nil,
        sessionLock: any SessionLockQuerying
    ) throws {
        let opened = RevealPolicyPersistence.canonical(currentPolicy)
        let target = RevealPolicyPersistence.canonical(targetPolicy ?? opened)
        let pageLease = AppPasswordPageLease(target: target, currentPolicy: opened)
        guard let token = pageLease.begin() else {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "stale_page_request"
            )
        }
        self.openedPolicy = opened
        self.request = AppPasswordSubmitContext(lease: pageLease, token: token)
        self.sessionLock = sessionLock
        do {
            self.sessionAuthorization = try sessionLock.captureAuthorizationLease()
        } catch {
            pageLease.invalidate()
            throw error
        }
    }

    nonisolated func authorize() throws {
        try request.authorize(.policyPersist, currentPolicy: openedPolicy)
        try sessionLock.validateAuthorizationLease(sessionAuthorization)
    }

    /// Page and session invalidation race this exact synchronous boundary. No
    /// async work is permitted inside `operation`.
    nonisolated func commit(_ operation: () throws -> Void) throws {
        try request.commit(.policyPersist, currentPolicy: openedPolicy) {
            try sessionLock.commitAuthorizationLease(sessionAuthorization, operation: operation)
        }
    }

    nonisolated func finish() {
        request.lease.end(request.token)
    }

    nonisolated func invalidate() {
        request.lease.invalidate()
    }
}

protocol PreferencesServing: Actor {
    func load() async throws -> PreferencesDTO
    func update(_ patch: PreferencesPatch) async throws
    /// 同步偏好的非阻塞写入。界面与 MainActor 上的控制器 MUST 走这条，
    /// MUST NOT `await update`——那会让主线程干等 CloudKit/SwiftData 落盘。
    /// 安全类写入失败时 MUST 回调，界面回滚；不得静默吞掉。
    /// 降低等级的成功回调用于在落盘之后才改内存锁态（FR-069）。
    /// 入队不等于已提交：`authorizing` 在出队后、实际 `update` 前执行。
    nonisolated func persist(
        _ patch: PreferencesPatch,
        authorizing: @escaping @Sendable () async throws -> Void,
        committing: @escaping PreferencesCommit,
        expectedCurrentPolicy: RevealPolicy?,
        onFailure: (@Sendable (Error) -> Void)?,
        onSuccess: (@Sendable () -> Void)?
    )
    /// FR-061：清空同步偏好与本机偏好；下次 `load` 会重建默认值。
    func purgeAllRecordsForErase() async throws
    /// 仅供持久化、已授权的全量清除事务绕过正常写入闸门。
    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws
}

extension PreferencesServing {
    nonisolated func persist(
        _ patch: PreferencesPatch,
        onFailure: (@Sendable (Error) -> Void)?,
        onSuccess: (@Sendable () -> Void)?
    ) {
        persist(
            patch,
            authorizing: {},
            committing: { operation in try operation() },
            expectedCurrentPolicy: nil,
            onFailure: onFailure,
            onSuccess: onSuccess
        )
    }

    nonisolated func persist(_ patch: PreferencesPatch, onFailure: (@Sendable (Error) -> Void)?) {
        persist(patch, onFailure: onFailure, onSuccess: nil)
    }

    nonisolated func persist(_ patch: PreferencesPatch) {
        persist(patch, onFailure: nil, onSuccess: nil)
    }
}

actor PreferencesService: PreferencesServing {
    private let userRepo: UserPreferencesRepository
    private let deviceRepo: DevicePreferencesRepository
    private let mutationGate: StorageMutationGate
    private nonisolated let writeChain = SerialWriteChain()

    init(
        modelContainer: ModelContainer,
        mutationGate: StorageMutationGate = StorageMutationGate()
    ) {
        self.userRepo = UserPreferencesRepository(modelContainer: modelContainer)
        self.deviceRepo = DevicePreferencesRepository(modelContainer: modelContainer)
        self.mutationGate = mutationGate
    }

    func load() async throws -> PreferencesDTO {
        // Both repositories use load-or-create and may repair/canonicalize old
        // rows, so this is a write-capable transaction even for a UI "read".
        let storagePermit = try mutationGate.beginNormal(operation: "preferences_load_or_create")
        defer { storagePermit.finish() }
        let user = try await userRepo.loadOrCreate()
        let device = try await deviceRepo.loadOrCreate()
        return PreferencesDTO(
            appLockEnabled: user.appLockEnabled,
            autoLockSeconds: user.autoLockSeconds,
            autoLockDurationOptions: user.autoLockDurationOptions,
            revealPolicy: user.revealPolicy,
            revealAuthEnabled: user.revealAuthEnabled,
            clipboardClearEnabled: user.clipboardClearEnabled,
            clipboardClearSeconds: user.clipboardClearSeconds,
            clipboardClearDurationOptions: user.clipboardClearDurationOptions,
            clipboardLocalOnly: user.clipboardLocalOnly,
            hideInAppSwitcher: user.hideInAppSwitcher,
            refreshIntervalMinutes: user.refreshIntervalMinutes,
            displayCurrency: user.displayCurrency,
            usdToDisplayRate: user.usdToDisplayRate,
            notifyLowBalance: user.notifyLowBalance,
            notifyKeyRevoked: user.notifyKeyRevoked,
            notifyWeeklyDigest: user.notifyWeeklyDigest,
            lowBalanceThreshold: user.lowBalanceThreshold,
            appearance: device.appearance,
            defaultGrouping: device.defaultGrouping,
            assignPickerFilter: device.assignPickerFilter,
            lastWindowWidth: device.lastWindowWidth,
            lastWindowHeight: device.lastWindowHeight,
            platformSectionSort: device.platformSectionSort,
            consumerSectionSort: device.consumerSectionSort,
            defaultKeyAvatarSymbol: nonempty(device.defaultKeyAvatarSymbol),
            defaultKeyAvatarColor: nonempty(device.defaultKeyAvatarColor),
            defaultCustomAccountAvatarSymbol: nonempty(device.defaultCustomAccountAvatarSymbol),
            defaultCustomAccountAvatarColor: nonempty(device.defaultCustomAccountAvatarColor),
            defaultCustomToolAvatarSymbol: nonempty(device.defaultCustomToolAvatarSymbol),
            defaultCustomToolAvatarColor: nonempty(device.defaultCustomToolAvatarColor)
        )
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func update(_ patch: PreferencesPatch) async throws {
        try await update(patch, expectedCurrentPolicy: nil)
    }

    private func update(
        _ patch: PreferencesPatch,
        expectedCurrentPolicy: RevealPolicy?,
        committing: @escaping PreferencesCommit = { operation in try operation() }
    ) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "preferences_update")
        defer { storagePermit.finish() }
        // FR-060：外观/默认视角/窗口 → DevicePreferences；其余 → UserPreferences
        var persistedAppLockArmed: Bool?
        if patch.writesUserPreferences {
            persistedAppLockArmed = try await userRepo.update(
                patch,
                expectedCurrentPolicy: expectedCurrentPolicy,
                committing: committing
            )
        }
        if patch.writesDevicePreferences {
            try await deviceRepo.update(patch)
        }
        if (patch.appLockEnabled != nil || patch.revealPolicy != nil),
           let persistedAppLockArmed
        {
            // The launch cache represents the effective armed state, never the
            // raw switch. `appLockEnabled + noVerification` must not draw a
            // false lock screen before SwiftData/CloudKit has loaded.
            AppLockLaunchCache.write(persistedAppLockArmed)
        }
    }

    /// 界面写入 CloudKit 同步的 UserPreferences 时，MUST NOT 在 MainActor 上 `await update`。
    /// SwiftUI `.modelContainer` 的 mainContext 与 `@ModelActor` save 互相等待，会卡住整窗转圈。
    /// 立即返回，写入排进串行链：连拨开关时最后一次拨的值一定是最后写进去的那个。
    /// 出队后先取得提交许可，再核对当前策略，许可失效则 MUST NOT `update`。
    nonisolated func persist(
        _ patch: PreferencesPatch,
        authorizing: @escaping @Sendable () async throws -> Void = {},
        committing: @escaping PreferencesCommit = { operation in try operation() },
        expectedCurrentPolicy: RevealPolicy? = nil,
        onFailure: (@Sendable (Error) -> Void)? = nil,
        onSuccess: (@Sendable () -> Void)? = nil
    ) {
        writeChain.append { [weak self] in
            do {
                try await authorizing()
                guard let self else { return }
                if let expected = expectedCurrentPolicy {
                    let loaded = try await self.load()
                    let actual = RevealPolicyPersistence.canonical(loaded.revealPolicy)
                    let wanted = RevealPolicyPersistence.canonical(expected)
                    guard actual == wanted else {
                        throw ApiRelayError.validationFailed(
                            field: "revealPolicy",
                            reason: "stale_page_request"
                        )
                    }
                    try await authorizing()
                }
                // 仓库必须再次在实际写入的同一同步操作中核对条件。
                // 上面的 load 仅用于尽早拒绝，不是最终提交依据。
                try await self.update(
                    patch,
                    expectedCurrentPolicy: expectedCurrentPolicy,
                    committing: committing
                )
                onSuccess?()
            } catch {
                onFailure?(error)
            }
        }
    }

    /// 等到目前排队的 `persist` 全部落盘。测试用；界面 MUST NOT 调用，那就等于又在主线程干等 save。
    nonisolated func drainPendingWrites() async {
        await writeChain.drain()
    }

    /// FR-061：清空同步偏好与本机偏好；下次 `load` 会重建默认值。
    func purgeAllRecordsForErase() async throws {
        let storagePermit = try mutationGate.beginNormal(
            operation: "preferences_legacy_erase"
        )
        defer { storagePermit.finish() }
        try await purgeAllRecordsForEraseStorage()
    }

    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws {
        try mutationGate.validateCommittedEraseToken(
            authorization,
            operation: "preferences_committed_erase"
        )
        try await purgeAllRecordsForEraseStorage()
    }

    private func purgeAllRecordsForEraseStorage() async throws {
        try await userRepo.deleteAllRecords()
        try await deviceRepo.deleteAllRecords()
        AppLockLaunchCache.write(false)
    }
}

/// 把「不等结果」的写入按调用顺序串起来。
/// 各自 `Task.detached` 是并发的，谁先落盘不确定；对同一个字段连拨就可能留下中间值。
/// 入队在锁内同步完成，因此链上的顺序 == 调用顺序；每个任务先等上一个跑完再动手。
/// `Task.detached`：工程开了 NonisolatedNonsendingByDefault，普通 `Task {}` 仍会继承 MainActor。
nonisolated final class SerialWriteChain: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never> = Task.detached {}

    func append(_ work: @escaping @Sendable () async -> Void) {
        lock.lock()
        let previous = tail
        tail = Task.detached {
            await previous.value
            await work()
        }
        lock.unlock()
    }

    /// 测试用：等到目前排队的写入全部落盘。生产代码 MUST NOT 在 MainActor 上调用。
    /// 取尾巴要单独走同步方法：`NSLock` 在 async 上下文里不可用（跨挂起点持锁会死锁）。
    func drain() async {
        await currentTail().value
    }

    private func currentTail() -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }
        return tail
    }
}
