import SwiftUI

struct VaultHomeView: View {
    @ObservedObject var viewModel: VaultHomeViewModel
    @State private var showAddAccount = false
    @State private var showAddKeyFor: UpstreamAccountDTO?
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

    var body: some View {
        NavigationStack {
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
                    Section(sectionTitle(section)) {
                        ForEach(section.keys) { key in
                            keyRow(key)
                        }
                    }
                }
            }
            .navigationTitle("vault.title")
            .toolbar {
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
                        showAddAccount = true
                    } label: {
                        Label("vault.account.add", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
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
            .task { await viewModel.onAppear() }
            .alert("vault.error.title", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("gate.cancel", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("vault.quota.exceeded.title", isPresented: $viewModel.showQuotaAlert) {
                Button("vault.paywall.open") { showPaywall = true }
                Button("gate.cancel", role: .cancel) {}
            } message: {
                Text("vault.quota.exceeded.body")
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountSheet { platform, name, url in
                    await viewModel.createAccount(platform: platform, name: name, customBaseURL: url)
                }
            }
            .sheet(item: $showAddKeyFor) { account in
                AddKeySheet(accountName: account.displayName) { name, secret, ack in
                    await viewModel.createKey(accountId: account.id, name: name, secret: secret, ackDuplicate: ack)
                }
            }
            .sheet(isPresented: $showRecentlyDeleted) {
                RecentlyDeletedView(vault: viewModel)
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
    private func keyRow(_ key: KeyRecordDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(key.displayName)
                if key.consumerToolIds.count >= 2 {
                    Text("vault.shared.badge \(key.consumerToolIds.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            Text(maskLabel(key))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack {
                Button("vault.reveal") { Task { await beginReveal(key.id) } }
                    .disabled(!key.secretAvailable)
                Button("vault.copy") { Task { await beginCopy(key.id) } }
                    .disabled(!key.secretAvailable)
                Button("vault.assign") { assignKeyId = key.id }
                Button("vault.key.add") {
                    if let account = viewModel.accounts.first(where: { $0.id == key.accountId }) {
                        showAddKeyFor = account
                    }
                }
                Spacer()
                Button("vault.delete", role: .destructive) {
                    Task { await viewModel.deleteKey(key.id) }
                }
            }
            .buttonStyle(.borderless)
        }
        .contextMenu {
            Button("vault.copy") { Task { await beginCopy(key.id) } }
            Button("vault.assign") { assignKeyId = key.id }
            Button("vault.delete", role: .destructive) {
                Task { await viewModel.deleteKey(key.id) }
            }
        }
    }

    private func maskLabel(_ key: KeyRecordDTO) -> String {
        if !key.secretAvailable { return String(localized: "vault.secret.missing") }
        if let hint = key.maskedHint { return "••••\(hint)" }
        return "••••"
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

// MARK: - Sheets

private struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var platform = "openai"
    @State private var name = ""
    @State private var customURL = ""
    let onSave: (String, String, String?) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("vault.account.platform", selection: $platform) {
                    ForEach(PresetCatalog.platforms, id: \.id) { p in
                        Text(p.displayName).tag(p.id)
                    }
                    Text("vault.custom.platform").tag(PresetCatalog.customPlatformID)
                }
                TextField("vault.account.name", text: $name)
                if platform == PresetCatalog.customPlatformID {
                    TextField("vault.account.baseURL", text: $customURL)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("vault.account.add")
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
}

private struct AddKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let accountName: String
    let onSave: (String, String, Bool) async -> Void
    @State private var name = ""
    @State private var secret = ""
    @State private var ackDuplicate = false

    var body: some View {
        NavigationStack {
            Form {
                Text(accountName).foregroundStyle(.secondary)
                TextField("vault.key.name", text: $name)
                SecureField("vault.key.secret", text: $secret)
                    .autocorrectionDisabled()
                Toggle("vault.key.ackDuplicate", isOn: $ackDuplicate)
            }
            .navigationTitle("vault.key.add")
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
                    .disabled(name.isEmpty || secret.isEmpty)
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
    @State private var items: [KeyRecordDTO] = []

    var body: some View {
        NavigationStack {
            List(items) { key in
                VStack(alignment: .leading) {
                    Text(key.displayName)
                    if let purge = key.purgeAfter {
                        Text(purge, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("vault.restore") {
                            Task {
                                try? await vault.environmentVault.restoreKey(key.id)
                                await reload()
                                await vault.refresh()
                            }
                        }
                        Button("vault.delete.forever", role: .destructive) {
                            Task {
                                try? await vault.environmentVault.permanentlyDeleteKey(key.id)
                                await reload()
                                await vault.refresh()
                            }
                        }
                    }
                }
            }
            .navigationTitle("vault.recentlyDeleted")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        items = (try? await vault.environmentVault.recentlyDeletedKeys()) ?? []
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
                        if tool.isPreset {
                            Text("vault.tools.preset").font(.caption2).foregroundStyle(.secondary)
                        }
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
                        if !tool.isPreset {
                            Button("vault.delete", role: .destructive) {
                                Task {
                                    try? await environment.consumerTools.deleteTool(id: tool.id)
                                    await reload()
                                }
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
