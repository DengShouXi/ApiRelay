import SwiftUI

struct VaultHomeView: View {
    @ObservedObject var viewModel: VaultHomeViewModel
    @State private var showAddAccount = false
    @State private var showAddTool = false
    @State private var showAddKeyFor: UpstreamAccountDTO?
    /// 账号 sheet 关闭后再弹出密钥 sheet，避免 macOS 上双 sheet 抢呈现。
    @State private var pendingAddKeyAccount: UpstreamAccountDTO?
    @State private var showTools = false
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var revealText: String?
    @State private var masterPasswordInput = ""
    @State private var pendingRevealKeyId: UUID?
    @State private var pendingCopyKeyId: UUID?
    @State private var showMasterPrompt = false
    @State private var showRecentlyDeleted = false
    @State private var assignKeyId: UUID?
    /// 「按使用方」下展开：在该分区正下方列出全部已有密钥供指派。
    @State private var expandAssignToolId: UUID?
    @State private var pendingDeleteAccountId: UUID?
    @State private var pendingDeleteToolId: UUID?

    var body: some View {
        NavigationStack {
            vaultList
                .navigationTitle("vault.title")
                .toolbar { vaultToolbar }
                .safeAreaInset(edge: .top) { groupingPicker }
                .task { await viewModel.onAppear() }
                .modifier(VaultHomeAlertsModifier(
                    viewModel: viewModel,
                    showPaywall: $showPaywall,
                    pendingDeleteAccountId: $pendingDeleteAccountId,
                    pendingDeleteToolId: $pendingDeleteToolId,
                    assignKeyId: $assignKeyId,
                    revealText: $revealText
                ))
                .modifier(VaultHomeSheetsModifier(
                    viewModel: viewModel,
                    showAddAccount: $showAddAccount,
                    showAddTool: $showAddTool,
                    showAddKeyFor: $showAddKeyFor,
                    pendingAddKeyAccount: $pendingAddKeyAccount,
                    showRecentlyDeleted: $showRecentlyDeleted,
                    showTools: $showTools,
                    showSettings: $showSettings,
                    showPaywall: $showPaywall,
                    showMasterPrompt: $showMasterPrompt,
                    masterPasswordInput: $masterPasswordInput,
                    pendingRevealKeyId: $pendingRevealKeyId,
                    pendingCopyKeyId: $pendingCopyKeyId,
                    revealText: $revealText
                ))
        }
    }

    @ViewBuilder
    private var vaultList: some View {
        List {
            if let quota = viewModel.remainingQuota {
                Section {
                    HStack {
                        Text("vault.quota.remaining \(quota)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("vault.paywall.open") { showPaywall = true }
                            .font(.footnote)
                    }
                }
            }

            ForEach(viewModel.sections) { section in
                Section {
                    sectionBody(section)
                } header: {
                    sectionHeader(section)
                }
            }

            if viewModel.groupingMode == .byConsumer && viewModel.tools.isEmpty {
                Section {
                    Text("vault.consumer.listEmpty")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var vaultToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Menu {
                Button("vault.recentlyDeleted") { showRecentlyDeleted = true }
                Button("vault.tools.manage") { showTools = true }
                Button("settings.title") { showSettings = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                switch viewModel.groupingMode {
                case .byPlatform:
                    showAddAccount = true
                case .byConsumer:
                    showAddTool = true
                }
            } label: {
                switch viewModel.groupingMode {
                case .byPlatform:
                    Label("vault.account.add", systemImage: "plus")
                case .byConsumer:
                    Label("vault.consumer.add", systemImage: "plus")
                }
            }
        }
    }

    private var groupingPicker: some View {
        Picker("vault.grouping", selection: Binding(
            get: { viewModel.groupingMode },
            set: { mode in Task { await viewModel.setGrouping(mode) } }
        )) {
            Text("vault.grouping.platform").tag(GroupingMode.byPlatform)
            Text("vault.grouping.consumer").tag(GroupingMode.byConsumer)
        }
        .pickerStyle(.segmented)
        .padding()
    }

    private func sectionTitle(_ section: KeyGroupSection) -> String {
        switch section.kind {
        case .platform(_, let title), .consumer(_, let title):
            return title
        case .shared:
            return String(localized: "vault.group.shared")
        case .unassigned:
            return String(localized: "vault.group.unassigned")
        }
    }

    @ViewBuilder
    private func sectionHeader(_ section: KeyGroupSection) -> some View {
        HStack {
            Text(sectionTitle(section))
            Spacer(minLength: 8)
            switch section.kind {
            case .platform(let accountId, _):
                Button("vault.account.delete", role: .destructive) {
                    pendingDeleteAccountId = accountId
                }
                .buttonStyle(.borderless)
                .font(.caption)
            case .consumer(let toolId, _):
                Button("vault.consumer.delete", role: .destructive) {
                    pendingDeleteToolId = toolId
                }
                .buttonStyle(.borderless)
                .font(.caption)
            case .shared, .unassigned:
                EmptyView()
            }
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func sectionBody(_ section: KeyGroupSection) -> some View {
        switch section.kind {
        case .platform(let accountId, _):
            ForEach(section.keys) { key in
                keyRow(key)
            }
            Button {
                showAddKeyFor = viewModel.accounts.first { $0.id == accountId }
            } label: {
                Label("vault.key.add", systemImage: "plus.circle")
            }
        case .consumer(let toolId, _):
            ForEach(section.keys) { key in
                keyRow(key, unassignFromToolId: toolId, allowDelete: false)
            }
            consumerSectionFooter(toolId: toolId, hasAssignedKeys: !section.keys.isEmpty)
        case .shared, .unassigned:
            ForEach(section.keys) { key in
                // 「按使用方」下不删密钥，只在按平台维护；未分配仅可指派。
                keyRow(key, allowDelete: false)
            }
        }
    }

    @ViewBuilder
    private func consumerSectionFooter(toolId: UUID, hasAssignedKeys: Bool) -> some View {
        let expanded = expandAssignToolId == toolId
        if !hasAssignedKeys, !expanded {
            Text("vault.consumer.empty.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Button {
            beginAssignExistingKey(to: toolId)
        } label: {
            if expanded {
                Label("vault.consumer.assignKey.collapse", systemImage: "chevron.up.circle")
            } else {
                Label("vault.consumer.assignKey", systemImage: "plus.circle")
            }
        }
        if expanded {
            assignKeyPicker(for: toolId)
        }
    }

    @ViewBuilder
    private func keyRow(
        _ key: KeyRecordDTO,
        unassignFromToolId: UUID? = nil,
        allowDelete: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(key.displayName)
                assignmentBadge(count: key.consumerToolIds.count)
            }
            Text(maskLabel(key))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack {
                Button("vault.reveal") { Task { await beginReveal(key.id) } }
                    .disabled(!key.secretAvailable)
                Button("vault.copy") { Task { await beginCopy(key.id) } }
                    .disabled(!key.secretAvailable)
                if let toolId = unassignFromToolId {
                    Button("vault.unassign", role: .destructive) {
                        Task { await viewModel.unassign(keyId: key.id, toolId: toolId) }
                    }
                } else {
                    Button("vault.assign") { beginAssign(key.id) }
                }
                if allowDelete {
                    Spacer()
                    Button("vault.delete", role: .destructive) {
                        Task { await viewModel.deleteKey(key.id) }
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .contextMenu {
            Button("vault.copy") { Task { await beginCopy(key.id) } }
            if let toolId = unassignFromToolId {
                Button("vault.unassign", role: .destructive) {
                    Task { await viewModel.unassign(keyId: key.id, toolId: toolId) }
                }
            } else {
                Button("vault.assign") { beginAssign(key.id) }
            }
            if allowDelete {
                Button("vault.delete", role: .destructive) {
                    Task { await viewModel.deleteKey(key.id) }
                }
            }
        }
    }

    private func maskLabel(_ key: KeyRecordDTO) -> String {
        if !key.secretAvailable { return String(localized: "vault.secret.missing") }
        if let hint = key.maskedHint { return "••••\(hint)" }
        return "••••"
    }

    private func beginAssign(_ keyId: UUID) {
        if viewModel.tools.isEmpty {
            viewModel.errorMessage = String(localized: "vault.assign.noConsumer")
            return
        }
        assignKeyId = keyId
    }

    /// 「按使用方」下：在分区正下方展开密钥列表（不弹空白 sheet）。
    private func beginAssignExistingKey(to toolId: UUID) {
        if viewModel.allKeys.isEmpty {
            viewModel.errorMessage = String(localized: "vault.assign.noKey")
            expandAssignToolId = nil
            return
        }
        if expandAssignToolId == toolId {
            expandAssignToolId = nil
        } else {
            expandAssignToolId = toolId
        }
    }

    @ViewBuilder
    private func assignKeyPicker(for toolId: UUID) -> some View {
        let rows = viewModel.keysAssignable(to: toolId).map {
            AssignPickRow(toolId: toolId, key: $0)
        }
        Text("vault.assign.shared.explain")
            .font(.caption)
            .foregroundStyle(.secondary)
        if rows.isEmpty {
            Text("vault.assign.allAssigned")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // 独立 id，避免与上方 keyRow 的 ForEach 抢 List 单元格（否则会误弹出「指派给使用方」）。
            ForEach(rows) { row in
                assignCandidateRow(key: row.key, toolId: row.toolId)
            }
        }
    }

    private func assignCandidateRow(key: KeyRecordDTO, toolId: UUID) -> some View {
        let accountName = viewModel.accounts.first { $0.id == key.accountId }?.displayName ?? "—"
        let assignCount = key.consumerToolIds.count
        return Button {
            Task {
                await viewModel.assign(keyId: key.id, toolId: toolId)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(key.displayName)
                            .foregroundStyle(.primary)
                        assignmentBadge(count: assignCount)
                    }
                    Text(accountName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("vault.assign.here")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func assignmentBadge(count: Int) -> some View {
        Group {
            if count == 0 {
                Text("vault.assign.badge.none")
                    .foregroundStyle(.secondary)
            } else {
                Text("vault.assign.badge.count \(count)")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((count == 0 ? Color.secondary : Color.orange).opacity(0.15))
        .clipShape(Capsule())
    }

    private func beginReveal(_ id: UUID) async {
        if let secret = await viewModel.revealReturning(keyId: id, masterPassword: nil) {
            revealText = secret
        } else if viewModel.needsMasterPassword {
            pendingRevealKeyId = id
            showMasterPrompt = true
        }
    }

    private func beginCopy(_ id: UUID) async {
        let ok = await viewModel.copyReturning(keyId: id, masterPassword: nil)
        if !ok && viewModel.needsMasterPassword {
            pendingCopyKeyId = id
            showMasterPrompt = true
        }
    }
}

// MARK: - Home modifiers

private struct VaultHomeAlertsModifier: ViewModifier {
    @ObservedObject var viewModel: VaultHomeViewModel
    @Binding var showPaywall: Bool
    @Binding var pendingDeleteAccountId: UUID?
    @Binding var pendingDeleteToolId: UUID?
    @Binding var assignKeyId: UUID?
    @Binding var revealText: String?

    func body(content: Content) -> some View {
        content
            .alert("vault.error.title", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("gate.cancel", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(viewModel.toastMessage ?? "", isPresented: Binding(
                get: { viewModel.toastMessage != nil },
                set: { if !$0 { viewModel.toastMessage = nil } }
            )) {
                Button("vault.toast.dismiss", role: .cancel) { viewModel.toastMessage = nil }
            }
            .alert("vault.quota.exceeded.title", isPresented: $viewModel.showQuotaAlert) {
                Button("vault.paywall.open") { showPaywall = true }
                Button("gate.cancel", role: .cancel) {}
            } message: {
                Text("vault.quota.exceeded.body")
            }
            .confirmationDialog(
                "vault.account.delete.confirm",
                isPresented: Binding(
                    get: { pendingDeleteAccountId != nil },
                    set: { if !$0 { pendingDeleteAccountId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("vault.account.delete", role: .destructive) {
                    if let id = pendingDeleteAccountId {
                        pendingDeleteAccountId = nil
                        Task { await viewModel.deleteAccount(id) }
                    }
                }
                Button("gate.cancel", role: .cancel) { pendingDeleteAccountId = nil }
            }
            .confirmationDialog(
                "vault.consumer.delete.confirm",
                isPresented: Binding(
                    get: { pendingDeleteToolId != nil },
                    set: { if !$0 { pendingDeleteToolId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("vault.consumer.delete", role: .destructive) {
                    if let id = pendingDeleteToolId {
                        pendingDeleteToolId = nil
                        Task { await viewModel.deleteTool(id) }
                    }
                }
                Button("gate.cancel", role: .cancel) { pendingDeleteToolId = nil }
            }
            .confirmationDialog("vault.assign.title", isPresented: Binding(
                get: { assignKeyId != nil },
                set: { if !$0 { assignKeyId = nil } }
            )) {
                ForEach(viewModel.tools) { tool in
                    Button(tool.name) {
                        if let id = assignKeyId {
                            Task { await viewModel.assign(keyId: id, toolId: tool.id) }
                        }
                    }
                }
            }
            .alert("vault.reveal.title", isPresented: Binding(
                get: { revealText != nil },
                set: { if !$0 { revealText = nil } }
            )) {
                Button("gate.cancel", role: .cancel) { revealText = nil }
            } message: {
                Text(revealText ?? "")
            }
    }
}

private struct VaultHomeSheetsModifier: ViewModifier {
    @ObservedObject var viewModel: VaultHomeViewModel
    @Binding var showAddAccount: Bool
    @Binding var showAddTool: Bool
    @Binding var showAddKeyFor: UpstreamAccountDTO?
    @Binding var pendingAddKeyAccount: UpstreamAccountDTO?
    @Binding var showRecentlyDeleted: Bool
    @Binding var showTools: Bool
    @Binding var showSettings: Bool
    @Binding var showPaywall: Bool
    @Binding var showMasterPrompt: Bool
    @Binding var masterPasswordInput: String
    @Binding var pendingRevealKeyId: UUID?
    @Binding var pendingCopyKeyId: UUID?
    @Binding var revealText: String?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAddAccount, onDismiss: {
                if let account = pendingAddKeyAccount {
                    pendingAddKeyAccount = nil
                    showAddKeyFor = account
                }
            }) {
                AddAccountSheet(existingAccounts: viewModel.accounts) { platform, name, url in
                    if let account = await viewModel.createAccount(
                        platform: platform, name: name, customBaseURL: url
                    ) {
                        pendingAddKeyAccount = account
                    }
                }
            }
            .sheet(isPresented: $showAddTool) {
                AddConsumerToolSheet(existingTools: viewModel.tools) { name in
                    await viewModel.createTool(name: name)
                }
            }
            .sheet(item: $showAddKeyFor) { account in
                AddKeySheet(
                    accountName: account.displayName,
                    existingKeyCount: viewModel.allKeys.filter { $0.accountId == account.id }.count
                ) { name, secret, ack in
                    await viewModel.createKey(
                        accountId: account.id, name: name, secret: secret, ackDuplicate: ack
                    )
                }
            }
            .sheet(isPresented: $showRecentlyDeleted) {
                RecentlyDeletedView(vault: viewModel)
                    #if os(macOS)
                    .frame(minWidth: 520, minHeight: 440)
                    #endif
            }
            .sheet(isPresented: $showTools) {
                ConsumerToolsView(environment: viewModel.environment)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(environment: viewModel.environment)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(environment: viewModel.environment)
            }
            .sheet(isPresented: $showMasterPrompt) {
                MasterPasswordPrompt(password: $masterPasswordInput) {
                    showMasterPrompt = false
                    let pwd = masterPasswordInput
                    masterPasswordInput = ""
                    if let id = pendingRevealKeyId {
                        pendingRevealKeyId = nil
                        if let secret = await viewModel.revealReturning(keyId: id, masterPassword: pwd) {
                            revealText = secret
                        }
                    } else if let id = pendingCopyKeyId {
                        pendingCopyKeyId = nil
                        await viewModel.copy(keyId: id, masterPassword: pwd)
                    }
                }
            }
    }
}

// MARK: - Sheets

private struct AssignPickRow: Identifiable {
    let toolId: UUID
    let key: KeyRecordDTO
    var id: String { "pick-\(toolId.uuidString)-\(key.id.uuidString)" }
}

private struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingAccounts: [UpstreamAccountDTO]
    @State private var platform = "openai"
    @State private var name = ""
    /// 上次自动填入的建议名；用户改写后切换平台时不再覆盖。
    @State private var lastSuggested = ""
    @State private var customURL = ""
    let onSave: (String, String, String?) async -> Void

    private var selectedPlatformLabel: String {
        PresetCatalog.platform(id: platform)?.displayName
            ?? String(localized: "vault.custom.platform")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("vault.account.platform", selection: $platform) {
                    ForEach(PresetCatalog.platforms, id: \.id) { p in
                        Text(p.displayName).tag(p.id)
                    }
                    Text("vault.custom.platform").tag(PresetCatalog.customPlatformID)
                }
                LabeledContent("vault.account.platform.selected") {
                    Text(selectedPlatformLabel)
                        .foregroundStyle(.secondary)
                }
                TextField("vault.account.name", text: $name)
                Text("vault.account.name.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if platform == PresetCatalog.customPlatformID {
                    TextField("vault.account.baseURL", text: $customURL)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("vault.account.add")
            .onAppear { applySuggestion(for: platform, force: true) }
            .onChange(of: platform) { _, newValue in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || name == lastSuggested {
                    applySuggestion(for: newValue, force: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            await onSave(
                                platform,
                                name,
                                platform == PresetCatalog.customPlatformID ? customURL : nil
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func applySuggestion(for platformID: String, force: Bool) {
        let suggested = Self.suggestedDisplayName(
            platformID: platformID,
            existing: existingAccounts
        )
        if force || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = suggested
            lastSuggested = suggested
        }
    }

    /// 按**同一上游平台**已有账号数递增：DeepSeek 已有 2 个 →「DeepSeek 账号 3」。
    static func suggestedDisplayName(
        platformID: String,
        existing: [UpstreamAccountDTO]
    ) -> String {
        let label = PresetCatalog.platform(id: platformID)?.displayName
            ?? String(localized: "vault.custom.platform")
        let count = existing.filter { $0.platform == platformID }.count
        return String(localized: "vault.account.defaultName \(label) \(count + 1)")
    }
}

private struct AddConsumerToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingTools: [ConsumerToolDTO]
    /// 空字符串 = 完全自定义；否则为预置显示名（如 VS Code）。
    @State private var baseName = "VS Code"
    @State private var deviceLabel = ""
    @State private var lastSuggestedDevice = ""
    let onSave: (String) async -> Void

    private var customBaseTag: String { "" }

    private var resolvedDisplayName: String {
        let device = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return device.isEmpty
                ? String(localized: "vault.consumer.defaultName \(customInstanceCount + 1)")
                : device
        }
        if device.isEmpty { return base }
        return String(localized: "vault.consumer.compoundName \(base) \(device)")
    }

    private var customInstanceCount: Int {
        existingTools.filter { !$0.isPreset }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("vault.consumer.base", selection: $baseName) {
                    ForEach(PresetCatalog.consumerTools, id: \.name) { tool in
                        Text(tool.name).tag(tool.name)
                    }
                    Text("vault.consumer.base.custom").tag(customBaseTag)
                }
                TextField(
                    baseName.isEmpty ? "vault.consumer.name.optional" : "vault.consumer.device",
                    text: $deviceLabel
                )
                Text("vault.consumer.name.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("vault.consumer.preview") {
                    Text(resolvedDisplayName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("vault.consumer.add")
            .onAppear { applyDeviceSuggestion(force: true) }
            .onChange(of: baseName) { _, _ in
                let trimmed = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || deviceLabel == lastSuggestedDevice {
                    applyDeviceSuggestion(force: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            await onSave(resolvedDisplayName)
                            dismiss()
                        }
                    }
                    .disabled(resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    /// 同一基名下递增：预置「VS Code」之外，第一台设备默认「电脑 1」。
    private func applyDeviceSuggestion(force: Bool) {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            if force {
                deviceLabel = ""
                lastSuggestedDevice = ""
            }
            return
        }
        let deviceSpecific = existingTools.filter {
            $0.name.hasPrefix("\(base) · ") || $0.name.hasPrefix("\(base) - ")
        }.count
        let suggested = String(localized: "vault.consumer.deviceDefault \(deviceSpecific + 1)")
        if force || deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deviceLabel = suggested
            lastSuggestedDevice = suggested
        }
    }
}

private struct AddKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let accountName: String
    let existingKeyCount: Int
    let onSave: (String, String, Bool) async -> Void
    @State private var name = ""
    @State private var secret = ""
    @State private var ackDuplicate = false

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("vault.key.account") {
                    Text(accountName).foregroundStyle(.secondary)
                }
                TextField("vault.key.name.optional", text: $name)
                Text("vault.key.name.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SecureField("vault.key.secret", text: $secret)
                    .autocorrectionDisabled()
                Toggle("vault.key.ackDuplicate", isOn: $ackDuplicate)
            }
            .navigationTitle("vault.key.add")
            .onAppear {
                if name.isEmpty {
                    name = String(localized: "vault.key.defaultName \(existingKeyCount + 1)")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            await onSave(name, secret, ackDuplicate)
                            secret = ""
                            dismiss()
                        }
                    }
                    .disabled(secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct MasterPasswordPrompt: View {
    @Binding var password: String
    let onConfirm: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SecureField("vault.masterPassword", text: $password)
                Text("vault.masterPassword.disclosure")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("vault.masterPassword.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.confirm") { Task { await onConfirm() } }
                }
            }
        }
    }
}

private struct RecentlyDeletedView: View {
    @ObservedObject var vault: VaultHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var keys: [KeyRecordDTO] = []
    @State private var accounts: [UpstreamAccountDTO] = []
    @State private var tools: [ConsumerToolDTO] = []
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var isLoading = true

    private var isEmpty: Bool {
        keys.isEmpty && accounts.isEmpty && tools.isEmpty
    }

    var body: some View {
        NavigationStack {
            // macOS sheet 上 Group+ContentUnavailableView 常表现为整页空白；统一用 List 更稳。
            List {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("vault.recentlyDeleted.loading")
                            .foregroundStyle(.secondary)
                    }
                } else if let loadError {
                    Section {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button("vault.recentlyDeleted.retry") {
                            Task { await reload() }
                        }
                    }
                } else if isEmpty {
                    Section {
                        Text("vault.recentlyDeleted.empty")
                            .font(.headline)
                        Text("vault.recentlyDeleted.empty.detail")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("vault.recentlyDeleted.empty.how")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("vault.recentlyDeleted.hint")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !keys.isEmpty {
                        Section("vault.recentlyDeleted.section.keys") {
                            ForEach(keys) { key in
                                trashRow(
                                    title: key.displayName,
                                    deletedAt: key.deletedAt,
                                    purgeAfter: key.purgeAfter,
                                    onRestore: { await vault.restoreKey(key.id) },
                                    onPermanent: { await vault.permanentlyDeleteKey(key.id) }
                                )
                            }
                        }
                    }
                    if !accounts.isEmpty {
                        Section("vault.recentlyDeleted.section.accounts") {
                            ForEach(accounts) { account in
                                trashRow(
                                    title: account.displayName,
                                    subtitle: account.platform,
                                    deletedAt: account.deletedAt,
                                    purgeAfter: account.purgeAfter,
                                    onRestore: { await vault.restoreAccount(account.id) },
                                    onPermanent: { await vault.permanentlyDeleteAccount(account.id) }
                                )
                            }
                        }
                    }
                    if !tools.isEmpty {
                        Section("vault.recentlyDeleted.section.tools") {
                            ForEach(tools) { tool in
                                trashRow(
                                    title: tool.name,
                                    deletedAt: tool.deletedAt,
                                    purgeAfter: tool.purgeAfter,
                                    onRestore: { await vault.restoreTool(tool.id) },
                                    onPermanent: { await vault.permanentlyDeleteTool(tool.id) }
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("vault.recentlyDeleted")
            #if os(macOS)
            .navigationSubtitle(isLoading
                ? String(localized: "vault.recentlyDeleted.loading")
                : String(localized: "vault.recentlyDeleted.subtitle \(keys.count) \(accounts.count) \(tools.count)")
            )
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("vault.recentlyDeleted.done") { dismiss() }
                }
            }
            .task { await reload() }
            .alert("vault.error.title", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("gate.cancel", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    @ViewBuilder
    private func trashRow(
        title: String,
        subtitle: String? = nil,
        deletedAt: Date?,
        purgeAfter: Date?,
        onRestore: @escaping () async -> Void,
        onPermanent: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let deletedAt {
                Text(String(localized: "vault.recentlyDeleted.deletedAt \(deletedAt.formatted(date: .abbreviated, time: .shortened))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let purgeAfter {
                Text(String(localized: "vault.recentlyDeleted.purgeAt \(purgeAfter.formatted(date: .abbreviated, time: .omitted))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("vault.restore") {
                    Task { await runAction(onRestore) }
                }
                Button("vault.delete.forever", role: .destructive) {
                    Task { await runAction(onPermanent) }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let bundle = try await vault.loadRecentlyDeletedBundle()
            keys = bundle.keys
            accounts = bundle.accounts
            tools = bundle.tools
        } catch {
            loadError = error.localizedDescription
            keys = []
            accounts = []
            tools = []
        }
    }

    private func runAction(_ action: () async -> Void) async {
        vault.errorMessage = nil
        await action()
        if let message = vault.errorMessage {
            actionError = message
            vault.errorMessage = nil
        }
        await reload()
    }
}

struct ConsumerToolsView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var tools: [ConsumerToolDTO] = []
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(tools) { tool in
                    HStack {
                        Text(tool.name)
                        Spacer()
                        Toggle("vault.tools.hidden", isOn: Binding(
                            get: { tool.isHidden },
                            set: { hidden in
                                Task {
                                    var patch = ConsumerToolPatch()
                                    patch.isHidden = hidden
                                    try? await environment.consumerTools.updateTool(id: tool.id, patch: patch)
                                    await reload()
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions {
                        Button("vault.delete", role: .destructive) {
                            Task {
                                try? await environment.consumerTools.deleteTool(id: tool.id)
                                await reload()
                            }
                        }
                    }
                    .contextMenu {
                        Button("vault.delete", role: .destructive) {
                            Task {
                                try? await environment.consumerTools.deleteTool(id: tool.id)
                                await reload()
                            }
                        }
                    }
                }
                Section {
                    TextField("vault.tools.new", text: $newName)
                    Button("vault.tools.add") {
                        Task {
                            _ = try? await environment.consumerTools.createTool(
                                ConsumerToolDraft(name: newName)
                            )
                            newName = ""
                            await reload()
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("vault.tools.manage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        tools = (try? await environment.consumerTools.tools(includeHidden: true)) ?? []
    }
}
