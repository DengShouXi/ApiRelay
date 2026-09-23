@preconcurrency import XCTest
@testable import ApiRelay

/// Source-level UI contracts for password fields. SwiftUI does not expose the
/// underlying editor traits for inspection, so these checks guard every direct
/// credential entry point against silently drifting away from the shared policy.
@MainActor
final class SensitiveInputHygieneTests: XCTestCase {
    func testSharedPasswordModifierUsesCredentialSemanticsWithoutTextMutation() throws {
        let source = try Self.productionSource("UI/Shared/SensitivePasswordInput.swift")
        XCTAssertTrue(source.contains(".textContentType(.password)"))
        XCTAssertTrue(source.contains(".textContentType(.newPassword)"))
        XCTAssertTrue(source.contains(".autocorrectionDisabled(true)"))
        XCTAssertTrue(source.contains(".textInputAutocapitalization(.never)"))
    }

    func testEveryDirectSwiftUISecureFieldUsesSharedPasswordPolicy() throws {
        for path in [
            "UI/Shared/AppLockCoverView.swift",
            "UI/Settings/SettingsGroupedChrome.swift",
            "UI/Settings/SettingsView.swift",
            "UI/Settings/BackupSettingsViews.swift",
        ] {
            let source = try Self.productionSource(path)
            let lines = source.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated()
            where line.trimmingCharacters(in: .whitespaces).hasPrefix("SecureField(") {
                let policyWindow = lines[index...min(index + 3, lines.index(before: lines.endIndex))]
                XCTAssertTrue(
                    policyWindow.contains { $0.contains(".sensitivePasswordInput(") },
                    "\(path):\(index + 1) bypasses the shared password input policy"
                )
            }
        }
    }

    func testTouchLockFieldDisablesEveryAvailableTextTransformation() throws {
        let source = try Self.productionSource("UI/Shared/AppLockCoverView.swift")
        for contract in [
            "autocorrectionType = .no",
            "autocapitalizationType = .none",
            "spellCheckingType = .no",
            "smartQuotesType = .no",
            "smartDashesType = .no",
            "smartInsertDeleteType = .no",
            "inlinePredictionType = .no",
            "mathExpressionCompletionType = .no",
            "textContentType = .password",
        ] {
            XCTAssertTrue(source.contains(contract), "missing UIKit contract: \(contract)")
        }
        XCTAssertFalse(source.contains("keyboardType = .asciiCapable"))
    }

    func testVaultAppPasswordPromptUsesSharedPolicyAndClearsOnDismiss() throws {
        let source = try Self.productionSource("UI/Vault/VaultHomeView.swift")
        guard let promptStart = source.range(of: "private struct MasterPasswordPrompt") else {
            return XCTFail("missing MasterPasswordPrompt")
        }
        let prompt = source[promptStart.lowerBound...]
        XCTAssertTrue(prompt.contains("SecureField(\"vault.masterPassword\""))
        XCTAssertTrue(prompt.contains(".sensitivePasswordInput()"))

        guard let dismissStart = source.range(of: ".sheet(isPresented: $showMasterPrompt, onDismiss:") else {
            return XCTFail("missing master-password sheet dismissal")
        }
        let dismissalWindow = source[dismissStart.lowerBound...].prefix(400)
        XCTAssertTrue(dismissalWindow.contains("masterPasswordInput = \"\""))
    }

    func testSensitiveSurfacesClearOnSceneExitSessionLockAndDisappear() throws {
        let lock = try Self.productionSource("UI/Shared/AppLockCoverView.swift")
        XCTAssertTrue(lock.contains(".onChange(of: scenePhase)"))
        XCTAssertTrue(lock.contains(".onReceive(environment.appPrivacy.$session)"))
        XCTAssertTrue(lock.contains(".onDisappear"))
        XCTAssertTrue(lock.contains("clearSensitiveInput()"))

        let settings = try Self.productionSource("UI/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains("clearSettingsSensitiveInputs()"))
        XCTAssertTrue(settings.contains("clearSensitiveInputs()"))
        XCTAssertGreaterThanOrEqual(
            settings.components(separatedBy: ".onReceive(environment.appPrivacy.$session)").count - 1,
            2
        )

        let backup = try Self.productionSource("UI/Settings/BackupSettingsViews.swift")
        XCTAssertEqual(
            backup.components(separatedBy: ".onReceive(environment.appPrivacy.$session)").count - 1,
            3
        )
        XCTAssertGreaterThanOrEqual(
            backup.components(separatedBy: "clearSensitiveInputFields()").count - 1,
            6
        )
    }

    func testCredentialUIStateIsNotPublishedOrLogged() throws {
        let sources = try [
            "UI/Shared/AppLockCoverView.swift",
            "UI/Settings/SettingsView.swift",
            "UI/Settings/BackupSettingsViews.swift",
        ].map(Self.productionSource)
        for source in sources {
            XCTAssertFalse(source.contains("@Published"))
            XCTAssertFalse(source.contains("Logger("))
            XCTAssertFalse(source.contains("print("))
        }
    }

    func testPolicyDowngradePromptAndPersistedSelectionStayOnCurrentNavigationPage() throws {
        let source = try Self.productionSource("UI/Settings/SettingsView.swift")
        guard let bodyEnd = source.range(of: "    @ViewBuilder\n    private var settingsRoot") else {
            return XCTFail("missing SettingsView body boundary")
        }
        let navigationHost = source[..<bodyEnd.lowerBound]
        XCTAssertTrue(
            navigationHost.contains(
                "\n        }\n        .alert(\"settings.securityPersistFailed.title\""
            ),
            "security alerts must be attached to NavigationStack, not its hidden root destination"
        )
        XCTAssertTrue(navigationHost.contains("isPresented: $showWeakenPasswordPrompt"))

        guard let pickerStart = source.range(of: "private struct RevealPolicySettingsView"),
              let pickerEnd = source.range(of: "// MARK: - App password")
        else {
            return XCTFail("missing reveal-policy picker source")
        }
        let picker = source[pickerStart.lowerBound..<pickerEnd.lowerBound]
        XCTAssertTrue(
            picker.contains(
                ".onReceive(NotificationCenter.default.publisher(for: .securityPreferencesDidPersist))"
            )
        )
        XCTAssertTrue(picker.contains("refreshHighlightedPolicyFromPersistence()"))
        XCTAssertTrue(picker.contains("environment.preferences.load()"))
        XCTAssertTrue(
            picker.contains("@State private var effectiveCurrentPolicy: RevealPolicy"),
            "the next authentication flow needs a mutable authoritative policy, not the destination's initial value"
        )
        XCTAssertTrue(
            picker.contains("currentPolicy: effectiveCurrentPolicy"),
            "continuous switching on the same page must route with the latest persisted policy"
        )
        XCTAssertGreaterThanOrEqual(
            picker.components(separatedBy: "effectiveCurrentPolicy =").count - 1,
            2,
            "both parent updates and persistence reloads must refresh the effective policy"
        )
    }

    func testPendingEraseHasDedicatedOpaqueColdLaunchRecoveryAction() throws {
        let content = try Self.productionSource("ContentView.swift")
        XCTAssertTrue(content.contains("environment.dataLifecycle.hasPendingErase()"))
        XCTAssertTrue(
            content.contains(
                "eraseRecoveryRequired\n            || crossStoreRecoveryRequired\n            || !privacy.session.isPreferencesReady"
            )
        )
        XCTAssertTrue(content.contains("try await environment.dataLifecycle.eraseAllUserData()"))
        XCTAssertTrue(content.contains(".userDataEraseRecoveryStateDidChange"))
        XCTAssertTrue(content.contains("eraseRecoveryRevision &+= 1"))

        let cover = try Self.productionSource("UI/Shared/AppLockCoverView.swift")
        XCTAssertTrue(cover.contains("if eraseRecoveryRequired { return \"appLock.eraseRecovery.title\" }"))
        XCTAssertTrue(cover.contains("onContinueEraseRecovery()"))
        XCTAssertTrue(
            cover.contains(
                "!eraseRecoveryRequired && !storageRecoveryRequired && ((usesMasterPassword"
            )
        )
    }

    private static func productionSource(_ relativePath: String) throws -> String {
        let testsFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testsFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRoot.appendingPathComponent("ApiRelay/\(relativePath)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
