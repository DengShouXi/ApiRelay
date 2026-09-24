@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class StateOwnershipTests: XCTestCase {
    func testTrashBatchSelectionOnlyContainsCurrentlyVisibleCheckedItems() {
        let visibleKey = UUID()
        let hiddenKey = UUID()
        var state = VaultTrashPresentationState()
        state.isSelecting = true
        state.checkedItems = [.key(visibleKey), .key(hiddenKey)]
        state.visibleItems = [.key(visibleKey)]
        XCTAssertEqual(state.actionSelection.keyIds, [visibleKey])
        state.resetSelection()
        XCTAssertFalse(state.isSelecting)
        XCTAssertTrue(state.checkedItems.isEmpty)
        XCTAssertTrue(state.visibleItems.isEmpty)
    }

    func testSettingsCommittedSnapshotCannotOverwriteLaterDraft() {
        var store = SettingsPreferencesStore()
        var committed = PreferencesDTO.fakeDefault()
        committed.revealPolicy = .masterPassword
        let firstReload = store.beginReload()
        XCTAssertTrue(store.completeReload(committed, revision: firstReload))
        XCTAssertEqual(store.presented?.revealPolicy, .masterPassword)

        let staleReload = store.beginReload()
        var draft = committed
        draft.revealPolicy = .biometricOrPasscode
        store.presentDraft(draft)
        XCTAssertFalse(store.completeReload(committed, revision: staleReload))
        XCTAssertEqual(store.presented?.revealPolicy, .biometricOrPasscode)
        XCTAssertEqual(store.committed?.revealPolicy, .masterPassword)

        let confirmedReload = store.beginReload()
        XCTAssertTrue(store.completeReload(draft, revision: confirmedReload))
        XCTAssertNil(store.draft)
        XCTAssertEqual(store.committed?.revealPolicy, .biometricOrPasscode)
    }

    func testOldPreferenceOutcomeCannotOverrideNewRequestOrDraft() {
        let old = SecurityPreferenceNotificationContext(requestRevision: 4, draftRevision: 7)
        let notification = Notification(
            name: .securityPreferencesPersistFailed,
            object: nil,
            userInfo: ["securityPreferenceNotificationContext": old]
        )
        XCTAssertTrue(SecurityPreferenceCommit.isCurrent(
            notification, requestRevision: 4, draftRevision: 7
        ))
        XCTAssertFalse(SecurityPreferenceCommit.isCurrent(
            notification, requestRevision: 5, draftRevision: 7
        ))
        XCTAssertFalse(SecurityPreferenceCommit.isCurrent(
            notification, requestRevision: 4, draftRevision: 8
        ))
    }


    func testSettingsSensitiveActionsAreMutuallyExclusive() {
        var state = SettingsPendingActionState()
        state.setWeakenPatch(PreferencesPatch(appLockEnabled: false))
        XCTAssertNotNil(state.weakenPatch)
        XCTAssertFalse(state.eraseAwaitingIdentity)

        state.setEraseAwaitingIdentity(true)
        XCTAssertNil(state.weakenPatch)
        XCTAssertTrue(state.eraseAwaitingIdentity)

        state.setWeakenPatch(PreferencesPatch(hideInAppSwitcher: false))
        XCTAssertNotNil(state.weakenPatch)
        XCTAssertFalse(state.eraseAwaitingIdentity)

        state.setEraseAwaitingIdentity(false)
        XCTAssertNotNil(state.weakenPatch, "Finishing an old erase must not erase a newer policy action")
        state.clear()
        XCTAssertNil(state.weakenPatch)
        XCTAssertFalse(state.eraseAwaitingIdentity)
    }

    func testSwitchingFromAppPasswordToDeviceRequiresCurrentPolicyAuthorization() {
        var current = PreferencesDTO.fakeDefault()
        current.revealPolicy = .masterPassword
        let patch = PreferencesPatch(revealPolicy: .biometricOrPasscode)
        XCTAssertTrue(SecurityPolicyChange.weakens(patch, relativeTo: current))
        XCTAssertFalse(SecurityPreferenceCommit.appliesMemoryBeforePersist(patch, relativeTo: current))
    }

    func testPolicySelectionRoutesDeviceDirectlyAndAppPasswordThroughItsPage() {
        XCTAssertEqual(
            AppPasswordSettingsRouting.destination(selected: .biometricOrPasscode),
            .persistPolicy(.biometricOrPasscode)
        )
        XCTAssertEqual(
            AppPasswordSettingsRouting.destination(selected: .masterPassword),
            .appPasswordPage(target: .masterPassword)
        )
    }

    func testSecurityPreferenceCallbacksRetainCompletionOrderOnMainThread() async {
        let preferences = ManuallyCompletedPreferences()
        var current = PreferencesDTO.fakeDefault()
        current.revealPolicy = .biometricOrPasscode
        let trace = NotificationTrace()
        let delivered = expectation(description: "both preference outcomes delivered")
        delivered.expectedFulfillmentCount = 2
        let center = NotificationCenter.default
        let successToken = center.addObserver(
            forName: .securityPreferencesDidPersist, object: nil, queue: nil
        ) { _ in
            trace.append("success", onMain: Thread.isMainThread)
            delivered.fulfill()
        }
        let failureToken = center.addObserver(
            forName: .securityPreferencesPersistFailed, object: nil, queue: nil
        ) { _ in
            trace.append("failure", onMain: Thread.isMainThread)
            delivered.fulfill()
        }
        defer {
            center.removeObserver(successToken)
            center.removeObserver(failureToken)
        }

        SecurityPreferenceCommit.persist(
            PreferencesPatch(revealPolicy: .noVerification),
            relativeTo: current,
            using: preferences
        ) { _ in XCTFail("A downgrade must not update memory before persistence") }
        SecurityPreferenceCommit.persist(
            PreferencesPatch(hideInAppSwitcher: false),
            relativeTo: current,
            using: preferences
        ) { _ in XCTFail("A downgrade must not update memory before persistence") }

        // The production PreferencesService completes these callbacks from its
        // SerialWriteChain. Reproduce that callback order without depending on
        // CloudKit or SwiftData timing.
        preferences.completeSuccess(at: 0)
        preferences.completeFailure(at: 1)
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(trace.names, ["success", "failure"])
        XCTAssertEqual(trace.mainThreadChecks, [true, true])
    }
}

private final class NotificationTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var deliveredNames: [String] = []
    private var deliveredOnMain: [Bool] = []

    func append(_ name: String, onMain: Bool) {
        lock.lock()
        deliveredNames.append(name)
        deliveredOnMain.append(onMain)
        lock.unlock()
    }

    var names: [String] {
        lock.lock()
        defer { lock.unlock() }
        return deliveredNames
    }

    var mainThreadChecks: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return deliveredOnMain
    }
}

private actor ManuallyCompletedPreferences: PreferencesServing {
    private nonisolated let callbacks = CallbackBox()

    func load() async throws -> PreferencesDTO { .fakeDefault() }
    func update(_ patch: PreferencesPatch) async throws {}
    func purgeAllRecordsForErase() async throws {}
    func purgeAllRecordsForCommittedErase(authorization: CommittedEraseToken) async throws {}

    nonisolated func persist(
        _ patch: PreferencesPatch,
        authorizing: @escaping @Sendable () async throws -> Void,
        committing: @escaping PreferencesCommit,
        expectedCurrentPolicy: RevealPolicy?,
        onFailure: (@Sendable (Error) -> Void)?,
        onSuccess: (@Sendable () -> Void)?
    ) {
        callbacks.append(success: onSuccess, failure: onFailure)
    }

    nonisolated func completeSuccess(at index: Int) { callbacks.completeSuccess(at: index) }
    nonisolated func completeFailure(at index: Int) { callbacks.completeFailure(at: index) }

    private final class CallbackBox: @unchecked Sendable {
        private let lock = NSLock()
        private var completions: [(
            success: (@Sendable () -> Void)?,
            failure: (@Sendable (Error) -> Void)?
        )] = []

        func append(
            success: (@Sendable () -> Void)?,
            failure: (@Sendable (Error) -> Void)?
        ) {
            lock.lock()
            completions.append((success, failure))
            lock.unlock()
        }

        func completeSuccess(at index: Int) {
            lock.lock()
            let callback = completions[index].success
            lock.unlock()
            callback?()
        }

        func completeFailure(at index: Int) {
            lock.lock()
            let callback = completions[index].failure
            lock.unlock()
            callback?(ApiRelayError.networkUnavailable)
        }
    }
}
