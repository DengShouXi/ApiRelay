import CloudKit
import CoreData
import Foundation

nonisolated enum CloudKitPipelinePhase: String, Sendable, Equatable {
    case setup
    case `import`
    case export
}

nonisolated enum CloudKitExportWaitResult: Sendable, Equatable {
    case succeeded(Date, CloudKitPipelinePhase)
    case failed(String)
    case timedOut
    case nothingPending
    case notMirroring
}

/// Value snapshot extracted synchronously from Core Data's CloudKit event
/// notification. Keeping the Foundation event outside the actor also gives
/// tests a safe way to prove that observation is installed before init returns.
nonisolated struct CloudKitPipelineEventSnapshot: Sendable {
    let phase: CloudKitPipelinePhase
    let succeeded: Bool
    let ended: Bool
    let errorText: String?
    let date: Date
}

/// Owns block-observer tokens without making actor initialization asynchronous.
/// The notification center retains each token; this bag removes them when the
/// monitor is released so test-created monitors do not accumulate observers.
private nonisolated final class CloudKitObservationLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(NotificationCenter, NSObjectProtocol)] = []

    func retain(_ token: NSObjectProtocol, in center: NotificationCenter) {
        lock.lock()
        entries.append((center, token))
        lock.unlock()
    }

    deinit {
        lock.lock()
        let retainedEntries = entries
        entries.removeAll()
        lock.unlock()
        for (center, token) in retainedEntries {
            center.removeObserver(token)
        }
    }
}

/// Synchronously records CloudKit notifications before actor scheduling can
/// delay their consumption. The lock establishes one total order for capture,
/// revision assignment, in-flight state, terminal success, and failure.
///
/// The actor drains the queued events serially for persistence/UI side effects,
/// but erase checkpoints and quiet decisions always read this bridge. A busy
/// actor therefore cannot turn an already captured import into a false quiet
/// window.
private nonisolated final class CloudKitPipelineEventBridge: @unchecked Sendable {
    struct CapturedEvent: Sendable {
        let revision: UInt64
        let event: CloudKitPipelineEventSnapshot
    }

    struct TerminalEvent: Sendable {
        let revision: UInt64
        let result: CloudKitExportWaitResult
    }

    struct State: Sendable {
        let revision: UInt64
        let setupInFlight: Bool
        let importInFlight: Bool
        let exportInFlight: Bool
        let lastTerminal: TerminalEvent?
        let lastFailure: TerminalEvent?

        var hasInFlight: Bool {
            setupInFlight || importInFlight || exportInFlight
        }
    }

    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var setupInFlight = false
    private var importInFlight = false
    private var exportInFlight = false
    private var lastTerminal: TerminalEvent?
    private var lastFailure: TerminalEvent?
    private var pending: [CapturedEvent] = []
    private var drainScheduled = false
    private var drainRequestDelivered = false
    private var drainHandler: (@Sendable () -> Void)?

    /// Returns true only for the transition from no scheduled drain to a
    /// scheduled drain. Later captures join the same ordered queue.
    func capture(_ event: CloudKitPipelineEventSnapshot) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        revision &+= 1
        let captured = CapturedEvent(revision: revision, event: event)

        switch event.phase {
        case .setup: setupInFlight = !event.ended
        case .import: importInFlight = !event.ended
        case .export: exportInFlight = !event.ended
        }

        if event.ended {
            if event.succeeded {
                if !hasInFlightLocked {
                    lastTerminal = TerminalEvent(
                        revision: revision,
                        result: .succeeded(event.date, event.phase)
                    )
                }
            } else {
                let result = CloudKitExportWaitResult.failed(event.errorText ?? "CloudKit")
                let terminal = TerminalEvent(revision: revision, result: result)
                lastTerminal = terminal
                // Never let a later success erase failure evidence from the
                // same checkpoint observation window.
                lastFailure = terminal
            }
        }

        pending.append(captured)
        guard !drainScheduled else { return false }
        drainScheduled = true
        drainRequestDelivered = false
        return true
    }

    func installDrainHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        drainHandler = handler
        let handlerToCall = takeUndeliveredDrainHandlerLocked()
        lock.unlock()
        handlerToCall?()
    }

    func deliverDrainRequestIfNeeded() {
        lock.lock()
        let handlerToCall = takeUndeliveredDrainHandlerLocked()
        lock.unlock()
        handlerToCall?()
    }

    /// Pops in capture order. Emptying and clearing `drainScheduled` happen
    /// under the same lock, so a concurrent capture either joins this drain or
    /// schedules exactly one successor drain.
    func nextCapturedEvent() -> CapturedEvent? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else {
            drainScheduled = false
            drainRequestDelivered = false
            return nil
        }
        return pending.removeFirst()
    }

    func state() -> State {
        lock.lock()
        defer { lock.unlock() }
        return State(
            revision: revision,
            setupInFlight: setupInFlight,
            importInFlight: importInFlight,
            exportInFlight: exportInFlight,
            lastTerminal: lastTerminal,
            lastFailure: lastFailure
        )
    }

    private var hasInFlightLocked: Bool {
        setupInFlight || importInFlight || exportInFlight
    }

    private func takeUndeliveredDrainHandlerLocked() -> (@Sendable () -> Void)? {
        guard drainScheduled,
              !drainRequestDelivered,
              let drainHandler else { return nil }
        drainRequestDelivered = true
        return drainHandler
    }
}

/// Owns the raw notification observer independently of the monitor actor. The
/// production instance is installed before SwiftData creates the mirrored
/// container, so setup/import events can be buffered before the composition
/// root constructs `CloudKitSyncMonitor`.
nonisolated final class CloudKitPipelineObservation: @unchecked Sendable {
    fileprivate let bridge: CloudKitPipelineEventBridge
    private let lifetime = CloudKitObservationLifetime()

    init(
        notificationCenter: NotificationCenter,
        pipelineEventDecoder: @escaping @Sendable (Notification) -> CloudKitPipelineEventSnapshot?
    ) {
        let bridge = CloudKitPipelineEventBridge()
        self.bridge = bridge
        let token = notificationCenter.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let event = pipelineEventDecoder(notification) else { return }
            let needsDrain = bridge.capture(event)

            // Security-policy fencing needs the import-start edge at capture
            // time, not after actor scheduling. The payload is already
            // detached from Core Data and contains no record data.
            if event.phase == .import {
                notificationCenter.post(
                    name: .apiRelayCloudSecurityPolicyRefreshRequired,
                    object: event
                )
            }

            if needsDrain {
                bridge.deliverDrainRequestIfNeeded()
            }
        }
        lifetime.retain(token, in: notificationCenter)
    }

    var capturedRevision: UInt64 { bridge.state().revision }
    var importInFlight: Bool { bridge.state().importInFlight }
}

nonisolated struct CloudKitPipelineBootstrapState: Sendable, Equatable {
    let revision: UInt64
    let importInFlight: Bool
}

/// Data 层：账号状态 + CloudKit 导入/导出事件。UI MUST NOT 直接听这些通知。
protocol CloudKitSyncMonitoring: Actor {
    nonisolated var mirroringEnabled: Bool { get }
    func accountState() async -> CloudAccountState
    func userRecordName() async -> String?
    func activity() async -> CloudSyncActivity
    func lastSuccessAt() async -> Date?
    func lastFailureMessage() async -> String?
    func lastFailureAt() async -> Date?
    func hasInFlightActivity() async -> Bool
    /// Monotonic in-process checkpoint for setup/import/export notifications.
    /// A caller can take this before a storage sweep, then atomically consume
    /// a terminal event that completed before its waiter was registered.
    func pipelineRevision() async -> UInt64
    func waitForCloudActivity(grace: Duration, activeTimeout: Duration) async -> CloudKitExportWaitResult
    func waitForCloudActivity(
        after revision: UInt64,
        grace: Duration,
        activeTimeout: Duration
    ) async -> CloudKitExportWaitResult
}

extension CloudKitSyncMonitoring {
    /// Compatibility for simple fakes and non-checkpoint-aware monitors.
    /// Production `CloudKitSyncMonitor` overrides both methods.
    func pipelineRevision() async -> UInt64 { 0 }

    func waitForCloudActivity(
        after revision: UInt64,
        grace: Duration,
        activeTimeout: Duration
    ) async -> CloudKitExportWaitResult {
        _ = revision
        return await waitForCloudActivity(
            grace: grace,
            activeTimeout: activeTimeout
        )
    }
}

actor CloudKitSyncMonitor: CloudKitSyncMonitoring {
    nonisolated static let lastSuccessDefaultsKey = "ApiRelay.cloudKit.lastSuccessAt"
    nonisolated static let lastFailureDefaultsKey = "ApiRelay.cloudKit.lastFailureMessage"
    nonisolated static let lastFailureAtDefaultsKey = "ApiRelay.cloudKit.lastFailureAt"
    nonisolated static let lastFailurePhaseDefaultsKey = "ApiRelay.cloudKit.lastFailurePhase"

    /// Lazily created but explicitly forced by
    /// `prepareForCloudKitContainerBootstrap()` before ModelContainer startup.
    nonisolated private static let processPipelineObservation = CloudKitPipelineObservation(
        notificationCenter: .default,
        pipelineEventDecoder: CloudKitSyncMonitor.decodePipelineEvent
    )

    /// MUST run before `AppSchema.makeProductionContainer()`. Events captured
    /// before the monitor actor exists remain ordered in the process bridge and
    /// are drained when the monitor attaches.
    nonisolated static func prepareForCloudKitContainerBootstrap() {
        _ = processPipelineObservation
    }

    /// Lets a security fence initialized after ModelContainer startup detect a
    /// pre-monitor import start even if its synchronous notification was early.
    nonisolated static func processPipelineBootstrapState() -> CloudKitPipelineBootstrapState {
        CloudKitPipelineBootstrapState(
            revision: processPipelineObservation.capturedRevision,
            importInFlight: processPipelineObservation.importInFlight
        )
    }

    nonisolated let mirroringEnabled: Bool
    private let containerIdentifier: String
    private let defaults: UserDefaults
    private let observationLifetime: CloudKitObservationLifetime
    private let pipelineObservation: CloudKitPipelineObservation
    private let beforePipelineDrain: @Sendable () async -> Void

    private var cachedAccount: CloudAccountState = .unknown
    private var cachedUserRecordName: String?
    private var setupInFlight = false
    private var importInFlight = false
    private var exportInFlight = false
    private var waiters: [UUID: Waiter] = [:]

    /// 管道事件。超时在 `waitForCloudActivity` 的 task group 里赛跑，不在同步方法里起 `Task`。
    private enum WaiterEvent: Sendable {
        case activityStarted(UInt64)
        case finished(UInt64, CloudKitExportWaitResult)
        case abandoned
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
                parked.resume(returning: .abandoned)
            }
        }
    }

    init(
        mirroringEnabled: Bool,
        containerIdentifier: String = AppSchema.cloudKitContainerID,
        defaults: UserDefaults = AppRuntime.userDefaultsForCurrentRuntime(),
        notificationCenter: NotificationCenter = .default,
        pipelineEventDecoder: @escaping @Sendable (Notification) -> CloudKitPipelineEventSnapshot? =
            CloudKitSyncMonitor.decodePipelineEvent,
        pipelineObservation: CloudKitPipelineObservation? = nil,
        beforePipelineDrain: @escaping @Sendable () async -> Void = {}
    ) {
        if AppRuntime.isRunningTests, defaults === UserDefaults.standard {
            preconditionFailure(
                "CloudKitSyncMonitor: 测试禁止使用 UserDefaults.standard。请注入 AppRuntime.userDefaultsForCurrentRuntime() 或独立 suite。"
            )
        }
        self.mirroringEnabled = mirroringEnabled
        self.containerIdentifier = containerIdentifier
        self.defaults = defaults
        let pipelineObservation = pipelineObservation ?? {
            if AppRuntime.isRunningTests {
                return CloudKitPipelineObservation(
                    notificationCenter: notificationCenter,
                    pipelineEventDecoder: pipelineEventDecoder
                )
            }
            return Self.processPipelineObservation
        }()
        self.pipelineObservation = pipelineObservation
        self.beforePipelineDrain = beforePipelineDrain
        let observationLifetime = CloudKitObservationLifetime()
        self.observationLifetime = observationLifetime

        let account = notificationCenter.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshAccount() }
        }
        observationLifetime.retain(account, in: notificationCenter)

        // A pre-monitor capture may already be queued. Attaching the handler
        // synchronously schedules exactly one serial drain for that queue.
        pipelineObservation.bridge.installDrainHandler { [weak self] in
            guard let self else { return }
            Task { await self.drainCapturedPipelineEvents() }
        }

        // XCTest 宿主可能没有 CloudKit entitlement；直接创建 CKContainer 会触发系统崩溃，
        // 而测试通过注入 / applyPipelineEvent 验证状态机，不需要访问真实账号。
        if !AppRuntime.isRunningTests {
            Task { await self.refreshAccount() }
        }
    }

    func accountState() async -> CloudAccountState {
        cachedAccount
    }

    func userRecordName() async -> String? {
        cachedUserRecordName
    }

    func activity() async -> CloudSyncActivity {
        let state = pipelineObservation.bridge.state()
        if state.exportInFlight { return .exporting }
        if state.importInFlight { return .importing }
        if state.setupInFlight { return .settingUp }
        return .idle
    }

    func lastSuccessAt() async -> Date? {
        persistedSuccess()
    }

    func lastFailureMessage() async -> String? {
        defaults.string(forKey: Self.lastFailureDefaultsKey)
    }

    func lastFailureAt() async -> Date? {
        let interval = defaults.double(forKey: Self.lastFailureAtDefaultsKey)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func hasInFlightActivity() async -> Bool {
        pipelineObservation.bridge.state().hasInFlight
    }

    func pipelineRevision() async -> UInt64 {
        pipelineObservation.bridge.state().revision
    }

    func waitForCloudActivity(
        after revision: UInt64,
        grace: Duration,
        activeTimeout: Duration
    ) async -> CloudKitExportWaitResult {
        if !mirroringEnabled { return .notMirroring }
        return await waitForCapturedCloudActivity(
            after: revision,
            grace: grace,
            activeTimeout: activeTimeout
        )
    }

    func waitForCloudActivity(grace: Duration, activeTimeout: Duration) async -> CloudKitExportWaitResult {
        if !mirroringEnabled { return .notMirroring }

        // The non-checkpoint API waits only for activity captured from now on,
        // while still honoring an operation that is already in flight.
        let baseline = pipelineObservation.bridge.state().revision
        return await waitForCapturedCloudActivity(
            after: baseline,
            grace: grace,
            activeTimeout: activeTimeout
        )
    }

    private func waitForCapturedCloudActivity(
        after baselineRevision: UInt64,
        grace: Duration,
        activeTimeout: Duration
    ) async -> CloudKitExportWaitResult {
        var capturedState = pipelineObservation.bridge.state()
        if let completion = capturedCompletion(
            after: baselineRevision,
            state: capturedState
        ) {
            return completion
        }

        let id = UUID()
        waiters[id] = Waiter(
            observedActivity: capturedState.hasInFlight || capturedState.revision > baselineRevision
        )
        defer { waiters.removeValue(forKey: id) }

        var slice = capturedState.hasInFlight ? activeTimeout : grace

        // Capture can run on another thread while this actor registers the
        // waiter. Re-read after registration; timeout also re-reads, so there
        // is no unchecked gap even if actor delivery is delayed.
        capturedState = pipelineObservation.bridge.state()
        if let completion = capturedCompletion(
            after: baselineRevision,
            state: capturedState
        ) {
            return completion
        }
        if capturedState.hasInFlight {
            waiters[id]?.observedActivity = true
            slice = activeTimeout
        }

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
                    let event = await withTaskCancellationHandler {
                        await self.nextWaiterEvent(id)
                    } onCancel: {
                        // `CheckedContinuation` is not cancellation-aware. If
                        // the timer wins, wake this losing child so structured
                        // task-group teardown cannot wait forever.
                        Task { await self.abandonWaiter(id) }
                    }
                    return Race.event(event)
                }
                let first = await group.next()!
                group.cancelAll()
                return first
            }

            capturedState = pipelineObservation.bridge.state()
            if let completion = capturedCompletion(
                after: baselineRevision,
                state: capturedState
            ) {
                return completion
            }

            switch raced {
            case .event(.finished(let revision, let result)):
                if capturedState.hasInFlight {
                    waiters[id]?.observedActivity = true
                    slice = activeTimeout
                } else if revision > baselineRevision {
                    return result
                }
                // A delayed drain may deliver a pre-baseline terminal event.
                // Ignore it and keep waiting for this observation window.
            case .event(.activityStarted(let revision)):
                if revision > baselineRevision || capturedState.hasInFlight {
                    waiters[id]?.observedActivity = true
                    slice = activeTimeout
                }
            case .event(.abandoned):
                return timeoutOutcome(id, after: baselineRevision)
            case .tick:
                waiters[id]?.abandon()
                return timeoutOutcome(id, after: baselineRevision)
            }
        }
        waiters[id]?.abandon()
        return .timedOut
    }

    /// 单测入口：同步 capture 后等待串行消费完成。
    func applyPipelineEvent(
        phase: CloudKitPipelinePhase,
        succeeded: Bool,
        ended: Bool,
        errorText: String?,
        date: Date
    ) async {
        _ = pipelineObservation.bridge.capture(
            CloudKitPipelineEventSnapshot(
                phase: phase,
                succeeded: succeeded,
                ended: ended,
                errorText: errorText,
                date: date
            )
        )
        await drainCapturedPipelineEvents()
    }

    private func drainCapturedPipelineEvents() async {
        // Tests can hold this gate to prove that capture-time state, rather
        // than actor-consumption timing, controls erase convergence.
        await beforePipelineDrain()
        while let captured = pipelineObservation.bridge.nextCapturedEvent() {
            consumeCapturedPipelineEvent(captured)
        }
    }

    private func consumeCapturedPipelineEvent(
        _ captured: CloudKitPipelineEventBridge.CapturedEvent
    ) {
        let event = captured.event
        let phase = event.phase
        switch phase {
        case .setup: setupInFlight = !event.ended
        case .import: importInFlight = !event.ended
        case .export: exportInFlight = !event.ended
        }

        if !event.ended {
            signalActivityStarted(revision: captured.revision)
            return
        }

        if event.succeeded {
            defaults.set(event.date.timeIntervalSince1970, forKey: Self.lastSuccessDefaultsKey)
            // 只有同一阶段的后续成功才能关闭该阶段的失败；import 成功不能掩盖 export 失败。
            if defaults.string(forKey: Self.lastFailurePhaseDefaultsKey) == phase.rawValue {
                defaults.removeObject(forKey: Self.lastFailureDefaultsKey)
                defaults.removeObject(forKey: Self.lastFailureAtDefaultsKey)
                defaults.removeObject(forKey: Self.lastFailurePhaseDefaultsKey)
            }
            if phase == .import {
                NotificationCenter.default.post(name: .apiRelayCloudMetadataDidImport, object: nil)
            }
            if !hasInFlight {
                resumeAll(
                    .succeeded(event.date, phase),
                    revision: captured.revision
                )
            }
        } else {
            let message = event.errorText ?? "CloudKit"
            persistFailure(message, phase: phase, date: event.date)
            let result = CloudKitExportWaitResult.failed(message)
            resumeAll(result, revision: captured.revision)
        }
    }

    func refreshAccount() async {
        let result: Result<CKAccountStatus, NSError> = await withCheckedContinuation { continuation in
            CKContainer(identifier: containerIdentifier).accountStatus { status, error in
                if let error {
                    continuation.resume(returning: .failure(error as NSError))
                } else {
                    continuation.resume(returning: .success(status))
                }
            }
        }
        guard case .success(let status) = result else {
            cachedAccount = .unknown
            cachedUserRecordName = nil
            if case .failure(let error) = result {
                persistFailure(Self.diagnosticMessage(for: error), phase: .setup, date: Date())
            }
            return
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

    private func persistedSuccess() -> Date? {
        let interval = defaults.double(forKey: Self.lastSuccessDefaultsKey)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func persistFailure(_ message: String, phase: CloudKitPipelinePhase, date: Date) {
        defaults.set(message, forKey: Self.lastFailureDefaultsKey)
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastFailureAtDefaultsKey)
        defaults.set(phase.rawValue, forKey: Self.lastFailurePhaseDefaultsKey)
    }

    nonisolated private static func decodePipelineEvent(
        _ notification: Notification
    ) -> CloudKitPipelineEventSnapshot? {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else { return nil }
        let phase: CloudKitPipelinePhase?
        switch event.type {
        case .setup: phase = .setup
        case .import: phase = .import
        case .export: phase = .export
        @unknown default: phase = nil
        }
        guard let phase else { return nil }
        return CloudKitPipelineEventSnapshot(
            phase: phase,
            succeeded: event.succeeded,
            ended: event.endDate != nil,
            errorText: event.error.map(Self.diagnosticMessage(for:)),
            date: event.endDate ?? Date()
        )
    }

    private func fetchUserRecordName() async -> String? {
        await withCheckedContinuation { continuation in
            CKContainer(identifier: containerIdentifier).fetchUserRecordID { recordID, _ in
                continuation.resume(returning: recordID?.recordName)
            }
        }
    }

    private func nextWaiterEvent(_ id: UUID) async -> WaiterEvent {
        guard let waiter = waiters[id] else { return .abandoned }
        return await waiter.next()
    }

    private func abandonWaiter(_ id: UUID) {
        waiters[id]?.abandon()
    }

    private func signalActivityStarted(revision: UInt64) {
        for waiter in waiters.values where !waiter.observedActivity {
            waiter.observedActivity = true
            waiter.yield(.activityStarted(revision))
        }
    }

    private func capturedCompletion(
        after revision: UInt64,
        state: CloudKitPipelineEventBridge.State
    ) -> CloudKitExportWaitResult? {
        if let failure = state.lastFailure,
           failure.revision > revision {
            return failure.result
        }
        if state.hasInFlight { return nil }
        if let terminal = state.lastTerminal,
           terminal.revision > revision {
            return terminal.result
        }
        return nil
    }

    private func timeoutOutcome(
        _ id: UUID,
        after revision: UInt64
    ) -> CloudKitExportWaitResult {
        let state = pipelineObservation.bridge.state()
        if let completion = capturedCompletion(after: revision, state: state) {
            return completion
        }
        if state.hasInFlight { return .timedOut }
        let observed = (waiters[id]?.observedActivity ?? false) || state.revision > revision
        return observed ? .timedOut : .nothingPending
    }

    private func resumeAll(_ result: CloudKitExportWaitResult, revision: UInt64) {
        for waiter in Array(waiters.values) {
            waiter.yield(.finished(revision, result))
        }
    }

    /// `CKError.partialFailure` 的外层描述只有“错误 2”；这里展开逐条子错误，但不记录 record ID。
    nonisolated static func diagnosticMessage(for error: Error) -> String {
        let leaves = leafErrors(in: error as NSError)
        var unique: [String] = []
        for leaf in leaves {
            let marker = "\(leaf.domain) \(leaf.code)"
            let description = leaf.localizedDescription
            let item = description.contains(marker) ? description : "\(description) [\(marker)]"
            if !unique.contains(item) { unique.append(item) }
        }
        let shown = unique.prefix(3).joined(separator: "；")
        let omitted = max(0, unique.count - 3)
        return omitted == 0 ? shown : "\(shown)；另有 \(omitted) 类错误"
    }

    nonisolated private static func leafErrors(in error: NSError, depth: Int = 0) -> [NSError] {
        guard depth < 6 else { return [error] }
        var children: [NSError] = []
        if let partial = error.userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary {
            children += partial.allValues.compactMap { $0 as? NSError }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            children.append(underlying)
        }
        guard !children.isEmpty else { return [error] }
        return children.flatMap { leafErrors(in: $0, depth: depth + 1) }
    }
}

extension Notification.Name {
    /// Posted synchronously when a raw import notification is captured. The
    /// object is `CloudKitPipelineEventSnapshot`; security fences use start to
    /// revoke leases and successful end to schedule a policy reload.
    nonisolated static let apiRelayCloudSecurityPolicyRefreshRequired =
        Notification.Name("ApiRelay.cloudSecurityPolicyRefreshRequired")

    /// 业务 UI 只听这个脱敏后的语义事件，不直接依赖 Core Data / CloudKit 通知。
    nonisolated static let apiRelayCloudMetadataDidImport = Notification.Name("ApiRelay.cloudMetadataDidImport")
}
