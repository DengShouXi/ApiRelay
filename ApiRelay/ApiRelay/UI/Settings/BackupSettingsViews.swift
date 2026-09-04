import SwiftUI
import UniformTypeIdentifiers

struct BackupPassphraseSettingsView: View {
    let environment: AppEnvironment
    let onChanged: () async -> Void

    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var isSet = false
    @State private var isBusy = false
    @State private var status = ""
    @State private var showFailure = false
    @State private var failureReason = ""

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
                SettingsSecureField(title: "settings.backup.passphrase", text: $passphrase)
                SettingsCardDivider()
                SettingsSecureField(title: "settings.backup.passphrase.confirm", text: $confirm)
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
        }
        .overlay {
            if isBusy { ProgressView() }
        }
        .task {
            isSet = (try? await environment.backupPassphrase.isSet()) ?? false
        }
        .alert("settings.backup.passphrase.saveFailed.title", isPresented: $showFailure) {
            Button("settings.done", role: .cancel) {}
        } message: {
            Text(failureReason)
        }
    }

    private func save() async {
        status = ""
        guard passphrase == confirm else {
            failureReason = String(localized: "settings.backup.passphrase.mismatch")
            showFailure = true
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            if isSet {
                try await environment.gate.confirmMandatory(
                    reason: String(localized: "gate.backupPassphraseSet")
                )
            }
            try await environment.backupPassphrase.set(passphrase)
            passphrase = ""
            confirm = ""
            isSet = true
            status = String(localized: "settings.backup.passphrase.saved")
            await onChanged()
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            failureReason = error.localizedDescription
            showFailure = true
        }
    }

    private func copyStored() async {
        status = ""
        isBusy = true
        defer { isBusy = false }
        do {
            try await environment.gate.confirmMandatory(
                reason: String(localized: "gate.backupPassphraseCopy")
            )
            let secret = try await environment.backupPassphrase.plaintext()
            let prefs = try? await environment.preferences.load()
            let seconds = TimeInterval(prefs?.clipboardClearSeconds ?? 120)
            try await environment.clipboard.write(secret, expiresAfter: seconds, localOnly: true)
            status = String(localized: "settings.backup.passphrase.copied")
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            failureReason = error.localizedDescription
            showFailure = true
        }
    }

    private func clearStored() async {
        status = ""
        isBusy = true
        defer { isBusy = false }
        do {
            try await environment.gate.confirmMandatory(
                reason: String(localized: "gate.backupPassphraseClear")
            )
            try await environment.backupPassphrase.clear()
            isSet = false
            status = String(localized: "settings.backup.passphrase.cleared")
            await onChanged()
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            failureReason = error.localizedDescription
            showFailure = true
        }
    }
}

private enum BackupProtectionChoice: Hashable, CaseIterable {
    case none
    case defaultStored
    case custom
}

struct BackupExportView: View {
    let environment: AppEnvironment
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
                    SettingsSecureField(title: "settings.backup.passphrase", text: $oneTimePassphrase)
                    SettingsCardDivider()
                    SettingsSecureField(title: "settings.backup.passphrase.confirm", text: $oneTimeConfirm)
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
        }
        .animation(.easeInOut(duration: 0.2), value: choice)
        .overlay {
            if isBusy { ProgressView() }
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

    private func startExport() async {
        status = ""
        switch choice {
        case .none:
            showUnprotectedConfirm = true
        case .defaultStored:
            await exportWithStored()
        case .custom:
            guard oneTimePassphrase == oneTimeConfirm else {
                status = String(localized: "settings.backup.passphrase.mismatch")
                return
            }
            await performExport(passphrase: oneTimePassphrase)
        }
    }

    private func exportWithStored() async {
        do {
            let secret = try await environment.backupPassphrase.plaintext()
            await performExport(passphrase: secret)
        } catch {
            status = error.localizedDescription
        }
    }

    private func performExport(passphrase: String?) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await environment.backups.exportBackup(
                passphrase: passphrase,
                purpose: .fullBackup
            )
            pendingExportMissingSecretCount = result.keysWithoutSecretCount
            exportFilename = Self.backupFilenameStem()
            exportDocument = EncryptedBackupDocument(data: result.data)
            await Task.yield()
            showExporter = true
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            status = error.localizedDescription
        }
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
    @State private var storedIsSet = false
    @State private var choice: BackupProtectionChoice = .none
    @State private var customPassphrase = ""
    @State private var status = ""
    @State private var isBusy = false
    @State private var showImporter = false

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
                    SettingsSecureField(title: "settings.backup.passphrase", text: $customPassphrase)
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
        }
        .animation(.easeInOut(duration: 0.2), value: choice)
        .overlay {
            if isBusy { ProgressView() }
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
        do {
            let protection = try await environment.backups.inspectProtection(data)
            switch choice {
            case .none:
                guard protection == .unprotected else {
                    status = String(localized: "settings.backup.import.mismatch.needsPassphrase")
                    return
                }
                await importData(data, passphrase: nil)
            case .defaultStored:
                guard protection == .passphraseProtected else {
                    status = String(localized: "settings.backup.import.mismatch.unprotected")
                    return
                }
                let stored = try await environment.backupPassphrase.plaintext()
                await importData(data, passphrase: stored)
            case .custom:
                guard protection == .passphraseProtected else {
                    status = String(localized: "settings.backup.import.mismatch.unprotected")
                    return
                }
                await importData(data, passphrase: customPassphrase)
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func importData(_ data: Data, passphrase: String?) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let summary = try await environment.backups.importBackup(data: data, passphrase: passphrase)
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
        } catch ApiRelayError.authenticationCancelled {
            return
        } catch {
            status = error.localizedDescription
        }
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
