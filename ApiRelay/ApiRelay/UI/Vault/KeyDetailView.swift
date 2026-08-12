import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

/// 密钥详情：参考系统「密码」App 的卡片式信息页（字段为本产品数据）。
struct KeyDetailView: View {
    let keyId: UUID
    @ObservedObject var viewModel: VaultHomeViewModel
    var allowDelete: Bool = true
    var unassignFromToolId: UUID? = nil
    /// Mac 三栏右侧：不要再套一层「密钥详情」大标题推送感。
    var splitPaneStyle: Bool = false

    let onCopy: (UUID) -> Void
    let onReveal: (UUID) -> Void
    let onAssign: (UUID) -> Void
    let onUnassign: (UUID, UUID) -> Void
    let onDelete: (UUID) -> Void

    @State private var showEdit = false

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
        .toolbar {
            if let key {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showEdit = true
                    } label: {
                        Label("vault.key.edit", systemImage: AppSymbols.Action.edit)
                    }

                    Button {
                        onCopy(key.id)
                    } label: {
                        Label("vault.copy", systemImage: AppSymbols.Action.copy)
                    }
                    .disabled(!key.secretAvailable)

                    Button {
                        onReveal(key.id)
                    } label: {
                        Label("vault.reveal", systemImage: AppSymbols.Action.reveal)
                    }
                    .disabled(!key.secretAvailable)

                    if allowDelete {
                        Button("vault.delete", role: .destructive) {
                            onDelete(key.id)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let key, let account {
                EditKeySheet(
                    key: key,
                    account: account,
                    onSave: { name, secret, ack, notes, accountName, platform, customURL in
                        await viewModel.editKey(
                            keyId: key.id,
                            name: name,
                            secret: secret,
                            ackDuplicate: ack,
                            notes: notes,
                            accountName: accountName,
                            platform: platform,
                            customBaseURL: customURL
                        )
                    }
                )
            }
        }
        .navigationTitle(splitPaneStyle ? (key?.displayName ?? "") : String(localized: "vault.detail.title"))
        #if os(iOS) || targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            VStack(spacing: 16) {
                infoCard(key)
                statusCard(key)
                actionsCard(key)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func infoCard(_ key: KeyRecordDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: AppSymbols.Key.default)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor)
                    )
                    .accessibilityHidden(true)
                Text(key.displayName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)

            cardRow("vault.detail.name", value: key.displayName)
            cardDivider()
            cardRow("vault.detail.secret", value: maskLabel(key), monospaced: true)
            cardDivider()
            cardRow("vault.detail.account", value: account?.displayName ?? "—")
            cardDivider()
            cardRow("vault.detail.platform", value: platformLabel(for: account))
            cardDivider()
            cardRow("vault.detail.assignment", value: assignmentText(for: key))
            if !assignedTools.isEmpty {
                cardDivider()
                cardRow(
                    "vault.detail.assignedTools",
                    value: assignedTools.map(\.name).joined(separator: "、")
                )
            }
            cardDivider()
            cardRow("vault.detail.notes", value: notesLabel(key.notes))
            cardDivider()
            cardRow("vault.detail.lifecycle", value: lifecycleText(key.lifecycle))
            cardDivider()
            cardRow("vault.detail.origin", value: originText(key.origin))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private func statusCard(_ key: KeyRecordDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol(for: key))
                .font(.title2)
                .foregroundStyle(statusColor(for: key))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle(for: key))
                    .font(.headline)
                Text(statusDetail(for: key))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private func actionsCard(_ key: KeyRecordDTO) -> some View {
        VStack(spacing: 0) {
            Button {
                showEdit = true
            } label: {
                Label("vault.key.edit", systemImage: AppSymbols.Action.edit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12)

            Divider().opacity(0.5)

            if let toolId = unassignFromToolId {
                Button("vault.unassign", role: .destructive) {
                    onUnassign(key.id, toolId)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else {
                Button {
                    onAssign(key.id)
                } label: {
                    Label("vault.assign", systemImage: AppSymbols.Action.assign)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private func cardRow(_ title: LocalizedStringKey, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .body.monospaced() : .body)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 10)
    }

    private func cardDivider() -> some View {
        Divider().opacity(0.5)
    }

    private func maskLabel(_ key: KeyRecordDTO) -> String {
        if !key.secretAvailable { return String(localized: "vault.secret.missing") }
        if let hint = key.maskedHint { return "••••\(hint)" }
        return "••••"
    }

    private func notesLabel(_ notes: String?) -> String {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func platformLabel(for account: UpstreamAccountDTO?) -> String {
        guard let account else { return "—" }
        if let custom = account.customPlatformName, !custom.isEmpty {
            return custom
        }
        return PresetCatalog.platform(id: account.platform)?.displayName ?? account.platform
    }

    private func assignmentText(for key: KeyRecordDTO) -> String {
        switch key.consumerToolIds.count {
        case 0:
            return String(localized: "vault.assign.badge.none")
        default:
            return String(localized: "vault.assign.badge.count \(key.consumerToolIds.count)")
        }
    }

    private func lifecycleText(_ lifecycle: KeyLifecycle) -> String {
        switch lifecycle {
        case .active:
            return String(localized: "vault.detail.lifecycle.active")
        case .revokedUpstream:
            return String(localized: "vault.detail.lifecycle.revoked")
        case .softDeleted:
            return String(localized: "vault.detail.lifecycle.deleted")
        }
    }

    private func originText(_ origin: KeyOrigin) -> String {
        switch origin {
        case .manualEntry:
            return String(localized: "vault.detail.origin.manual")
        case .providerIssued:
            return String(localized: "vault.detail.origin.provider")
        case .receivedFromTransfer:
            return String(localized: "vault.detail.origin.transfer")
        case .relayIssued:
            return String(localized: "vault.detail.origin.relay")
        }
    }

    private func statusSymbol(for key: KeyRecordDTO) -> String {
        if !key.secretAvailable { return AppSymbols.Key.missingSecret }
        if key.consumerToolIds.count >= 2 { return AppSymbols.Key.shared }
        if key.consumerToolIds.isEmpty { return AppSymbols.Key.unassigned }
        return AppSymbols.Key.ready
    }

    private func statusColor(for key: KeyRecordDTO) -> Color {
        if !key.secretAvailable { return .secondary }
        if key.consumerToolIds.count >= 2 { return .accentColor }
        if key.consumerToolIds.isEmpty { return .secondary }
        return .green
    }

    private func statusTitle(for key: KeyRecordDTO) -> String {
        if !key.secretAvailable {
            return String(localized: "vault.detail.status.missing.title")
        }
        if key.consumerToolIds.count >= 2 {
            return String(localized: "vault.detail.status.shared.title")
        }
        if key.consumerToolIds.isEmpty {
            return String(localized: "vault.detail.status.unassigned.title")
        }
        return String(localized: "vault.detail.status.ready.title")
    }

    private func statusDetail(for key: KeyRecordDTO) -> String {
        if !key.secretAvailable {
            return String(localized: "vault.detail.status.missing.detail")
        }
        if key.consumerToolIds.count >= 2 {
            return String(localized: "vault.detail.status.shared.detail")
        }
        if key.consumerToolIds.isEmpty {
            return String(localized: "vault.detail.status.unassigned.detail")
        }
        return String(localized: "vault.detail.status.ready.detail")
    }
}

// MARK: - Edit

private struct EditKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let key: KeyRecordDTO
    let account: UpstreamAccountDTO
    let onSave: (
        _ name: String,
        _ secret: String?,
        _ ackDuplicate: Bool,
        _ notes: String?,
        _ accountName: String,
        _ platform: String,
        _ customBaseURL: String?
    ) async -> Bool

    @State private var name: String
    @State private var secret = ""
    @State private var ackDuplicate = false
    @State private var notes: String
    @State private var accountName: String
    @State private var platform: String
    @State private var customURL: String
    @State private var isSaving = false

    init(
        key: KeyRecordDTO,
        account: UpstreamAccountDTO,
        onSave: @escaping (
            _ name: String,
            _ secret: String?,
            _ ackDuplicate: Bool,
            _ notes: String?,
            _ accountName: String,
            _ platform: String,
            _ customBaseURL: String?
        ) async -> Bool
    ) {
        self.key = key
        self.account = account
        self.onSave = onSave
        _name = State(initialValue: key.displayName)
        _notes = State(initialValue: key.notes ?? "")
        _accountName = State(initialValue: account.displayName)
        _platform = State(initialValue: account.platform)
        _customURL = State(initialValue: account.customBaseURL ?? "")
    }

    private var selectedPlatformLabel: String {
        PresetCatalog.platform(id: platform)?.displayName
            ?? String(localized: "vault.custom.platform")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("vault.key.name", text: $name)
                    SecureField("vault.key.secret.optional", text: $secret)
                        .autocorrectionDisabled()
                    Text("vault.key.secret.keepHint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Toggle("vault.key.ackDuplicate", isOn: $ackDuplicate)
                    }
                    TextField("vault.key.notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                    Text("vault.key.notes.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("vault.account.platform", selection: $platform) {
                        ForEach(PresetCatalog.platforms, id: \.id) { p in
                            Label(p.displayName, systemImage: p.iconSymbol).tag(p.id)
                        }
                        Label(
                            "vault.custom.platform",
                            systemImage: AppSymbols.platform(id: PresetCatalog.customPlatformID)
                        )
                        .tag(PresetCatalog.customPlatformID)
                    }
                    .pickerStyle(.menu)
                    LabeledContent("vault.account.platform.selected") {
                        Text(selectedPlatformLabel)
                            .foregroundStyle(.secondary)
                    }
                    TextField("vault.account.name", text: $accountName)
                    if platform == PresetCatalog.customPlatformID {
                        TextField("vault.account.baseURL", text: $customURL)
                            .autocorrectionDisabled()
                    }
                    Text("vault.key.edit.accountHint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("vault.key.edit")
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 520)
        #endif
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await onSave(
            name,
            trimmedSecret.isEmpty ? nil : trimmedSecret,
            ackDuplicate,
            notes,
            accountName,
            platform,
            platform == PresetCatalog.customPlatformID ? customURL : nil
        )
        if ok {
            secret = ""
            dismiss()
        }
    }
}
