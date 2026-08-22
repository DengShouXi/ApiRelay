import CloudKit
import CoreData
import Foundation

enum CloudKitPipelinePhase: Sendable, Equatable {
    case setup
    case `import`
    case export
}

enum CloudKitExportWaitResult: Sendable, Equatable {
    case succeeded(Date)
    case failed(String)
    case timedOut
    case nothingPending
    case notMirroring
}

/// Data 层：账号状态 + CloudKit 导入/导出事件。UI MUST NOT 直接听这些通知。
protocol CloudKitSyncMonitoring: Actor {
    nonisolated var mirroringEnabled: Bool { get }
    func accountState() async -> CloudAccountState
    func userRecordName() async -> String?
    func activity() async -> CloudSyncActivity
    func lastSuccessAt() async -> Date?
    func lastFailureMessage() async -> String?
    func hasInFlightActivity() async -> Bool
    func waitForCloudActivity(grace: Duration, activeTimeout: Duration) async -> CloudKitExportWaitResult
}

actor CloudKitSyncMonitor: CloudKitSyncMonitoring {
    nonisolated static let lastSuccessDefaultsKey = "ApiRelay.cloudKit.lastSuccessAt"
    nonisolated static let lastFailureDefaultsKey = "ApiRelay.cloudKit.lastFailureMessage"

    nonisolated let mirroringEnabled: Bool
    private let containerIdentifier: String
    private let defaults: UserDefaults

    private var started = false
    private var cachedAccount: CloudAccountState = .unknown
    private var cachedUserRecordName: String?
    private var setupInFlight = false
    private var importInFlight = false
    private var exportInFlight = false
    private var waiters: [UUID: Waiter] = [:]
    private var observerTokens: [NSObjectProtocol] = []

    /// 管道事件。超时在 `waitForCloudActivity` 的 task group 里赛跑，不在同步方法里起 `Task`。
    private enum WaiterEvent: Sendable {
        case activityStarted
        case finished(CloudKitExportWaitResult)
    }

    private final class Waiter {
        var observedActivity: Bool
        private var pending: [WaiterEvent] = []
        private var parked: CheckedContinuation<WaiterEvent, Never>?

        init(observedActivity: Bool) {
            self.observedActivity = observedActivity
        }

        func yield(_ event: WaiterEvent) {
            if let parked {
                self.parked = nil
                parked.resume(returning: event)
            } else {
                pending.append(event)
            }
        }

        func next() async -> WaiterEvent {
            if !pending.isEmpty {
                return pending.removeFirst()
            }
            return await withCheckedContinuation { continuation in
                parked = continuation
            }
        }

        func abandon() {
            if let parked {
                self.parked = nil
                parked.resume(returning: .finished(.timedOut))
            }
        }
    }

    init(
        mirroringEnabled: Bool,
        containerIdentifier: String = AppSchema.cloudKitContainerID,
        defaults: UserDefaults = .standard
    ) {
        self.mirroringEnabled = mirroringEnabled
        self.containerIdentifier = containerIdentifier
        self.defaults = defaults
        Task { await self.start() }
    }

    func start() async {
        guard !started else { return }
        started = true
        observeNotifications()
        await refreshAccount()
    }

    func accountState() async -> CloudAccountState {
        cachedAccount
    }

    func userRecordName() async -> String? {
        cachedUserRecordName
    }

    func activity() async -> CloudSyncActivity {
        currentActivity()
    }

    func lastSuccessAt() async -> Date? {
        persistedSuccess()
    }

    func lastFailureMessage() async -> String? {
        defaults.string(forKey: Self.lastFailureDefaultsKey)
    }

    func hasInFlightActivity() async -> Bool {
        hasInFlight
    }

    func waitForCloudActivity(grace: Duration, activeTimeout: Duration) async -> CloudKitExportWaitResult {
        if !mirroringEnabled { return .notMirroring }

        let id = UUID()
        waiters[id] = Waiter(observedActivity: hasInFlight)
        defer { waiters.removeValue(forKey: id) }

        var slice = hasInFlight ? activeTimeout : grace

        while !Task.isCancelled {
            enum Race: Sendable {
                case tick
                case event(WaiterEvent)
            }

            let sleepFor = slice
            let raced = await withTaskGroup(of: Race.self) { group in
                group.addTask {
                    try? await Task.sleep(for: sleepFor)
                    return Race.tick
                }
                group.addTask {
                    let event = await self.nextWaiterEvent(id)
                    return Race.event(event)
                }
                let first = await group.next()!
                group.cancelAll()
                return first
            }

            switch raced {
            case .event(.finished(let result)):
                return result
            case .event(.activityStarted):
                slice = activeTimeout
            case .tick:
                waiters[id]?.abandon()
                return timeoutOutcome(id)
            }
        }
        waiters[id]?.abandon()
        return .timedOut
    }

    /// 单测 / 通知回调共用：把一次 CloudKit 管道事件收进状态机。
    func applyPipelineEvent(
        phase: CloudKitPipelinePhase,
        succeeded: Bool,
        ended: Bool,
        errorText: String?,
        date: Date
    ) {
        switch phase {
        case .setup: setupInFlight = !ended
        case .import: importInFlight = !ended
        case .export: exportInFlight = !ended
        }

        if !ended {
            signalActivityStarted()
            return
        }

        if succeeded {
            defaults.set(date.timeIntervalSince1970, forKey: Self.lastSuccessDefaultsKey)
            defaults.removeObject(forKey: Self.lastFailureDefaultsKey)
            if !hasInFlight {
                resumeAll(.succeeded(date))
            }
        } else {
            let message = errorText ?? "CloudKit"
            defaults.set(message, forKey: Self.lastFailureDefaultsKey)
            resumeAll(.failed(message))
        }
    }

    func refreshAccount() async {
        let status: CKAccountStatus = await withCheckedContinuation { continuation in
            CKContainer(identifier: containerIdentifier).accountStatus { status, _ in
                continuation.resume(returning: status)
            }
        }
        cachedAccount = Self.mapAccountStatus(status)
        if status == .available {
            cachedUserRecordName = await fetchUserRecordName()
        } else {
            cachedUserRecordName = nil
        }
    }

    nonisolated static func mapAccountStatus(_ status: CKAccountStatus) -> CloudAccountState {
        switch status {
        case .available: return .signedIn
        case .noAccount: return .signedOut
        case .restricted: return .restricted
        case .temporarilyUnavailable: return .temporarilyUnavailable
        case .couldNotDetermine: return .unknown
        @unknown default: return .unknown
        }
    }

    private var hasInFlight: Bool {
        setupInFlight || importInFlight || exportInFlight
    }

    private func currentActivity() -> CloudSyncActivity {
        if exportInFlight { return .exporting }
        if importInFlight { return .importing }
        if setupInFlight { return .settingUp }
        return .idle
    }

    private func persistedSuccess() -> Date? {
        let interval = defaults.double(forKey: Self.lastSuccessDefaultsKey)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func observeNotifications() {
        let pipeline = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            let phase: CloudKitPipelinePhase?
            switch event.type {
            case .setup: phase = .setup
            case .import: phase = .import
            case .export: phase = .export
            @unknown default: phase = nil
            }
            guard let phase else { return }
            let succeeded = event.succeeded
            let ended = event.endDate != nil
            let errorText = event.error?.localizedDescription
            let date = event.endDate ?? Date()
            Task { await self.applyPipelineEvent(
                phase: phase,
                succeeded: succeeded,
                ended: ended,
                errorText: errorText,
                date: date
            ) }
        }
        let account = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshAccount() }
        }
        observerTokens.append(pipeline)
        observerTokens.append(account)
    }

    private func fetchUserRecordName() async -> String? {
        await withCheckedContinuation { continuation in
            CKContainer(identifier: containerIdentifier).fetchUserRecordID { recordID, _ in
                continuation.resume(returning: recordID?.recordName)
            }
        }
    }

    private func nextWaiterEvent(_ id: UUID) async -> WaiterEvent {
        guard let waiter = waiters[id] else { return .finished(.timedOut) }
        return await waiter.next()
    }

    private func signalActivityStarted() {
        for waiter in waiters.values where !waiter.observedActivity {
            waiter.observedActivity = true
            waiter.yield(.activityStarted)
        }
    }

    private func timeoutOutcome(_ id: UUID) -> CloudKitExportWaitResult {
        let observed = waiters[id]?.observedActivity ?? false
        if hasInFlight { return .timedOut }
        if observed, let date = persistedSuccess() { return .succeeded(date) }
        return observed ? .timedOut : .nothingPending
    }

    private func resumeAll(_ result: CloudKitExportWaitResult) {
        for waiter in Array(waiters.values) {
            waiter.yield(.finished(result))
        }
    }
}
