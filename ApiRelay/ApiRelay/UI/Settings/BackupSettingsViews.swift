import SwiftUI
import UniformTypeIdentifiers

struct BackupPassphraseSettingsView: View {
    let environment: AppEnvironment
    let onChanged: () async -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var isSet = false
    @State private var isBusy = false
    @State private var status = ""
    @State private var showFailure = false
    @State private var failureReason = ""
    @State private var showAppPasswordPrompt = false
    @State private var appPasswordInput = ""
    @State private var pendingAuth: BackupPassphraseSensitiveOps.Action?
    @State private var combinationNeedsSetup = false
    @State private var showIndependentRecovery = false
    @State private var authenticationScope: AuthenticationRequestScope?

    var body: some View {
        SettingsSubpage(title: "settings.backup.passphrase.setDefault") {
            HStack(spacing: 8) {
                Image(systemName: isSet ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(isSet ? Color.green : Color.secondary)
                Text(
                    isSet
                        ? "settings.backup.passphrase.status.set"
                        : "settings.backup.passphrase.status.unset"
                )
                .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.45))
            )

            SettingsCard {
                SettingsSecureField(
                    title: "settings.backup.passphrase",
                    text: $passphrase,
                    role: .newCredential
                )
                SettingsCardDivider()
                SettingsSecureField(
                    title: "settings.backup.passphrase.confirm",
                    text: $confirm,
                    role: .newCredential
                )
            }
            SettingsFooterNote(text: "settings.backup.passphrase.footer")

            SettingsPrimaryButton(
                title: isSet ? "settings.backup.passphrase.update" : "settings.backup.passphrase.save",
                disabled: isBusy || passphrase.isEmpty || confirm.isEmpty
            ) {
                Task { await save() }
            }

            if isSet {
                SettingsCard {
                    Button {
                        Task { await copyStored() }
                    } label: {
                        Text("settings.backup.passphrase.copy")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    .disabled(isBusy)
                    SettingsCardDivider()
                    Button(role: .destructive) {
                        Task { await clearStored() }
                    } label: {
                        Text("settings.backup.passphrase.clear")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    .disabled(isBusy)
                }
            }

            if !status.isEmpty {
                SettingsStatusBanner(text: status)
            }

            CombinationAppPasswordButton(
                environment: environment,
                hasBoundOperation: pendingAuth != nil
            ) {
                Task { await beginBackupCombinationPassword() }
            }

            OrdinaryMissingAppPasswordRecoveryButton(
                environment: environment,
                isVisible: showIndependentRecovery
            ) {
                pendingAuth = nil
                combinationNeedsSetup = false
            }
        }
        .overlay {
            if isBusy { ProgressView() }
        }
        .onDisappear {
            abandonSensitiveRequest()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .onReceive(environment.appPrivacy.$session) { session in
            if session.isSessionLocked {
                abandonSensitiveRequest()
            }
        }
        .task {
            isSet = (try? await environment.backupPassphrase.isSet()) ?? false
        }
        .alert("settings.backup.passphrase.saveFailed.title", isPresented: $showFailure) {
            Button("settings.done", role: .cancel) {}
        } message: {
            Text(failureReason)
        }
        .alert(
            String(localized: "settings.weakenConfirm.appPassword.title"),
            isPresented: $showAppPasswordPrompt
        ) {
            SecureField("vault.masterPassword", text: $appPasswordInput)
                .sensitivePasswordInput()
            Button("settings.done") {
                let password = appPasswordInput
                appPasswordInput = ""
                Task { await confirmPendingPassphraseAction(password: password) }
            }
            Button("settings.cancel", role: .cancel) {
                pendingAuth = nil
                appPasswordInput = ""
            }
        } message: {
            Text("settings.weakenConfirm.appPassword.message")
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase != .active {
            clearSensitiveInputFields()
        }
        if phase == .inactive && environment.gate.isAuthenticationInProgress() { return }
        if phase != .active { abandonSensitiveRequest() }
    }

    private func clearSensitiveInputFields() {
        passphrase = ""
        confirm = ""
        appPasswordInput = ""
    }

    private func abandonSensitiveRequest() {
        authenticationScope?.cancel()
        authenticationScope = nil
        pendingAuth = nil
        combinationNeedsSetup = false
        showIndependentRecovery = false
        showAppPasswordPrompt = false
        clearSensitiveInputFields()
    }

    private func beginBackupCombinationPassword() async {
        guard CombinationExplicitAuth.isCombination(
            environment.appPrivacy.session.preferences.revealPolicy
        ) else { return }
        guard pendingAuth != nil else { return }
        authenticationScope?.cancel()
        authenticationScope = nil
        let material = await environment.gate.appPasswordMaterialStatus()
        guard AppPasswordPolicyGate.canUseAppPasswordEntry(material: material) else {
            pendingAuth = nil
            combinationNeedsSetup = false
            showAppPasswordPrompt = false
            status = AppPasswordPolicyGate.ordinaryEntryUnavailableMessage(material: material)
            showIndependentRecovery = true
            return
        }
        combinationNeedsSetup = false
        showAppPasswordPrompt = true
    }

    private func save() async {
        status = ""
        let submittedPassphrase = passphrase
        let submittedConfirmation = confirm
        passphrase = ""
        confirm = ""
        guard submittedPassphrase == submittedConfirmation else {
            failureReason = String(localized: "settings.backup.passphrase.mismatch")
            showFailure = true
            return
        }
        await finishPassphraseAction(.save(submittedPassphrase), appPassword: nil)
    }

    private func copyStored() async {
        status = ""
        await finishPassphraseAction(.copy, appPassword: nil)
    }

    private func clearStored() async {
        status = ""
        await finishPassphraseAction(.clear, appPassword: nil)
    }

    private func confirmPendingPassphraseAction(password: String) async {
        let action = pendingAuth
        pendingAuth = nil
        guard let action else { return }
        await finishPassphraseAction(action, appPassword: password)
    }

    private func finishPassphraseAction(
        _ action: BackupPassphraseSensitiveOps.Action,
        appPassword: String?
    ) async {
        isBusy = true
        defer { isBusy = false }
        do {
            if combinationNeedsSetup {
                pendingAuth = nil
                combinationNeedsSetup = false
                status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
                showIndependentRecovery = true
                return
            }
            try await performWithPageAuthenticationScope {
                try await BackupPassphraseSensitiveOps.perform(
                    action,
                    environment: environment,
                    appPassword: appPassword
                )
            }
            switch action {
            case .save:
                passphrase = ""
                confirm = ""
                isSet = true
                status = String(localized: "settings.backup.passphrase.saved")
                await onChanged()
            case .copy:
                status = String(localized: "settings.backup.passphrase.copied")
            case .clear:
                isSet = false
                status = String(localized: "settings.backup.passphrase.cleared")
                await onChanged()
            }
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isMissingMaterial(error) {
            pendingAuth = nil
            showAppPasswordPrompt = false
            status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
            showIndependentRecovery = true
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isPasswordPrompt(error) {
            pendingAuth = action
            showAppPasswordPrompt = true
        } catch let error as ApiRelayError
            where BackupCombinationRetry.shouldKeepPending(
                policy: environment.appPrivacy.session.preferences.revealPolicy,
                error: error
            )
        {
            pendingAuth = action
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            failureReason = error.localizedDescription
            showFailure = true
        }
    }

    private func performWithPageAuthenticationScope<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let scope = AuthenticationRequestScope()
        authenticationScope?.cancel()
        authenticationScope = scope
        defer {
            if authenticationScope === scope { authenticationScope = nil }
        }
        return try await scope.perform(operation)
    }
}

private enum BackupProtectionChoice: Hashable, CaseIterable {
    case none
    case defaultStored
    case custom
}

struct BackupExportView: View {
    let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var storedIsSet = false
    @State private var choice: BackupProtectionChoice = .none
    @State private var oneTimePassphrase = ""
    @State private var oneTimeConfirm = ""
    @State private var status = ""
    @State private var isBusy = false
    @State private var showExporter = false
    @State private var showUnprotectedConfirm = false
    @State private var exportDocument = EncryptedBackupDocument(data: Data())
    @State private var exportFilename = "ApiRelay-Backup"
    @State private var pendingExportMissingSecretCount = 0
    @State private var showAppPasswordPrompt = false
    @State private var appPasswordInput = ""
    @State private var pendingExportPassphrase: String??
    @State private var pendingStoredExport = false
    @State private var combinationNeedsSetup = false
    @State private var showIndependentRecovery = false
    @State private var authenticationScope: AuthenticationRequestScope?

    private var exportDisabled: Bool {
        if isBusy { return true }
        switch choice {
        case .none:
            return false
        case .defaultStored:
            return !storedIsSet
        case .custom:
            return oneTimePassphrase.isEmpty || oneTimeConfirm.isEmpty
        }
    }

    var body: some View {
        SettingsSubpage(title: "settings.backup.export") {
            SettingsCard(title: "settings.backup.export.section.method") {
                SettingsChoiceRow(
                    title: "settings.backup.export.choice.none",
                    selected: choice == .none
                ) { choice = .none }
                SettingsCardDivider()
                SettingsChoiceRow(
                    title: "settings.backup.export.choice.default",
                    selected: choice == .defaultStored,
                    enabled: storedIsSet,
                    subtitle: storedIsSet ? nil : "settings.backup.passphrase.status.unset"
                ) { choice = .defaultStored }
                SettingsCardDivider()
                SettingsChoiceRow(
                    title: "settings.backup.export.choice.custom",
                    selected: choice == .custom
                ) { choice = .custom }
            }

            if choice == .custom {
                SettingsCard {
                    SettingsSecureField(
                        title: "settings.backup.passphrase",
                        text: $oneTimePassphrase,
                        role: .newCredential
                    )
                    SettingsCardDivider()
                    SettingsSecureField(
                        title: "settings.backup.passphrase.confirm",
                        text: $oneTimeConfirm,
                        role: .newCredential
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SettingsFooterNote(text: exportFooter)

            SettingsPrimaryButton(
                title: "settings.backup.export.action",
                disabled: exportDisabled
            ) {
                Task { await startExport() }
            }

            if !status.isEmpty {
                SettingsStatusBanner(text: status)
            }

            CombinationAppPasswordButton(
                environment: environment,
                hasBoundOperation: pendingStoredExport || pendingExportPassphrase != nil
            ) {
                Task { await beginExportCombinationPassword() }
            }

            OrdinaryMissingAppPasswordRecoveryButton(
                environment: environment,
                isVisible: showIndependentRecovery
            ) {
                pendingStoredExport = false
                pendingExportPassphrase = nil
                combinationNeedsSetup = false
            }
        }
        .animation(.easeInOut(duration: 0.2), value: choice)
        .overlay {
            if isBusy { ProgressView() }
        }
        .onDisappear {
            abandonSensitiveRequest()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .onReceive(environment.appPrivacy.$session) { session in
            if session.isSessionLocked {
                abandonSensitiveRequest()
            }
        }
        .task {
            storedIsSet = (try? await environment.backupPassphrase.isSet()) ?? false
            choice = storedIsSet ? .defaultStored : .none
        }
        .onChange(of: choice) { _, newValue in
            if newValue != .custom {
                oneTimePassphrase = ""
                oneTimeConfirm = ""
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: BackupFileTypes.backup,
            defaultFilename: exportFilename
        ) { result in
            handleExportResult(result)
        }
        .confirmationDialog(
            "settings.backup.export.unprotected.confirm",
            isPresented: $showUnprotectedConfirm,
            titleVisibility: .visible
        ) {
            Button("settings.backup.export.action", role: .destructive) {
                Task { await performExport(passphrase: nil) }
            }
            Button("gate.cancel", role: .cancel) {}
        }
        .alert(
            String(localized: "settings.weakenConfirm.appPassword.title"),
            isPresented: $showAppPasswordPrompt
        ) {
            SecureField("vault.masterPassword", text: $appPasswordInput)
                .sensitivePasswordInput()
            Button("settings.done") {
                let password = appPasswordInput
                appPasswordInput = ""
                let retryStored = pendingStoredExport
                pendingStoredExport = false
                let pending = pendingExportPassphrase
                pendingExportPassphrase = nil
                Task {
                    if retryStored {
                        await exportWithStored(appPassword: password)
                    } else {
                        await performExport(passphrase: pending ?? nil, appPassword: password)
                    }
                }
            }
            Button("settings.cancel", role: .cancel) {
                pendingStoredExport = false
                pendingExportPassphrase = nil
                appPasswordInput = ""
            }
        } message: {
            Text("settings.weakenConfirm.appPassword.message")
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase != .active {
            clearSensitiveInputFields()
        }
        if phase == .inactive && environment.gate.isAuthenticationInProgress() { return }
        if phase != .active { abandonSensitiveRequest() }
    }

    private func clearSensitiveInputFields() {
        oneTimePassphrase = ""
        oneTimeConfirm = ""
        appPasswordInput = ""
    }

    private func abandonSensitiveRequest() {
        authenticationScope?.cancel()
        authenticationScope = nil
        pendingStoredExport = false
        pendingExportPassphrase = nil
        combinationNeedsSetup = false
        showIndependentRecovery = false
        showAppPasswordPrompt = false
        clearSensitiveInputFields()
    }

    private var exportFooter: LocalizedStringKey {
        switch choice {
        case .none:
            return "settings.backup.export.footer.unprotected"
        case .defaultStored:
            return storedIsSet
                ? "settings.backup.export.footer.default"
                : "settings.backup.choice.default.unavailable"
        case .custom:
            return "settings.backup.export.footer.custom"
        }
    }

    private func beginExportCombinationPassword() async {
        guard CombinationExplicitAuth.isCombination(
            environment.appPrivacy.session.preferences.revealPolicy
        ) else { return }
        guard pendingStoredExport || pendingExportPassphrase != nil else { return }
        authenticationScope?.cancel()
        authenticationScope = nil
        let material = await environment.gate.appPasswordMaterialStatus()
        guard AppPasswordPolicyGate.canUseAppPasswordEntry(material: material) else {
            pendingStoredExport = false
            pendingExportPassphrase = nil
            combinationNeedsSetup = false
            showAppPasswordPrompt = false
            status = AppPasswordPolicyGate.ordinaryEntryUnavailableMessage(material: material)
            showIndependentRecovery = true
            return
        }
        combinationNeedsSetup = false
        showAppPasswordPrompt = true
    }

    private func startExport() async {
        status = ""
        switch choice {
        case .none:
            showUnprotectedConfirm = true
        case .defaultStored:
            await exportWithStored()
        case .custom:
            let submittedPassphrase = oneTimePassphrase
            let submittedConfirmation = oneTimeConfirm
            oneTimePassphrase = ""
            oneTimeConfirm = ""
            guard submittedPassphrase == submittedConfirmation else {
                status = String(localized: "settings.backup.passphrase.mismatch")
                return
            }
            await performExport(passphrase: submittedPassphrase)
        }
    }

    private func exportWithStored(appPassword: String? = nil) async {
        isBusy = true
        defer { isBusy = false }
        do {
            if combinationNeedsSetup {
                pendingStoredExport = false
                combinationNeedsSetup = false
                status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
                showIndependentRecovery = true
                return
            }
            let result = try await performWithPageAuthenticationScope {
                try await BackupStoredPassphraseAccess.exportUsingStored(
                    environment,
                    appPassword: appPassword
                )
            }
            await presentExported(result)
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isMissingMaterial(error) {
            pendingStoredExport = false
            pendingExportPassphrase = nil
            showAppPasswordPrompt = false
            status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
            showIndependentRecovery = true
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isPasswordPrompt(error) {
            pendingStoredExport = true
            showAppPasswordPrompt = true
        } catch let error as ApiRelayError
            where BackupCombinationRetry.shouldKeepPending(
                policy: environment.appPrivacy.session.preferences.revealPolicy,
                error: error
            )
        {
            pendingStoredExport = true
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            status = error.localizedDescription
        }
    }

    private func performExport(passphrase: String?, appPassword: String? = nil) async {
        isBusy = true
        defer { isBusy = false }
        do {
            if combinationNeedsSetup {
                pendingExportPassphrase = nil
                combinationNeedsSetup = false
                status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
                showIndependentRecovery = true
                return
            }
            let result = try await performWithPageAuthenticationScope {
                try await environment.backups.exportBackup(
                    passphrase: passphrase,
                    purpose: .fullBackup,
                    appPassword: appPassword
                )
            }
            await presentExported(result)
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isMissingMaterial(error) {
            pendingStoredExport = false
            pendingExportPassphrase = nil
            showAppPasswordPrompt = false
            status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
            showIndependentRecovery = true
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isPasswordPrompt(error) {
            pendingExportPassphrase = passphrase
            showAppPasswordPrompt = true
        } catch let error as ApiRelayError
            where BackupCombinationRetry.shouldKeepPending(
                policy: environment.appPrivacy.session.preferences.revealPolicy,
                error: error
            )
        {
            pendingExportPassphrase = passphrase
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            status = error.localizedDescription
        }
    }

    private func presentExported(_ result: BackupExportResult) async {
        pendingExportMissingSecretCount = result.keysWithoutSecretCount
        exportFilename = Self.backupFilenameStem()
        exportDocument = EncryptedBackupDocument(data: result.data)
        await Task.yield()
        showExporter = true
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            var message = String(localized: "settings.backup.exported")
            if pendingExportMissingSecretCount > 0 {
                message += "\n" + String(
                    localized: "settings.backup.exported.missingSecret \(Int64(pendingExportMissingSecretCount))"
                )
            }
            status = message
            pendingExportMissingSecretCount = 0
        case .failure(let error):
            guard !BackupFileIO.isCancellation(error) else { return }
            status = error.localizedDescription
        }
    }

    private static func backupFilenameStem() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "ApiRelay-Backup-\(formatter.string(from: Date()))"
    }

    private func performWithPageAuthenticationScope<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let scope = AuthenticationRequestScope()
        authenticationScope?.cancel()
        authenticationScope = scope
        defer {
            if authenticationScope === scope { authenticationScope = nil }
        }
        return try await scope.perform(operation)
    }
}

struct IncomingBackupPayload: Identifiable {
    let id = UUID()
    let data: Data

    static func read(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try Data(contentsOf: url)
    }
}

struct BackupImportView: View {
    let environment: AppEnvironment
    var incomingData: Data? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var storedIsSet = false
    @State private var choice: BackupProtectionChoice = .none
    @State private var customPassphrase = ""
    @State private var status = ""
    @State private var isBusy = false
    @State private var showImporter = false
    @State private var showAppPasswordPrompt = false
    @State private var appPasswordInput = ""
    @State private var pendingImport: (data: Data, passphrase: String?)?
    @State private var pendingStoredImport: Data?
    @State private var combinationNeedsSetup = false
    @State private var showIndependentRecovery = false
    @State private var authenticationScope: AuthenticationRequestScope?

    private var importDisabled: Bool {
        if isBusy { return true }
        switch choice {
        case .none:
            return false
        case .defaultStored:
            return !storedIsSet
        case .custom:
            return customPassphrase.isEmpty
        }
    }

    var body: some View {
        SettingsSubpage(
            title: "settings.backup.import",
            usesMacColumnChrome: incomingData == nil
        ) {
            SettingsCard(title: "settings.backup.import.section.method") {
                SettingsChoiceRow(
                    title: "settings.backup.import.choice.none",
                    selected: choice == .none
                ) { choice = .none }
                SettingsCardDivider()
                SettingsChoiceRow(
                    title: "settings.backup.import.choice.default",
                    selected: choice == .defaultStored,
                    enabled: storedIsSet,
                    subtitle: storedIsSet ? nil : "settings.backup.passphrase.status.unset"
                ) { choice = .defaultStored }
                SettingsCardDivider()
                SettingsChoiceRow(
                    title: "settings.backup.import.choice.custom",
                    selected: choice == .custom
                ) { choice = .custom }
            }

            if choice == .custom {
                SettingsCard {
                    SettingsSecureField(
                        title: "settings.backup.passphrase",
                        text: $customPassphrase
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SettingsFooterNote(text: importFooter)

            SettingsPrimaryButton(
                title: incomingData == nil
                    ? "settings.backup.import.choose"
                    : "settings.backup.import.action",
                disabled: importDisabled
            ) {
                if let incomingData {
                    Task { await importBytes(incomingData) }
                } else {
                    showImporter = true
                }
            }

            if !status.isEmpty {
                SettingsStatusBanner(text: status)
            }

            CombinationAppPasswordButton(
                environment: environment,
                hasBoundOperation: pendingStoredImport != nil || pendingImport != nil
            ) {
                Task { await beginImportCombinationPassword() }
            }

            OrdinaryMissingAppPasswordRecoveryButton(
                environment: environment,
                isVisible: showIndependentRecovery
            ) {
                pendingStoredImport = nil
                pendingImport = nil
                combinationNeedsSetup = false
            }
        }
        .animation(.easeInOut(duration: 0.2), value: choice)
        .overlay {
            if isBusy { ProgressView() }
        }
        .onDisappear {
            abandonSensitiveRequest()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .onReceive(environment.appPrivacy.$session) { session in
            if session.isSessionLocked {
                abandonSensitiveRequest()
            }
        }
        .task {
            storedIsSet = (try? await environment.backupPassphrase.isSet()) ?? false
            choice = storedIsSet ? .defaultStored : .none
        }
        .onChange(of: choice) { _, newValue in
            if newValue != .custom {
                customPassphrase = ""
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: BackupFileTypes.importTypes,
            allowsMultipleSelection: false
        ) { result in
            Task { await handlePicked(result) }
        }
        .alert(
            String(localized: "settings.weakenConfirm.appPassword.title"),
            isPresented: $showAppPasswordPrompt
        ) {
            SecureField("vault.masterPassword", text: $appPasswordInput)
                .sensitivePasswordInput()
            Button("settings.done") {
                let password = appPasswordInput
                appPasswordInput = ""
                let stored = pendingStoredImport
                pendingStoredImport = nil
                let pending = pendingImport
                pendingImport = nil
                Task {
                    if let stored {
                        await importWithStored(stored, appPassword: password)
                    } else if let pending {
                        await importData(pending.data, passphrase: pending.passphrase, appPassword: password)
                    }
                }
            }
            Button("settings.cancel", role: .cancel) {
                pendingStoredImport = nil
                pendingImport = nil
                appPasswordInput = ""
            }
        } message: {
            Text("settings.weakenConfirm.appPassword.message")
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase != .active {
            clearSensitiveInputFields()
        }
        if phase == .inactive && environment.gate.isAuthenticationInProgress() { return }
        if phase != .active { abandonSensitiveRequest() }
    }

    private func clearSensitiveInputFields() {
        customPassphrase = ""
        appPasswordInput = ""
    }

    private func abandonSensitiveRequest() {
        authenticationScope?.cancel()
        authenticationScope = nil
        pendingStoredImport = nil
        pendingImport = nil
        combinationNeedsSetup = false
        showIndependentRecovery = false
        showAppPasswordPrompt = false
        clearSensitiveInputFields()
    }

    private var importFooter: LocalizedStringKey {
        switch choice {
        case .none:
            return "settings.backup.import.footer.none"
        case .defaultStored:
            return storedIsSet
                ? "settings.backup.import.footer.default"
                : "settings.backup.choice.default.unavailable"
        case .custom:
            return "settings.backup.import.footer.custom"
        }
    }

    private func handlePicked(_ result: Result<[URL], Error>) async {
        status = ""
        let url: URL
        switch result {
        case .success(let urls):
            guard let picked = urls.first else { return }
            url = picked
        case .failure(let error):
            guard !BackupFileIO.isCancellation(error) else { return }
            status = error.localizedDescription
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            await importBytes(data)
        } catch {
            status = error.localizedDescription
        }
    }

    private func importBytes(_ data: Data) async {
        status = ""
        switch choice {
        case .none, .custom:
            do {
                let protection = try await environment.backups.inspectProtection(data)
                switch choice {
                case .none:
                    guard protection == .unprotected else {
                        status = String(localized: "settings.backup.import.mismatch.needsPassphrase")
                        return
                    }
                    await importData(data, passphrase: nil)
                case .custom:
                    let submittedPassphrase = customPassphrase
                    customPassphrase = ""
                    guard protection == .passphraseProtected else {
                        status = String(localized: "settings.backup.import.mismatch.unprotected")
                        return
                    }
                    await importData(data, passphrase: submittedPassphrase)
                case .defaultStored:
                    return
                }
            } catch {
                status = error.localizedDescription
            }
        case .defaultStored:
            await importWithStored(data)
        }
    }

    private func beginImportCombinationPassword() async {
        guard CombinationExplicitAuth.isCombination(
            environment.appPrivacy.session.preferences.revealPolicy
        ) else { return }
        guard pendingStoredImport != nil || pendingImport != nil else { return }
        authenticationScope?.cancel()
        authenticationScope = nil
        let material = await environment.gate.appPasswordMaterialStatus()
        guard AppPasswordPolicyGate.canUseAppPasswordEntry(material: material) else {
            pendingStoredImport = nil
            pendingImport = nil
            combinationNeedsSetup = false
            showAppPasswordPrompt = false
            status = AppPasswordPolicyGate.ordinaryEntryUnavailableMessage(material: material)
            showIndependentRecovery = true
            return
        }
        combinationNeedsSetup = false
        showAppPasswordPrompt = true
    }

    private func importWithStored(_ data: Data, appPassword: String? = nil) async {
        isBusy = true
        defer { isBusy = false }
        do {
            if combinationNeedsSetup {
                pendingStoredImport = nil
                combinationNeedsSetup = false
                status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
                showIndependentRecovery = true
                return
            }
            let summary = try await performWithPageAuthenticationScope {
                try await BackupStoredPassphraseAccess.importUsingStored(
                    environment,
                    data: data,
                    appPassword: appPassword
                )
            }
            applyImported(summary)
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isMissingMaterial(error) {
            pendingStoredImport = nil
            pendingImport = nil
            showAppPasswordPrompt = false
            status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
            showIndependentRecovery = true
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isPasswordPrompt(error) {
            pendingStoredImport = data
            showAppPasswordPrompt = true
        } catch let error as ApiRelayError where BackupStoredPassphraseAccess.isUnprotectedImport(error) {
            status = String(localized: "settings.backup.import.mismatch.unprotected")
        } catch let error as ApiRelayError
            where BackupCombinationRetry.shouldKeepPending(
                policy: environment.appPrivacy.session.preferences.revealPolicy,
                error: error
            )
        {
            pendingStoredImport = data
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            status = error.localizedDescription
        }
    }

    private func importData(_ data: Data, passphrase: String?, appPassword: String? = nil) async {
        isBusy = true
        defer { isBusy = false }
        do {
            if combinationNeedsSetup {
                pendingImport = nil
                combinationNeedsSetup = false
                status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
                showIndependentRecovery = true
                return
            }
            let summary = try await performWithPageAuthenticationScope {
                try await environment.backups.importBackup(
                    data: data,
                    passphrase: passphrase,
                    appPassword: appPassword
                )
            }
            applyImported(summary)
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isMissingMaterial(error) {
            pendingStoredImport = nil
            pendingImport = nil
            showAppPasswordPrompt = false
            status = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
            showIndependentRecovery = true
        } catch let error as ApiRelayError where BackupCurrentPolicyAuth.isPasswordPrompt(error) {
            pendingImport = (data, passphrase)
            showAppPasswordPrompt = true
        } catch let error as ApiRelayError
            where BackupCombinationRetry.shouldKeepPending(
                policy: environment.appPrivacy.session.preferences.revealPolicy,
                error: error
            )
        {
            pendingImport = (data, passphrase)
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            status = error.localizedDescription
        }
    }

    private func applyImported(_ summary: ImportSummary) {
        customPassphrase = ""
        var message = String(
            localized: "settings.backup.imported \(Int64(summary.accountCount)) \(Int64(summary.keyCount)) \(Int64(summary.skippedKeyCount))"
        )
        if summary.keysWithoutSecretCount > 0 {
            message += "\n" + String(
                localized: "settings.backup.imported.missingSecret \(Int64(summary.keysWithoutSecretCount))"
            )
        }
        status = message
        if incomingData != nil {
            dismiss()
        }
    }

    private func performWithPageAuthenticationScope<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let scope = AuthenticationRequestScope()
        authenticationScope?.cancel()
        authenticationScope = scope
        defer {
            if authenticationScope === scope { authenticationScope = nil }
        }
        return try await scope.perform(operation)
    }
}

nonisolated private struct EncryptedBackupDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] {
        [BackupFileTypes.backup]
    }

    nonisolated static var writableContentTypes: [UTType] {
        readableContentTypes
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

nonisolated private enum BackupFileTypes {
    nonisolated static var backup: UTType {
        UTType(exportedAs: SecureBackupFile.uti)
    }

    nonisolated static var importTypes: [UTType] {
        var types = [backup]
        if let byExtension = UTType(filenameExtension: SecureBackupFile.pathExtension) {
            types.append(byExtension)
        }
        return types
    }
}

private enum BackupFileIO {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}

enum BackupPassphraseSensitiveOps {
    enum Action: Equatable {
        case save(String)
        case copy
        case clear
    }

    static func reason(for action: Action) -> String {
        switch action {
        case .save:
            return String(localized: "gate.backupPassphraseSet")
        case .copy:
            return String(localized: "gate.backupPassphraseCopy")
        case .clear:
            return String(localized: "gate.backupPassphraseClear")
        }
    }

    static func perform(
        _ action: Action,
        environment: AppEnvironment,
        appPassword: String?
    ) async throws {
        // Capture before authentication. A background/lock/policy transition
        // during the prompt must make this exact operation stale; capturing a new
        // lease after authentication would incorrectly resurrect it.
        let authorization = try environment.backupPassphrase.captureAuthorizationLease()
        try await BackupCurrentPolicyAuth.confirm(
            environment: environment,
            reason: reason(for: action),
            appPassword: appPassword
        )
        try environment.backupPassphrase.validateAuthorizationLease(authorization)
        switch action {
        case .save(let passphrase):
            try await environment.backupPassphrase.set(
                passphrase,
                authorization: authorization
            )
            try environment.backupPassphrase.validateAuthorizationLease(authorization)
        case .copy:
            let secret = try await environment.backupPassphrase.plaintext(
                authorization: authorization
            )
            try environment.backupPassphrase.validateAuthorizationLease(authorization)
            // Clipboard retention is a security preference. If it cannot be
            // loaded, fail closed before touching the pasteboard instead of
            // silently treating the error as "auto-clear disabled".
            let prefs = try await environment.preferences.load()
            try environment.backupPassphrase.validateAuthorizationLease(authorization)
            let expires: TimeInterval? = {
                guard prefs.clipboardClearEnabled else { return nil }
                return TimeInterval(prefs.clipboardClearSeconds)
            }()
            let passphraseStore = environment.backupPassphrase
            try await environment.clipboard.write(
                secret,
                expiresAfter: expires,
                localOnly: true,
                committing: { operation in
                    try passphraseStore.commitAuthorizationLease(
                        authorization,
                        operation: operation
                    )
                }
            )
            try environment.backupPassphrase.validateAuthorizationLease(authorization)
        case .clear:
            try await environment.backupPassphrase.clear(authorization: authorization)
            try environment.backupPassphrase.validateAuthorizationLease(authorization)
        }
    }
}

enum BackupStoredPassphraseAccess {
    static let unprotectedImportReason = "unprotected"

    static func isUnprotectedImport(_ error: ApiRelayError) -> Bool {
        if case .validationFailed(let field, let reason) = error {
            return field == "backupImport" && reason == unprotectedImportReason
        }
        return false
    }

    static func requireUnlocked(_ environment: AppEnvironment) throws {
        if environment.appPrivacy.session.isSessionLocked {
            throw ApiRelayError.sessionLocked
        }
    }

    static func read(_ environment: AppEnvironment) async throws -> String {
        try requireUnlocked(environment)
        let authorization = try environment.backupPassphrase.captureAuthorizationLease()
        return try await environment.backupPassphrase.plaintext(
            authorization: authorization
        )
    }

    static func exportUsingStored(
        _ environment: AppEnvironment,
        appPassword: String? = nil
    ) async throws -> BackupExportResult {
        let secret = try await read(environment)
        return try await environment.backups.exportBackup(
            passphrase: secret,
            purpose: .fullBackup,
            appPassword: appPassword
        )
    }

    static func importUsingStored(
        _ environment: AppEnvironment,
        data: Data,
        appPassword: String? = nil
    ) async throws -> ImportSummary {
        try requireUnlocked(environment)
        let protection = try await environment.backups.inspectProtection(data)
        guard protection == .passphraseProtected else {
            throw ApiRelayError.validationFailed(
                field: "backupImport",
                reason: unprotectedImportReason
            )
        }
        let stored = try await read(environment)
        return try await environment.backups.importBackup(
            data: data,
            passphrase: stored,
            appPassword: appPassword
        )
    }
}

enum BackupCombinationRetry: Sendable {
    static func shouldKeepPending(policy: RevealPolicy, error: Error) -> Bool {
        CombinationExplicitAuth.isCombination(policy)
            && CombinationExplicitAuth.shouldOfferAppPassword(after: error)
    }
}

private struct OrdinaryMissingAppPasswordRecoveryButton: View {
    let environment: AppEnvironment
    let isVisible: Bool
    let onDiscardPending: () -> Void
    @State private var isRecovering = false
    @State private var outcome = ""

    var body: some View {
        if isVisible {
            Button("settings.appPassword.recover") {
                guard !isRecovering else { return }
                onDiscardPending()
                isRecovering = true
                Task {
                    await environment.appPrivacy.recoverFromLostMasterPassword()
                    if let error = environment.appPrivacy.unlockError {
                        outcome = error
                    } else if let stored = try? await environment.preferences.load(),
                              RevealPolicyPersistence.canonical(stored.revealPolicy) == .biometricOrPasscode {
                        outcome = String(localized: "settings.masterPassword.resetDone")
                    } else {
                        outcome = String(localized: "gate.cancel")
                    }
                    isRecovering = false
                }
            }
            .disabled(isRecovering)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityLabel(Text("settings.appPassword.recover"))
            if !outcome.isEmpty {
                SettingsStatusBanner(text: outcome)
            }
        }
    }
}

private struct CombinationAppPasswordButton: View {
    let environment: AppEnvironment
    let hasBoundOperation: Bool
    let onChoose: () -> Void

    var body: some View {
        if CombinationExplicitAuth.shouldShowExplicitEntry(
            hasBoundOperation: hasBoundOperation,
            policy: environment.appPrivacy.session.preferences.revealPolicy
        ) {
            Button("appLock.useAppPassword", action: onChoose)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityLabel(Text("appLock.useAppPassword"))
                .accessibilityHint(Text("appLock.combination.hint"))
        }
    }
}

enum BackupCurrentPolicyAuth {
    static func isMissingMaterial(_ error: ApiRelayError) -> Bool {
        if case .validationFailed(_, let reason) = error {
            return reason == "master_password_not_set" || reason == "master_password_not_configured"
        }
        return false
    }
    static func isPasswordPrompt(_ error: ApiRelayError) -> Bool {
        if case .validationFailed(_, let reason) = error {
            return reason == "master_password_prompt_required" || reason == "required"
        }
        return false
    }

    static func confirm(
        environment: AppEnvironment,
        reason: String,
        purpose: AuthPurpose = .settings,
        appPassword: String?
    ) async throws {
        if environment.appPrivacy.session.isSessionLocked {
            throw ApiRelayError.sessionLocked
        }
        let prefs = try await environment.preferences.load()
        if RevealPolicyPersistence.canonical(prefs.revealPolicy) == .masterPassword {
            let material = await environment.gate.appPasswordMaterialStatus()
            guard material == .set else {
                if material == .unreadable {
                    throw ApiRelayError.validationFailed(
                        field: "masterPassword",
                        reason: "material_unreadable"
                    )
                }
                throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "master_password_not_set")
            }
        }
        try await CurrentRevealPolicyAuth.confirm(
            prefs.revealPolicy,
            gate: environment.gate,
            reason: reason,
            purpose: purpose,
            appPassword: appPassword
        )
    }
}
