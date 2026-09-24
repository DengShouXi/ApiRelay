#if DEBUG
import Foundation
import SwiftData

/// Fixed, in-memory UI-test world. The app still installs its real lifecycle
/// observers; only persistence and system authentication are substituted.
@MainActor
enum UITestFixture {
    static let password = "UITestPass123"

    static func makeEnvironment(scenario: String) throws -> AppEnvironment {
        let container = try AppSchema.makeInMemoryContainer()
        var initial = PreferencesDTO.fakeDefault()
        initial.revealPolicy = .masterPassword
        initial.appLockEnabled = scenario == "lock"
        initial.autoLockSeconds = 0
        initial.hideInAppSwitcher = true

        let keychain = FakeKeychain()
        let master = FakeMasterPassword(initialPassword: password)
        let gate = UITestRevealGate(password: password)
        let clipboard = FakeClipboard()
        let vault = FakeKeyVault(seedPreviewSample: true)
        let tools = FakeConsumerTools(seedPreviewSample: true)
        let trash = FakeRecentlyDeletedBatch()
        let entitlements: FakeEntitlements
        switch scenario {
        case "entitlement-free":
            entitlements = FakeEntitlements(tier: .free)
        case "entitlement-failure":
            entitlements = FakeEntitlements(tier: .unlimitedKeys, queryFails: true)
        case "entitlement-loading":
            entitlements = FakeEntitlements(
                tier: .unlimitedKeys,
                queryDelayNanoseconds: 30_000_000_000
            )
        case "entitlement-delayed-activation":
            entitlements = FakeEntitlements(
                tier: .free,
                activationDelayNanoseconds: 3_000_000_000
            )
        case "entitlement-pending-purchase":
            entitlements = FakeEntitlements(tier: .free, purchaseIsPending: true)
        default:
            entitlements = FakeEntitlements(tier: .unlimitedKeys)
        }
        let preferences = FakePreferences(initial: initial)
        let backups = FakeSecureBackup()
        let backupPassphrase = FakeBackupPassphrase()
        let dataLifecycle = FakeDataLifecycle()
        let cloudSync = FakeCloudSync()
        let privacy = AppPrivacyController(
            gate: gate,
            preferences: preferences,
            masterPassword: master,
            installsSnapshotCover: scenario == "lock",
            enablesUnlockPrompt: scenario == "lock",
            launchAppLockEnabled: initial.appLockEnabled,
            autoPromptsSystemAuth: false
        )
        return AppEnvironment(
            modelContainer: container,
            keychain: keychain,
            masterPassword: master,
            gate: gate,
            clipboard: clipboard,
            vault: vault,
            consumerTools: tools,
            trashBatch: trash,
            entitlements: entitlements,
            preferences: preferences,
            backups: backups,
            backupPassphrase: backupPassphrase,
            dataLifecycle: dataLifecycle,
            cloudSync: cloudSync,
            appPrivacy: privacy
        )
    }
}

/// Deliberately no LocalAuthentication or production password material.
/// This verifies UI routing, not operating-system biometric/passcode sheets.
private actor UITestRevealGate: RevealGateServing {
    let password: String

    init(password: String) { self.password = password }

    func confirm(reason: String, policy: RevealPolicy, purpose: AuthPurpose) async throws {}

    func confirmWithMasterPassword(reason: String, password: String, purpose: AuthPurpose) async throws {
        try verify(password)
    }

    func confirmCombinationWithAppPassword(reason: String, password: String, purpose: AuthPurpose) async throws {
        try verify(password)
    }

    func confirmMandatory(reason: String, purpose: AuthPurpose) async throws {}

    func ensureMasterPasswordConfigured() async throws {}

    func isAppPasswordMaterialSet() async throws -> Bool { true }

    func appPasswordMaterialStatus() async -> AppPasswordMaterialStatus { .set }

    nonisolated func cancelAuthentication(owner: AuthenticationRequestOwner) {}

    nonisolated func cancelAllAuthentication() {}

    nonisolated func isAuthenticationInProgress(owner: AuthenticationRequestOwner?) -> Bool { false }

    nonisolated func availableBiometry() -> BiometryKind { .none }

    private func verify(_ entered: String) throws {
        guard entered == password else {
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "incorrect")
        }
    }
}
#endif
