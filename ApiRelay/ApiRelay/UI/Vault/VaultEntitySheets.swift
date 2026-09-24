import SwiftUI

// MARK: - Sheets

struct AssignKeySheetTarget: Identifiable {
    let id: UUID
}

struct AssignToToolSheetTarget: Identifiable {
    let id: UUID
    let name: String
}

struct ReorderKeysTarget: Identifiable {
    let id = UUID()
    let title: String
    let keys: [KeyRecordDTO]
}

struct ReorderSectionsTarget: Identifiable {
    enum Kind {
        case accounts
        case tools
    }

    let id = UUID()
    let kind: Kind
    let items: [ReorderableNamedItem]

    var navigationTitle: String {
        switch kind {
        case .accounts: String(localized: "vault.reorder.accounts.title")
        case .tools: String(localized: "vault.reorder.tools.title")
        }
    }
}

/// Mac / Catalyst 上系统编辑态常常不画出抓手，自行画三条杠；iPhone 仍用系统自带的排序控件。
private struct ReorderDragHandle: View {
    var body: some View {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        EmptyView()
        #else
        Image(systemName: AppSymbols.Action.reorderHandle)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
        #endif
    }
}

struct ReorderNamedItemsSheet: View {
    let title: String
    let onSave: ([UUID]) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReorderableNamedItem]
    @State private var persistTask: Task<Void, Never>?

    init(
        title: String,
        initialItems: [ReorderableNamedItem],
        onSave: @escaping ([UUID]) async -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _items = State(initialValue: initialItems)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("vault.reorder.keys.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.symbolName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.accentColor)
                                )
                                .accessibilityHidden(true)
                            Text(item.title)
                            Spacer(minLength: 8)
                            ReorderDragHandle()
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove(perform: move)
                }
            }
            #if os(iOS) || targetEnvironment(macCatalyst)
            .environment(\.editMode, .constant(.active))
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.done") { dismiss() }
                }
            }
            .onDisappear { persistTask?.cancel() }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 440, minHeight: 420, idealHeight: 480)
        #endif
    }

    private func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        persistTask?.cancel()
        persistTask = Task {
            await onSave(items.map(\.id))
        }
    }
}

struct AssignKeyToConsumerSheet: View {
    let keyId: UUID
    @ObservedObject var viewModel: VaultHomeViewModel
    @Environment(\.dismiss) private var dismiss

    private var key: KeyRecordDTO? {
        viewModel.allKeys.first { $0.id == keyId }
    }

    private var tools: [ConsumerToolDTO] {
        viewModel.tools.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("vault.assign.pick.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if tools.isEmpty {
                    Section {
                        Text("vault.assign.noConsumer")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(tools) { tool in
                            let alreadyAssigned = key?.consumerToolIds.contains(tool.id) == true
                            Button {
                                guard !alreadyAssigned else { return }
                                Task {
                                    await viewModel.assign(keyId: keyId, toolId: tool.id)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: AppSymbols.tool(name: tool.name, storedSymbol: tool.iconSymbol))
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.accentColor)
                                        )
                                        .accessibilityHidden(true)
                                    Text(tool.name)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    if alreadyAssigned {
                                        Image(systemName: AppSymbols.Action.checkmark)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityLabel(Text("vault.assign.alreadyHere"))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyAssigned)
                        }
                    }
                }
            }
            .navigationTitle("vault.assign.title")
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 360, idealHeight: 440)
        #endif
        .settingsTaskSheet()
    }
}

struct AssignExistingKeySheet: View {
    let toolName: String
    let toolId: UUID
    @ObservedObject var viewModel: VaultHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter: AssignPickerFilter = .allowShared
    @State private var searchText = ""

    private var candidates: [KeyRecordDTO] {
        let base = viewModel.keysAssignable(to: toolId, filter: filter)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { key in
            if key.displayName.localizedCaseInsensitiveContains(query) { return true }
            let account = viewModel.accounts.first { $0.id == key.accountId }?.displayName ?? ""
            return account.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(filter == .unassignedOnly
                         ? "vault.assign.sheet.filter.unassignedOnly.hint"
                         : "vault.assign.sheet.filter.allowShared.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if candidates.isEmpty {
                    Section {
                        Text(emptyMessage)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(candidates) { key in
                            Button {
                                Task {
                                    await viewModel.assign(keyId: key.id, toolId: toolId)
                                    dismiss()
                                }
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(key.displayName)
                                                .foregroundStyle(.primary)
                                            if key.consumerToolIds.count >= 1 {
                                                Text("vault.assign.badge.count \(key.consumerToolIds.count)")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.tint)
                                            }
                                        }
                                        Text(accountName(for: key))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: AppSymbols.Action.addFilled)
                                        .foregroundStyle(Color.accentColor)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "vault.assign.sheet.title \(toolName)"))
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: Text("vault.assign.sheet.search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
            .task {
                if let prefs = try? await viewModel.environment.preferences.load() {
                    filter = prefs.assignPickerFilter
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 520)
        #endif
    }

    private var emptyMessage: LocalizedStringKey {
        if filter == .unassignedOnly {
            return "vault.assign.sheet.empty.unassignedOnly"
        }
        return "vault.assign.sheet.empty.allowShared"
    }

    private func accountName(for key: KeyRecordDTO) -> String {
        viewModel.accounts.first { $0.id == key.accountId }?.displayName ?? "—"
    }
}

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingAccounts: [UpstreamAccountDTO]
    @State private var platform = "openai"
    @State private var customPlatformName = ""
    @State private var instanceLabel = ""
    @State private var lastSuggestedInstance = ""
    @State private var customURL = ""
    let onSave: (String, String, String?, String?) async -> Void

    private var isCustom: Bool {
        platform == PresetCatalog.customPlatformID
    }

    private var resolvedPlatformName: String {
        if isCustom {
            return customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return PresetCatalog.platform(id: platform)?.displayName
            ?? String(localized: "vault.custom.platform")
    }

    private var resolvedDisplayName: String {
        let instance = instanceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let platformName = resolvedPlatformName
        if platformName.isEmpty { return "" }
        if instance.isEmpty { return platformName }
        return String(localized: "vault.consumer.compoundName \(platformName) \(instance)")
    }

    private var canSave: Bool {
        !resolvedPlatformName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("vault.account.platform", selection: $platform) {
                    ForEach(PresetCatalog.platforms, id: \.id) { p in
                        Label(p.displayName, systemImage: p.iconSymbol).tag(p.id)
                    }
                    Label("vault.custom.platform", systemImage: AppSymbols.platform(id: PresetCatalog.customPlatformID))
                        .tag(PresetCatalog.customPlatformID)
                }
                .pickerStyle(.menu)
                if isCustom {
                    TextField("vault.account.platformName", text: $customPlatformName)
                }
                TextField("vault.account.instance", text: $instanceLabel)
                if isCustom {
                    Text("vault.account.name.hint.custom")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("vault.account.name.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("vault.consumer.preview") {
                    Text(resolvedDisplayName.isEmpty ? "—" : resolvedDisplayName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if isCustom {
                    TextField("vault.account.baseURL", text: $customURL)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("vault.account.add")
            .onAppear { applyInstanceSuggestion(force: true) }
            .onChange(of: platform) { _, newValue in
                if newValue == PresetCatalog.customPlatformID {
                    customPlatformName = ""
                    instanceLabel = ""
                    lastSuggestedInstance = ""
                } else {
                    customPlatformName = ""
                    refreshInstanceSuggestionIfNeeded()
                }
            }
            .onChange(of: customPlatformName) { _, _ in
                guard isCustom else { return }
                refreshInstanceSuggestionIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            let trimmedCustom = customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
                            await onSave(
                                platform,
                                resolvedDisplayName,
                                isCustom ? trimmedCustom : nil,
                                isCustom ? customURL : nil
                            )
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func refreshInstanceSuggestionIfNeeded() {
        let trimmed = instanceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || instanceLabel == lastSuggestedInstance {
            applyInstanceSuggestion(force: true)
        }
    }

    /// 同一平台下递增：第一份默认「账号 1」。自定义须先有平台名才建议。
    private func applyInstanceSuggestion(force: Bool) {
        let base = resolvedPlatformName
        guard !base.isEmpty else {
            if force {
                instanceLabel = ""
                lastSuggestedInstance = ""
            }
            return
        }
        let count: Int
        if isCustom {
            count = existingAccounts.filter {
                $0.platform == platform
                    && ($0.customPlatformName ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines) == base
            }.count
        } else {
            count = existingAccounts.filter { $0.platform == platform }.count
        }
        let suggested = String(localized: "vault.account.instanceDefault \(count + 1)")
        if force || instanceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            instanceLabel = suggested
            lastSuggestedInstance = suggested
        }
    }
}

struct AddConsumerToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingTools: [ConsumerToolDTO]
    /// 空字符串 = 完全自定义；否则为预置显示名（如 VS Code）。
    @State private var baseName = "VS Code"
    @State private var customSoftwareName = ""
    @State private var deviceLabel = ""
    @State private var lastSuggestedDevice = ""
    let onSave: (String) async -> Void

    private var customBaseTag: String { "" }

    private var isCustom: Bool {
        baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedSoftwareName: String {
        if isCustom {
            return customSoftwareName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return baseName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedDisplayName: String {
        let device = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let software = resolvedSoftwareName
        if software.isEmpty { return "" }
        if device.isEmpty { return software }
        return String(localized: "vault.consumer.compoundName \(software) \(device)")
    }

    private var canSave: Bool {
        !resolvedSoftwareName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("vault.consumer.base", selection: $baseName) {
                    ForEach(PresetCatalog.consumerTools, id: \.name) { tool in
                        Label(
                            tool.name,
                            systemImage: AppSymbols.tool(name: tool.name, storedSymbol: tool.iconSymbol)
                        )
                            .tag(tool.name)
                    }
                    Label("vault.consumer.base.custom", systemImage: AppSymbols.Entity.toolCustom)
                        .tag(customBaseTag)
                }
                if isCustom {
                    TextField("vault.consumer.software", text: $customSoftwareName)
                }
                TextField("vault.consumer.device", text: $deviceLabel)
                if isCustom {
                    Text("vault.consumer.name.hint.custom")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("vault.consumer.name.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("vault.consumer.preview") {
                    Text(resolvedDisplayName.isEmpty ? "—" : resolvedDisplayName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("vault.consumer.add")
            .onAppear { applyDeviceSuggestion(force: true) }
            .onChange(of: baseName) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customSoftwareName = ""
                    deviceLabel = ""
                    lastSuggestedDevice = ""
                } else {
                    customSoftwareName = ""
                    refreshDeviceSuggestionIfNeeded()
                }
            }
            .onChange(of: customSoftwareName) { _, _ in
                guard isCustom else { return }
                refreshDeviceSuggestionIfNeeded()
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
                    .disabled(!canSave)
                }
            }
        }
    }

    private func refreshDeviceSuggestionIfNeeded() {
        let trimmed = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || deviceLabel == lastSuggestedDevice {
            applyDeviceSuggestion(force: true)
        }
    }

    /// 同一软件名下递增：第一台设备默认「电脑 1」。自定义须先有软件名才建议。
    private func applyDeviceSuggestion(force: Bool) {
        let base = resolvedSoftwareName
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

struct EditAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let account: UpstreamAccountDTO
    let avatarDefaults: AvatarPreferenceDefaults
    let onSave: (
        _ platform: String,
        _ name: String,
        _ customPlatformName: String?,
        _ customBaseURL: String?,
        _ notes: String?,
        _ usesDefaultAvatar: Bool,
        _ avatar: AvatarChoice
    ) async -> Bool

    @State private var platform: String
    @State private var customPlatformName: String
    @State private var name: String
    @State private var customURL: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var usesDefaultAvatar: Bool
    @State private var customAvatar: AvatarChoice
    @State private var showAvatarEditor = false

    init(
        account: UpstreamAccountDTO,
        avatarDefaults: AvatarPreferenceDefaults,
        onSave: @escaping (
            _ platform: String,
            _ name: String,
            _ customPlatformName: String?,
            _ customBaseURL: String?,
            _ notes: String?,
            _ usesDefaultAvatar: Bool,
            _ avatar: AvatarChoice
        ) async -> Bool
    ) {
        self.account = account
        self.avatarDefaults = avatarDefaults
        self.onSave = onSave
        _platform = State(initialValue: account.platform)
        _customPlatformName = State(initialValue: account.customPlatformName ?? "")
        _name = State(initialValue: account.displayName)
        _customURL = State(initialValue: account.customBaseURL ?? "")
        _notes = State(initialValue: account.notes ?? "")
        let override = AvatarChoice.parse(symbol: account.avatarSymbol, color: account.avatarColor)
        _usesDefaultAvatar = State(initialValue: override == nil)
        _customAvatar = State(
            initialValue: override ?? AvatarCatalog.accountDefault(platform: account.platform, defaults: avatarDefaults)
        )
    }

    private var isCustom: Bool {
        platform == PresetCatalog.customPlatformID
    }

    private var selectedPlatformLabel: String {
        PresetCatalog.platform(id: platform)?.displayName
            ?? String(localized: "vault.custom.platform")
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
        if isCustom {
            return hasName && !customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasName
    }

    private var displayedAvatar: AvatarChoice {
        usesDefaultAvatar
            ? AvatarCatalog.accountDefault(platform: platform, defaults: avatarDefaults)
            : customAvatar
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .center, spacing: 14) {
                        EditableAvatarButton(choice: displayedAvatar) {
                            showAvatarEditor = true
                        }
                        TextField("vault.account.name", text: $name)
                            .font(.title3.weight(.semibold))
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
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
                    if isCustom {
                        TextField("vault.account.platformName", text: $customPlatformName)
                    } else {
                        LabeledContent("vault.account.platform.selected") {
                            Text(selectedPlatformLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if isCustom {
                        TextField("vault.account.baseURL", text: $customURL)
                            .autocorrectionDisabled()
                    }
                    Text("vault.account.edit.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("vault.account.notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                    Text("vault.account.notes.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("vault.account.edit")
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
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            let trimmedCustom = customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let ok = await onSave(
                                platform,
                                name,
                                isCustom ? trimmedCustom : nil,
                                isCustom ? customURL : nil,
                                notes,
                                usesDefaultAvatar,
                                customAvatar
                            )
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showAvatarEditor) {
                NavigationStack {
                    Form {
                        Section {
                            AvatarOverrideEditor(
                                defaultChoice: AvatarCatalog.accountDefault(
                                    platform: platform,
                                    defaults: avatarDefaults
                                ),
                                usesDefault: $usesDefaultAvatar,
                                customChoice: $customAvatar
                            )
                            .buttonStyle(.borderless)
                        }
                    }
                    .navigationTitle("vault.avatar")
                    #if os(iOS) || targetEnvironment(macCatalyst)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("vault.avatar.done") { showAvatarEditor = false }
                        }
                    }
                }
                #if os(macOS) || targetEnvironment(macCatalyst)
                .frame(minWidth: 400, minHeight: 480)
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 440)
        #endif
    }
}

struct EditConsumerToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tool: ConsumerToolDTO
    let avatarDefaults: AvatarPreferenceDefaults
    let onSave: (_ name: String, _ notes: String?, _ usesDefaultAvatar: Bool, _ avatar: AvatarChoice) async -> Bool

    @State private var name: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var usesDefaultAvatar: Bool
    @State private var customAvatar: AvatarChoice

    init(
        tool: ConsumerToolDTO,
        avatarDefaults: AvatarPreferenceDefaults,
        onSave: @escaping (_ name: String, _ notes: String?, _ usesDefaultAvatar: Bool, _ avatar: AvatarChoice) async -> Bool
    ) {
        self.tool = tool
        self.avatarDefaults = avatarDefaults
        self.onSave = onSave
        _name = State(initialValue: tool.name)
        _notes = State(initialValue: tool.notes ?? "")
        let override = AvatarChoice.parse(symbol: tool.avatarSymbol, color: tool.avatarColor)
        _usesDefaultAvatar = State(initialValue: override == nil)
        _customAvatar = State(
            initialValue: override ?? AvatarCatalog.toolDefault(
                name: tool.name,
                catalogSymbol: tool.iconSymbol,
                defaults: avatarDefaults
            )
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("vault.consumer.name", text: $name)
                    Text("vault.consumer.edit.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("vault.avatar") {
                    AvatarOverrideEditor(
                        defaultChoice: AvatarCatalog.toolDefault(
                            name: name,
                            catalogSymbol: tool.iconSymbol,
                            defaults: avatarDefaults
                        ),
                        usesDefault: $usesDefaultAvatar,
                        customChoice: $customAvatar
                    )
                    .buttonStyle(.borderless)
                }
                Section {
                    TextField("vault.consumer.notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                    Text("vault.consumer.notes.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("vault.consumer.edit")
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
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            if await onSave(name, notes, usesDefaultAvatar, customAvatar) { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 600)
        #endif
    }
}

struct AddKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let accountName: String
    let existingKeyCount: Int
    let onSave: (String, String, Bool, String?) async -> KeySaveResult
    @State private var name = ""
    @State private var secret = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var duplicateExistingName: String?

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
                TextField("vault.key.notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
                Text("vault.key.notes.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task { await persist(acknowledgeDuplicate: false) }
                    }
                    .disabled(isSaving || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .vaultPossibleDuplicateAlert(existingName: $duplicateExistingName) {
                await persist(acknowledgeDuplicate: true)
            }
        }
    }

    private func persist(acknowledgeDuplicate: Bool) async {
        isSaving = true
        defer { isSaving = false }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await onSave(
            name,
            secret,
            acknowledgeDuplicate,
            trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        switch result {
        case .saved:
            secret = ""
            dismiss()
        case .possibleDuplicate(let existingName):
            duplicateExistingName = existingName
        case .failed:
            break
        }
    }
}
