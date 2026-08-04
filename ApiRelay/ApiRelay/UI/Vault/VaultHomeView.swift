import SwiftUI

struct VaultHomeView: View {
    @ObservedObject var viewModel: VaultHomeViewModel
    @State private var showAddAccount = false
    @State private var showAddKeyFor: UpstreamAccountDTO?
    @State private var revealText: String?
    @State private var masterPasswordInput = ""
    @State private var pendingRevealKeyId: UUID?
    @State private var pendingCopyKeyId: UUID?
    @State private var showMasterPrompt = false
    @State private var showRecentlyDeleted = false

    var body: some View {
        NavigationStack {
            List {
                if let quota = viewModel.remainingQuota {
                    Section {
                        Text("vault.quota.remaining \(quota)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(viewModel.accounts) { account in
                    Section(account.displayName) {
                        let keys = viewModel.keysByAccount[account.id] ?? []
                        if keys.isEmpty {
                            Text("vault.keys.empty")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(keys) { key in
                            keyRow(key)
                        }
                        Button("vault.key.add") {
                            showAddKeyFor = account
                        }
                    }
                }
            }
            .navigationTitle("vault.title")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddAccount = true
                    } label: {
                        Label("vault.account.add", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("vault.recentlyDeleted") {
                        showRecentlyDeleted = true
                    }
                }
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
                Button("gate.cancel", role: .cancel) {}
            } message: {
                Text("vault.quota.exceeded.body")
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountSheet { platform, name in
                    await viewModel.createAccount(platform: platform, name: name)
                }
            }
            .sheet(item: $showAddKeyFor) { account in
                AddKeySheet(accountName: account.displayName) { name, secret, ack in
                    await viewModel.createKey(
                        accountId: account.id,
                        name: name,
                        secret: secret,
                        ackDuplicate: ack
                    )
                }
            }
            .sheet(isPresented: $showRecentlyDeleted) {
                RecentlyDeletedView(vault: viewModel)
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

    @ViewBuilder
    private func keyRow(_ key: KeyRecordDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key.displayName)
            Text(maskLabel(key))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack {
                Button("vault.reveal") {
                    Task { await beginReveal(key.id) }
                }
                .disabled(!key.secretAvailable)
                Button("vault.copy") {
                    Task { await beginCopy(key.id) }
                }
                .disabled(!key.secretAvailable)
                Spacer()
                Button("vault.delete", role: .destructive) {
                    Task { await viewModel.deleteKey(key.id) }
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func maskLabel(_ key: KeyRecordDTO) -> String {
        if !key.secretAvailable {
            return String(localized: "vault.secret.missing")
        }
        if let hint = key.maskedHint {
            return "••••\(hint)"
        }
        return "••••"
    }

    private func beginReveal(_ id: UUID) async {
        // 默认策略：直接尝试；若需要主密码则弹出
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

private struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var platform = "openai"
    @State private var name = ""
    let onSave: (String, String) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("vault.account.platform", selection: $platform) {
                    ForEach(PresetCatalog.platforms, id: \.id) { p in
                        Text(p.displayName).tag(p.id)
                    }
                }
                TextField("vault.account.name", text: $name)
            }
            .navigationTitle("vault.account.add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            await onSave(platform, name)
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
                    #if os(iOS) || targetEnvironment(macCatalyst)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
                    .keyboardType(.asciiCapable)
                    #endif
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
                    Button("vault.confirm") {
                        Task { await onConfirm() }
                    }
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
                        Text(purge, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
