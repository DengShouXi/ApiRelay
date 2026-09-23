import Foundation
import OSLog
import SwiftData

@ModelActor
actor UserPreferencesRepository {
    private static let logger = Logger(
        subsystem: "com.apirelay.ApiRelay",
        category: "SecurityPreferences"
    )

    func loadOrCreate() throws -> PreferencesDTO {
        // 安全偏好会被设置页、密钥库、备份等多个 ModelActor 读取/写入。SwiftData 的
        // 长寿命 ModelContext 会继续返回已注册的旧对象；先 rollback 到持久化快照，
        // 才能保证开关保存后下一次敏感操作立即采用新策略。
        modelContext.rollback()
        var models = try fetchSingletons()
        if models.isEmpty {
            let created = UserPreferences()
            modelContext.insert(created)
            try modelContext.save()
            models = [created]
        }
        var didSeed = false
        for model in models {
            _ = seededOptions(
                stored: model.autoLockDurationOptionsJSON,
                current: model.autoLockSeconds,
                factory: DurationOptionList.autoLockFactory,
                didSeed: &didSeed
            ) { model.autoLockDurationOptionsJSON = $0 }
            _ = seededOptions(
                stored: model.clipboardClearDurationOptionsJSON,
                current: model.clipboardClearSeconds,
                factory: DurationOptionList.clipboardFactory,
                didSeed: &didSeed
            ) { model.clipboardClearDurationOptionsJSON = $0 }
        }
        if didSeed {
            try modelContext.save()
        }

        persistCanonicalRevealPolicies(on: models)
        let winner = SyncedIdentity.winner(in: models, rank: Self.rank) ?? models[0]
        let security = Self.conservativeSecurity(in: models)
        if models.count > 1 {
            Self.logger.warning(
                "Duplicate synced security preferences detected; applying conservative field merge to \(models.count, privacy: .public) replicas"
            )
            persistConservativeSecurity(security, on: models)
        }

        var didSeedAfter = false
        let autoLockOptions = seededOptions(
            stored: winner.autoLockDurationOptionsJSON,
            current: winner.autoLockSeconds,
            factory: DurationOptionList.autoLockFactory,
            didSeed: &didSeedAfter
        ) { _ in }
        let clipboardOptions = seededOptions(
            stored: winner.clipboardClearDurationOptionsJSON,
            current: winner.clipboardClearSeconds,
            factory: DurationOptionList.clipboardFactory,
            didSeed: &didSeedAfter
        ) { _ in }
        _ = didSeedAfter
        var result = Self.dto(
            from: winner,
            revealPolicy: security.revealPolicy,
            autoLockOptions: autoLockOptions,
            clipboardOptions: clipboardOptions
        )
        result.appLockEnabled = security.appLockEnabled
        result.autoLockSeconds = security.autoLockSeconds
        result.revealAuthEnabled = security.revealAuthEnabled
        result.clipboardClearEnabled = security.clipboardClearEnabled
        result.clipboardClearSeconds = security.clipboardClearSeconds
        result.clipboardLocalOnly = security.clipboardLocalOnly
        result.hideInAppSwitcher = security.hideInAppSwitcher
        return result
    }

    /// 条件核对与保存同属一个无挂起点的仓库操作；不能用服务层先 load 再 update 代替。
    /// Returns the effective app-lock armed state from the exact rows that were
    /// committed, so callers can update the cold-launch cache without a second
    /// fallible read after the transaction has already succeeded.
    @discardableResult
    func update(
        _ patch: PreferencesPatch,
        expectedCurrentPolicy: RevealPolicy? = nil,
        committing: PreferencesCommit = { operation in try operation() }
    ) throws -> Bool {
        // 条件写入也必须先看到其它上下文已经落盘的最新策略，否则会误过 stale 校验。
        modelContext.rollback()
        var models = try fetchSingletons()
        if let expected = expectedCurrentPolicy {
            let current = models.isEmpty
                ? RevealPolicy.biometricOrPasscode
                : Self.conservativeSecurity(in: models).revealPolicy
            guard RevealPolicyPersistence.canonical(current) == RevealPolicyPersistence.canonical(expected) else {
                throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "stale_page_request")
            }
        }
        do {
            try committing {
                if models.isEmpty {
                    let created = UserPreferences()
                    modelContext.insert(created)
                    models = [created]
                }
                for model in models {
                    Self.apply(patch, to: model)
                }
                try modelContext.save()
            }
        } catch {
            // A revoked commit must not leave dirty registered models that a later
            // unrelated save could accidentally persist.
            modelContext.rollback()
            throw error
        }
        let security = Self.conservativeSecurity(in: models)
        return security.appLockEnabled
            && RevealPolicyPersistence.canonical(security.revealPolicy) != .noVerification
    }

    func pruneDuplicateIdentities() throws {
        // 13.5：无 `updatedAt`，按指纹物理删可能留下错误设置组合。
        // 读取仍折叠、写入仍打全；有可靠版本时间或 replicaSeed 之前 MUST NOT 删行。
    }

    private func persistCanonicalRevealPolicies(on models: [UserPreferences]) {
        let originals = models.map(\.revealPolicy)
        let attempt = RevealPolicyCanonicalPersist.persistIfNeeded(storedRawValues: originals) { next in
            for (model, raw) in zip(models, next) {
                model.revealPolicy = raw
            }
            try modelContext.save()
        }
        if !attempt.didPersist {
            for (model, original) in zip(models, originals) {
                model.revealPolicy = original
            }
        }
    }

    /// CloudKit may temporarily materialize more than one row for the singleton.
    /// Without a revision/timestamp there is no honest last-writer decision. For
    /// the security fields only, fail closed and heal every replica to the most
    /// conservative combination; a later explicit settings update still writes
    /// every row and can intentionally lower the policy after authentication.
    private func persistConservativeSecurity(
        _ security: ConservativeSecurity,
        on models: [UserPreferences]
    ) {
        let needsWrite = models.contains { model in
            model.appLockEnabled != security.appLockEnabled
                || model.autoLockSeconds != security.autoLockSeconds
                || RevealPolicyPersistence.resolve(model.revealPolicy).policy != security.revealPolicy
                || model.revealAuthEnabled != security.revealAuthEnabled
                || model.clipboardClearEnabled != security.clipboardClearEnabled
                || model.clipboardClearSeconds != security.clipboardClearSeconds
                || model.clipboardLocalOnly != security.clipboardLocalOnly
                || model.hideInAppSwitcher != security.hideInAppSwitcher
        }
        guard needsWrite else { return }
        for model in models {
            model.appLockEnabled = security.appLockEnabled
            model.autoLockSeconds = security.autoLockSeconds
            model.revealPolicy = security.revealPolicy.rawValue
            model.revealAuthEnabled = security.revealAuthEnabled
            model.clipboardClearEnabled = security.clipboardClearEnabled
            model.clipboardClearSeconds = security.clipboardClearSeconds
            model.clipboardLocalOnly = security.clipboardLocalOnly
            model.hideInAppSwitcher = security.hideInAppSwitcher
        }
        do {
            try modelContext.save()
        } catch {
            // Runtime result remains fail-closed. Roll back the failed healing
            // write so a later explicit update starts from the persisted rows.
            modelContext.rollback()
            Self.logger.error("Failed to heal duplicate security preference replicas")
        }
    }

    private func fetchSingletons() throws -> [UserPreferences] {
        let id = UserPreferences.singletonID
        return try modelContext.fetch(FetchDescriptor<UserPreferences>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    private static func dto(
        from model: UserPreferences,
        revealPolicy: RevealPolicy,
        autoLockOptions: [Int],
        clipboardOptions: [Int]
    ) -> PreferencesDTO {
        PreferencesDTO(
            appLockEnabled: model.appLockEnabled,
            autoLockSeconds: model.autoLockSeconds,
            autoLockDurationOptions: autoLockOptions,
            revealPolicy: revealPolicy,
            revealAuthEnabled: model.revealAuthEnabled,
            clipboardClearEnabled: model.clipboardClearEnabled,
            clipboardClearSeconds: model.clipboardClearSeconds,
            clipboardClearDurationOptions: clipboardOptions,
            clipboardLocalOnly: model.clipboardLocalOnly,
            hideInAppSwitcher: model.hideInAppSwitcher,
            refreshIntervalMinutes: model.refreshIntervalMinutes,
            displayCurrency: model.displayCurrency,
            usdToDisplayRate: model.usdToDisplayRate,
            notifyLowBalance: model.notifyLowBalance,
            notifyKeyRevoked: model.notifyKeyRevoked,
            notifyWeeklyDigest: model.notifyWeeklyDigest,
            lowBalanceThreshold: model.lowBalanceThreshold,
            appearance: .system,
            defaultGrouping: .byPlatform,
            assignPickerFilter: .allowShared,
            lastWindowWidth: nil,
            lastWindowHeight: nil,
            platformSectionSort: .nameAscending,
            consumerSectionSort: .nameAscending,
            defaultKeyAvatarSymbol: nil,
            defaultKeyAvatarColor: nil,
            defaultCustomAccountAvatarSymbol: nil,
            defaultCustomAccountAvatarColor: nil,
            defaultCustomToolAvatarSymbol: nil,
            defaultCustomToolAvatarColor: nil
        )
    }

    private static func apply(_ patch: PreferencesPatch, to model: UserPreferences) {
        if let value = patch.appLockEnabled { model.appLockEnabled = value }
        if let value = patch.autoLockSeconds { model.autoLockSeconds = value }
        if let value = patch.autoLockDurationOptions {
            model.autoLockDurationOptionsJSON = DurationOptionList.encode(value)
        }
        if let value = patch.revealPolicy {
            model.revealPolicy = RevealPolicyPersistence.canonical(value).rawValue
        }
        if let value = patch.revealAuthEnabled { model.revealAuthEnabled = value }
        if let value = patch.clipboardClearEnabled { model.clipboardClearEnabled = value }
        if let value = patch.clipboardClearSeconds { model.clipboardClearSeconds = value }
        if let value = patch.clipboardClearDurationOptions {
            model.clipboardClearDurationOptionsJSON = DurationOptionList.encode(value)
        }
        if let value = patch.clipboardLocalOnly { model.clipboardLocalOnly = value }
        if let value = patch.hideInAppSwitcher { model.hideInAppSwitcher = value }
        if let value = patch.refreshIntervalMinutes { model.refreshIntervalMinutes = value }
        if let value = patch.displayCurrency { model.displayCurrency = value }
        if let value = patch.usdToDisplayRate { model.usdToDisplayRate = value }
        if let value = patch.notifyLowBalance { model.notifyLowBalance = value }
        if let value = patch.notifyKeyRevoked { model.notifyKeyRevoked = value }
        if let value = patch.notifyWeeklyDigest { model.notifyWeeklyDigest = value }
        if let value = patch.lowBalanceThreshold { model.lowBalanceThreshold = value }
        // appearance / defaultGrouping / window → DevicePreferences（此处刻意忽略）
    }

    private struct ConservativeSecurity: Sendable {
        var appLockEnabled: Bool
        var autoLockSeconds: Int
        var revealPolicy: RevealPolicy
        var revealAuthEnabled: Bool
        var clipboardClearEnabled: Bool
        var clipboardClearSeconds: Int
        var clipboardLocalOnly: Bool
        var hideInAppSwitcher: Bool
    }

    private static func conservativeSecurity(in models: [UserPreferences]) -> ConservativeSecurity {
        precondition(!models.isEmpty)
        let policies = models.map { RevealPolicyPersistence.resolve($0.revealPolicy).policy }
        let strongestPolicy = policies.max { lhs, rhs in
            let lhsRank = SecurityPolicyChange.rank(lhs)
            let rhsRank = SecurityPolicyChange.rank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.rawValue < rhs.rawValue
        } ?? .biometricOrPasscode
        return ConservativeSecurity(
            appLockEnabled: models.contains(where: \.appLockEnabled),
            autoLockSeconds: models.map(\.autoLockSeconds).min() ?? 0,
            revealPolicy: strongestPolicy,
            revealAuthEnabled: models.contains(where: \.revealAuthEnabled),
            clipboardClearEnabled: models.contains(where: \.clipboardClearEnabled),
            clipboardClearSeconds: models.map(\.clipboardClearSeconds).min() ?? 0,
            clipboardLocalOnly: models.contains(where: \.clipboardLocalOnly),
            hideInAppSwitcher: models.contains(where: \.hideInAppSwitcher)
        )
    }

    private static func rank(_ model: UserPreferences) -> SyncedIdentity.ReplicaRank {
        // Security fields (including their duration-picker preset lists) do not
        // participate in electing the whole-row winner for the remaining
        // preferences. Effective values are merged independently by
        // `conservativeSecurity(in:)`; including security-adjacent fields here
        // would let a stronger policy accidentally choose an unrelated
        // currency/notification payload as well.
        SyncedIdentity.ReplicaRank(
            updatedAt: .distantPast,
            isDeleted: false,
            fingerprint: [
                String(model.refreshIntervalMinutes),
                model.displayCurrency,
                SyncedIdentity.decimalStamp(model.usdToDisplayRate),
                model.notifyLowBalance ? "1" : "0",
                model.notifyKeyRevoked ? "1" : "0",
                model.notifyWeeklyDigest ? "1" : "0",
                SyncedIdentity.decimalStamp(model.lowBalanceThreshold),
            ].joined(separator: "\u{1e}")
        )
    }

    /// FR-061：删除安全偏好单例；下次 `loadOrCreate` 会写入默认值。
    func deleteAllRecords() throws {
        try modelContext.deleteAllRecords(UserPreferences.self)
    }

    private func seededOptions(
        stored: String?,
        current: Int,
        factory: [Int],
        didSeed: inout Bool,
        assign: (String) -> Void
    ) -> [Int] {
        if let decoded = DurationOptionList.decode(stored) {
            return decoded
        }
        let seeded = DurationOptionList.seedIfNeeded(stored: nil, current: current, factory: factory)
        assign(DurationOptionList.encode(seeded))
        didSeed = true
        return seeded
    }
}
