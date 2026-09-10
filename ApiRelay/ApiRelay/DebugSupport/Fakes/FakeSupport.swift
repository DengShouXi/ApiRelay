#if DEBUG
import Foundation

/// 假实现共用的记事本：记下每个方法被调了几次，并允许把指定方法改成抛错。
///
/// 「调了几次」用来断言那些**不该发生**的事，例如遮罩不得读明文、
/// 自动刷新不得走门闩——这类要求只看返回值验不出来。
/// 「改成抛错」用来走失败路径；生产实现里这些失败要么难复现，要么得真断网。
nonisolated struct FakeJournal: Sendable {
    private(set) var calls: [String] = []
    private var programmedErrors: [String: ApiRelayError] = [:]

    /// 记一次调用；若该方法被安排了错误则抛出。错误不会用完即弃，
    /// 需显式 `clearFailure` 才恢复，避免「只错第一次」这种半真半假的状态。
    mutating func record(_ method: String) throws {
        calls.append(method)
        if let error = programmedErrors[method] { throw error }
    }

    /// 无抛出版本，供 `async` 但不 `throws` 的方法使用。
    mutating func recordNonThrowing(_ method: String) {
        calls.append(method)
    }

    mutating func fail(_ method: String, with error: ApiRelayError) {
        programmedErrors[method] = error
    }

    mutating func clearFailure(_ method: String) {
        programmedErrors.removeValue(forKey: method)
    }

    mutating func reset() {
        calls.removeAll()
        programmedErrors.removeAll()
    }

    func callCount(_ method: String) -> Int {
        calls.filter { $0 == method }.count
    }

    func didCall(_ method: String) -> Bool {
        callCount(method) > 0
    }
}

// MARK: - 样例数据

extension PreferencesDTO {
    /// 与 `UserPreferences` / `DevicePreferences` 的建模默认值一致的一份偏好。
    /// 假实现以它作为起点，测试只需覆盖关心的那几个字段。
    nonisolated static func fakeDefault() -> PreferencesDTO {
        PreferencesDTO(
            appLockEnabled: false,
            autoLockSeconds: 60,
            autoLockDurationOptions: DurationOptionList.autoLockFactory,
            revealPolicy: .noVerification,
            clipboardClearEnabled: true,
            clipboardClearSeconds: 120,
            clipboardClearDurationOptions: DurationOptionList.clipboardFactory,
            clipboardLocalOnly: true,
            hideInAppSwitcher: true,
            refreshIntervalMinutes: 60,
            displayCurrency: "USD",
            usdToDisplayRate: nil,
            notifyLowBalance: false,
            notifyKeyRevoked: false,
            notifyWeeklyDigest: false,
            lowBalanceThreshold: nil,
            appearance: .system,
            defaultGrouping: .byPlatform,
            assignPickerFilter: .unassignedOnly,
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

}

extension UpstreamAccountDTO {
    nonisolated static func fake(
        id: UUID = UUID(),
        platform: String = "openai",
        displayName: String = "Fake Account",
        sortOrder: Int = 0,
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil
    ) -> UpstreamAccountDTO {
        UpstreamAccountDTO(
            id: id,
            platform: platform,
            customPlatformName: nil,
            displayName: displayName,
            customBaseURL: nil,
            hasManagementCredential: false,
            notes: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            sortOrder: sortOrder,
            deletedAt: deletedAt,
            purgeAfter: purgeAfter
        )
    }
}

extension ConsumerToolDTO {
    nonisolated static func fake(
        id: UUID = UUID(),
        name: String = "Fake Tool",
        isPreset: Bool = false,
        isHidden: Bool = false,
        sortOrder: Int = 0,
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil
    ) -> ConsumerToolDTO {
        ConsumerToolDTO(
            id: id,
            name: name,
            iconSymbol: nil,
            isPreset: isPreset,
            isHidden: isHidden,
            notes: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            sortOrder: sortOrder,
            deletedAt: deletedAt,
            purgeAfter: purgeAfter
        )
    }
}

extension KeyRecordDTO {
    nonisolated static func fake(
        id: UUID = UUID(),
        accountId: UUID = UUID(),
        consumerToolIds: [UUID] = [],
        displayName: String = "Fake Key",
        lifecycle: KeyLifecycle = .active,
        secretAvailable: Bool = true,
        sortOrder: Int = 0,
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil
    ) -> KeyRecordDTO {
        KeyRecordDTO(
            id: id,
            accountId: accountId,
            consumerToolIds: consumerToolIds,
            displayName: displayName,
            maskedHint: nil,
            origin: .manualEntry,
            providerKeyRef: nil,
            lifecycle: lifecycle,
            health: KeyHealthDTO(state: .unknown, lastCheckedAt: nil, lastCheckNote: nil),
            deletedAt: deletedAt,
            purgeAfter: purgeAfter,
            spendLimit: nil,
            notes: nil,
            secretAvailable: secretAvailable,
            sortOrder: sortOrder
        )
    }
}
#endif
