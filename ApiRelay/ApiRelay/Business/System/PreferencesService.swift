import Foundation
import SwiftData

protocol PreferencesServing: Actor {
    func load() async throws -> PreferencesDTO
    func update(_ patch: PreferencesPatch) async throws
    /// 同步偏好的非阻塞写入。界面与 MainActor 上的控制器 MUST 走这条，
    /// MUST NOT `await update`——那会让主线程干等 CloudKit/SwiftData 落盘。
    nonisolated func persist(_ patch: PreferencesPatch)
    /// FR-061：清空同步偏好与本机偏好；下次 `load` 会重建默认值。
    func purgeAllRecordsForErase() async throws
}

actor PreferencesService: PreferencesServing {
    private let userRepo: UserPreferencesRepository
    private let deviceRepo: DevicePreferencesRepository
    private nonisolated let writeChain = SerialWriteChain()

    init(modelContainer: ModelContainer) {
        self.userRepo = UserPreferencesRepository(modelContainer: modelContainer)
        self.deviceRepo = DevicePreferencesRepository(modelContainer: modelContainer)
    }

    func load() async throws -> PreferencesDTO {
        let user = try await userRepo.loadOrCreate()
        let device = try await deviceRepo.loadOrCreate()
        return PreferencesDTO(
            appLockEnabled: user.appLockEnabled,
            autoLockSeconds: user.autoLockSeconds,
            revealPolicy: user.revealPolicy,
            clipboardClearSeconds: user.clipboardClearSeconds,
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
        // FR-060：外观/默认视角/窗口 → DevicePreferences；其余 → UserPreferences
        if patch.writesUserPreferences {
            try await userRepo.update(patch)
        }
        if patch.writesDevicePreferences {
            try await deviceRepo.update(patch)
        }
    }

    /// 界面写入 CloudKit 同步的 UserPreferences 时，MUST NOT 在 MainActor 上 `await update`。
    /// SwiftUI `.modelContainer` 的 mainContext 与 `@ModelActor` save 互相等待，会卡住整窗转圈。
    /// 立即返回，写入排进串行链：连拨开关时最后一次拨的值一定是最后写进去的那个。
    nonisolated func persist(_ patch: PreferencesPatch) {
        writeChain.append { [weak self] in
            try? await self?.update(patch)
        }
    }

    /// 等到目前排队的 `persist` 全部落盘。测试用；界面 MUST NOT 调用，那就等于又在主线程干等 save。
    nonisolated func drainPendingWrites() async {
        await writeChain.drain()
    }

    /// FR-061：清空同步偏好与本机偏好；下次 `load` 会重建默认值。
    func purgeAllRecordsForErase() async throws {
        try await userRepo.deleteAllRecords()
        try await deviceRepo.deleteAllRecords()
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
