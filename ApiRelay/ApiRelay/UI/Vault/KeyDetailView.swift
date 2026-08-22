import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

/// 右栏 / 详情：浏览态点密钥即复制；点「编辑」后原地进入编辑态。
enum KeyDetailChromeCommand: Equatable {
    case none
    case start
    case cancel
    case save
}

struct KeyDetailView: View {
    let keyId: UUID
    @ObservedObject var viewModel: VaultHomeViewModel
    var allowDelete: Bool = true
    var unassignFromToolId: UUID? = nil
    /// Mac 三栏右侧：不要再套一层「密钥详情」大标题推送感。
    var splitPaneStyle: Bool = false

    let onCopy: (UUID) -> Void
    let onAssign: (UUID) -> Void
    let onUnassign: (UUID, UUID) -> Void
    let onDelete: (UUID) -> Void
    let onRequestMasterPassword: (UUID) -> Void
    /// 主密码通过后把明文送进编辑态；浏览态 MUST NOT 用来展示明文。
    @Binding var revealedSecret: String?
    /// Mac 右栏顶栏由父视图托管时，用这个驱动开始 / 取消 / 保存。
    @Binding var chromeCommand: KeyDetailChromeCommand
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var isEditing = false
    @State private var awaitingEditUnlock = false
    @State private var isSaving = false
    @State private var duplicateExistingName: String?
    @State private var originalSecret = ""
    @State private var draftName = ""
    @State private var draftSecret = ""
    @State private var draftNotes = ""
    @State private var draftAccountName = ""
    @State private var draftPlatform = ""
    @State private var draftCustomPlatformName = ""
    @State private var draftCustomURL = ""
    @State private var usesDefaultAvatar = true
    @State private var customAvatar = AvatarChoice.key

    private var key: KeyRecordDTO? {
        viewModel.allKeys.first { $0.id == keyId }
    }

    private var account: UpstreamAccountDTO? {
        guard let key else { return nil }
        return viewModel.accounts.first { $0.id == key.accountId }
    }

    private var assignedTools: [ConsumerToolDTO] {
        guard let key else { return [] }
        return viewModel.tools.filter { key.consumerToolIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var isCustomPlatform: Bool {
        draftPlatform == PresetCatalog.customPlatformID
    }

    private var canSave: Bool {
        let hasNames = !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
        if isCustomPlatform {
            return hasNames && !draftCustomPlatformName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasNames
    }

    var body: some View {
        Group {
            if let key {
                cardScroll(key)
            } else {
                ContentUnavailableView(
                    "vault.detail.missing.title",
                    systemImage: AppSymbols.Key.unavailable,
                    description: Text("vault.detail.missing.detail")
                )
            }
        }
        .background(pageBackground)
        .onChange(of: keyId) { _, _ in
            leaveEditing(clearUnlock: true)
        }
        .onChange(of: isEditing) { _, editing in
            onEditingChanged?(editing)
        }
        .onChange(of: chromeCommand) { _, command in
            guard command != .none else { return }
            Task { await handleChrome(command) }
        }
        .onChange(of: revealedSecret) { _, secret in
            guard awaitingEditUnlock, let secret else { return }
            awaitingEditUnlock = false
            revealedSecret = nil
            beginEditing(with: secret)
        }
        .toolbar {
            if !splitPaneStyle, key != nil {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("gate.cancel") { leaveEditing(clearUnlock: true) }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("vault.save") {
                            Task { await save(acknowledgeDuplicate: false) }
                        }
                        .disabled(!canSave)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button("vault.edit") {
                            Task { await requestEditing() }
                        }
                    }
                }
            }
        }
        .navigationTitle(splitPaneStyle ? "" : (key?.displayName ?? String(localized: "vault.detail.title")))
        #if os(iOS) || targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .vaultPossibleDuplicateAlert(existingName: $duplicateExistingName) {
            await save(acknowledgeDuplicate: true)
        }
    }

    private var pageBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.gray.opacity(0.08)
        #endif
    }

    private var cardFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.primary.opacity(0.04)
        #endif
    }

    private func cardScroll(_ key: KeyRecordDTO) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                hero(key)
                if isEditing {
                    editCard(key)
                    if allowDelete {
                        deleteCard(key)
                    }
                } else {
                    browseCard(key)
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func hero(_ key: KeyRecordDTO) -> some View {
        VStack(spacing: 12) {
            VaultAvatarView(
                choice: isEditing
                    ? (usesDefaultAvatar ? viewModel.avatarDefaults.key : customAvatar)
                    : viewModel.avatar(for: key),
                size: 72,
                cornerRadius: 16
            )
            Text(isEditing ? draftName : key.displayName)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private func browseCard(_ key: KeyRecordDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            browseRow("vault.detail.account", value: account?.displayName ?? "—")
            cardDivider()
            secretBrowseRow(key)
            cardDivider()
            browseRow("vault.detail.assignment", value: assignmentText(for: key))
            cardDivider()
            browseRow("vault.detail.notes", value: notesLabel(key.notes))
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private func editCard(_ key: KeyRecordDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            editTextRow("vault.detail.name", text: $draftName)
            cardDivider()
            editSecretRow
            cardDivider()
            editTextRow("vault.detail.account", text: $draftAccountName)
            cardDivider()
            editPlatformRow
            if isCustomPlatform {
                cardDivider()
                editTextRow("vault.account.platformName", text: $draftCustomPlatformName)
                cardDivider()
                editTextRow("vault.account.baseURL", text: $draftCustomURL)
            }
            cardDivider()
            editAssignmentRow(key)
            cardDivider()
            editNotesRow
            cardDivider()
            AvatarOverrideEditor(
                defaultChoice: viewModel.avatarDefaults.key,
                usesDefault: $usesDefaultAvatar,
                customChoice: $customAvatar
            )
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private func deleteCard(_ key: KeyRecordDTO) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button("vault.delete", role: .destructive) {
                leaveEditing(clearUnlock: true)
                onDelete(key.id)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private func browseRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 12)
    }

    private func secretBrowseRow(_ key: KeyRecordDTO) -> some View {
        Button {
            onCopy(key.id)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("vault.detail.secret")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(secretDots(key))
                    .font(.body.monospaced())
                    .tracking(1.5)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("vault.a11y.secretHidden"))
        .accessibilityHint(Text("vault.a11y.secretHidden.hint"))
    }

    private func secretDots(_ key: KeyRecordDTO) -> String {
        String(repeating: "•", count: max(key.secretLength ?? 18, 8))
    }

    private func editTextRow(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private var editSecretRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("vault.detail.secret")
                .foregroundStyle(.secondary)
            TextField("", text: $draftSecret)
                .font(.body.monospaced())
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS) || targetEnvironment(macCatalyst)
                .textInputAutocapitalization(.never)
                #endif
        }
        .padding(.vertical, 12)
    }

    private var editPlatformRow: some View {
        HStack {
            Text("vault.detail.platform")
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Picker("vault.detail.platform", selection: $draftPlatform) {
                ForEach(PresetCatalog.platforms, id: \.id) { item in
                    Text(item.displayName).tag(item.id)
                }
                Text("vault.custom.platform").tag(PresetCatalog.customPlatformID)
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(.vertical, 8)
    }

    private func editAssignmentRow(_ key: KeyRecordDTO) -> some View {
        VStack(spacing: 0) {
            Button {
                onAssign(key.id)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("vault.detail.assignment")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(assignmentText(for: key))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let toolId = unassignFromToolId {
                cardDivider()
                Button("vault.unassign", role: .destructive) {
                    onUnassign(key.id, toolId)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 12)
            }
        }
    }

    private var editNotesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("vault.detail.notes")
                .foregroundStyle(.secondary)
            TextField("", text: $draftNotes, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private func cardDivider() -> some View {
        Divider().opacity(0.5)
    }

    private func notesLabel(_ notes: String?) -> String {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func assignmentText(for key: KeyRecordDTO) -> String {
        if assignedTools.isEmpty {
            return String(localized: "vault.assign.badge.none")
        }
        return assignedTools.map(\.name).joined(separator: "、")
    }

    private func handleChrome(_ command: KeyDetailChromeCommand) async {
        switch command {
        case .none:
            return
        case .start:
            await requestEditing()
        case .cancel:
            leaveEditing(clearUnlock: true)
        case .save:
            await save(acknowledgeDuplicate: false)
        }
        chromeCommand = .none
    }

    private func requestEditing() async {
        guard let key, let account else { return }
        awaitingEditUnlock = false
        seedDraft(from: key, account: account, secret: "")
        if !key.secretAvailable {
            beginEditing(with: "")
            return
        }
        if let secret = await viewModel.revealReturning(keyId: key.id, masterPassword: nil) {
            beginEditing(with: secret)
            return
        }
        if viewModel.needsMasterPassword {
            awaitingEditUnlock = true
            onRequestMasterPassword(key.id)
            return
        }
        if viewModel.revealWasCancelled {
            return
        }
        beginEditing(with: "")
    }

    private func seedDraft(from key: KeyRecordDTO, account: UpstreamAccountDTO, secret: String) {
        draftName = key.displayName
        draftSecret = secret
        originalSecret = secret
        draftNotes = key.notes ?? ""
        draftAccountName = account.displayName
        draftPlatform = account.platform
        draftCustomPlatformName = account.customPlatformName ?? ""
        draftCustomURL = account.customBaseURL ?? ""
        let override = AvatarChoice.parse(symbol: key.avatarSymbol, color: key.avatarColor)
        usesDefaultAvatar = override == nil
        customAvatar = override ?? viewModel.avatarDefaults.key
    }

    private func beginEditing(with secret: String) {
        guard let key, let account else { return }
        seedDraft(from: key, account: account, secret: secret)
        isEditing = true
    }

    private func leaveEditing(clearUnlock: Bool) {
        isEditing = false
        isSaving = false
        awaitingEditUnlock = false
        draftSecret = ""
        originalSecret = ""
        if clearUnlock {
            revealedSecret = nil
        }
    }

    private func save(acknowledgeDuplicate: Bool) async {
        guard let key, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedSecret = draftSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretToWrite: String?
        if trimmedSecret.isEmpty || trimmedSecret == originalSecret {
            secretToWrite = nil
        } else {
            secretToWrite = trimmedSecret
        }
        let trimmedCustom = draftCustomPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await viewModel.editKey(
            keyId: key.id,
            name: draftName,
            secret: secretToWrite,
            ackDuplicate: acknowledgeDuplicate,
            notes: draftNotes,
            accountName: draftAccountName,
            platform: draftPlatform,
            customPlatformName: isCustomPlatform ? trimmedCustom : nil,
            customBaseURL: isCustomPlatform ? draftCustomURL : nil,
            avatarSymbol: usesDefaultAvatar ? nil : customAvatar.symbol,
            avatarColor: usesDefaultAvatar ? nil : customAvatar.color.rawValue
        )
        switch result {
        case .saved:
            leaveEditing(clearUnlock: true)
        case .possibleDuplicate(let existingName):
            duplicateExistingName = existingName
        case .failed:
            break
        }
    }
}
