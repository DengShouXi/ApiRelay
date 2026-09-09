import SwiftUI
import SwiftData
import Combine

enum KeySaveResult: Equatable {
    case saved
    case possibleDuplicate(existingName: String)
    case failed
}

struct ReorderableNamedItem: Identifiable, Sendable {
    let id: UUID
    let title: String
    let symbolName: String
}

@MainActor
final class VaultHomeViewModel: ObservableObject {
    @Published var accounts: [UpstreamAccountDTO] = []
    @Published var tools: [ConsumerToolDTO] = []
    @Published var allKeys: [KeyRecordDTO] = []
    @Published var sections: [KeyGroupSection] = []
    @Published var groupingMode: GroupingMode = .byPlatform
    @Published var platformSectionSort: SectionSortPreference = .nameAscending
    @Published var consumerSectionSort: SectionSortPreference = .nameAscending
    @Published var remainingQuota: Int?
    /// 产品写死的默认头像；设置页不再提供改默认的入口。单条覆盖存在账号 / 使用方 / 密钥上。
    let avatarDefaults = AvatarPreferenceDefaults.builtIn
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    /// 提示弹窗的第二行说明。复制成功时装的是真实清除时长与该平台的清除边界。
    @Published var toastDetail: String?
    @Published var showQuotaAlert = false
    @Published var needsMasterPassword = false
    @Published var copySecondsRemaining: Int?
    /// 用户取消了进编辑时的门闩；此时 MUST NOT 进入编辑态。
    private(set) var revealWasCancelled = false

    let environment: AppEnvironment
    private let vault: any KeyVaultServing

    var environmentVault: any KeyVaultServing { vault }

    init(environment: AppEnvironment) {
        self.environment = environment
        self.vault = environment.vault
    }

    func onAppear() async {
        do {
            try await vault.performStartupMaintenance()
            try await environment.consumerTools.ensurePresetsSeeded()
            let prefs = try await environment.preferences.load()
            groupingMode = prefs.defaultGrouping
            platformSectionSort = prefs.platformSectionSort
            consumerSectionSort = prefs.consumerSectionSort
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        do {
            accounts = try await vault.accounts()
            tools = try await environment.consumerTools.tools(includeHidden: false)
            var keys: [KeyRecordDTO] = []
            for account in accounts {
                keys += try await vault.keys(in: account.id)
            }
            allKeys = keys
            rebuildSections()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // 额度状态依赖 StoreKit；失败不能把已经成功加载的密钥列表判成失败。
        do {
            remainingQuota = try await vault.remainingFreeQuota()
        } catch {
            remainingQuota = nil
        }
    }

    /// 「清除全部数据」后丢掉内存中的分区缓存，并按默认偏好重建列表。
    func handleUserDataDidErase() async {
        if let prefs = try? await environment.preferences.load() {
            groupingMode = prefs.defaultGrouping
            platformSectionSort = prefs.platformSectionSort
            consumerSectionSort = prefs.consumerSectionSort
        }
        toastMessage = nil
        toastDetail = nil
        await refresh()
    }

    func avatar(for key: KeyRecordDTO) -> AvatarChoice {
        AvatarCatalog.key(
            overrideSymbol: key.avatarSymbol,
            overrideColor: key.avatarColor,
            defaults: avatarDefaults
        )
    }

    func avatar(for account: UpstreamAccountDTO) -> AvatarChoice {
        AvatarCatalog.account(
            platform: account.platform,
            overrideSymbol: account.avatarSymbol,
            overrideColor: account.avatarColor,
            defaults: avatarDefaults
        )
    }

    func avatar(for tool: ConsumerToolDTO) -> AvatarChoice {
        AvatarCatalog.tool(
            name: tool.name,
            catalogSymbol: tool.iconSymbol,
            overrideSymbol: tool.avatarSymbol,
            overrideColor: tool.avatarColor,
            defaults: avatarDefaults
        )
    }

    func avatar(for section: KeyGroupSection) -> AvatarChoice {
        switch section.kind {
        case .platform(let accountId, _):
            if let account = accounts.first(where: { $0.id == accountId }) {
                return avatar(for: account)
            }
            return avatarDefaults.customAccount
        case .consumer(let toolId, _):
            if let tool = tools.first(where: { $0.id == toolId }) {
                return avatar(for: tool)
            }
            return avatarDefaults.customTool
        case .shared:
            return AvatarChoice(symbol: AppSymbols.Key.shared, color: .teal)
        case .unassigned:
            return AvatarChoice(symbol: AppSymbols.Key.unassigned, color: .slate)
        }
    }

    /// 切换当前列表视角（按平台 / 按使用方）。
    /// - Parameter persistAsDefault: 仅设置页改「默认分组视角」时为 true。
    ///   Tab 切换 MUST 传 false，否则会覆盖用户设好的启动默认值。
    func setGrouping(_ mode: GroupingMode, persistAsDefault: Bool = false) async {
        groupingMode = mode
        if persistAsDefault {
            var patch = PreferencesPatch()
            patch.defaultGrouping = mode
            try? await environment.preferences.update(patch)
        }
        await refresh()
    }

    var activeSectionSort: SectionSortPreference {
        groupingMode == .byPlatform ? platformSectionSort : consumerSectionSort
    }

    var reorderableSectionCount: Int {
        sections.filter {
            switch $0.kind {
            case .platform, .consumer: return true
            case .shared, .unassigned: return false
            }
        }.count
    }

    var sectionSortAccessibilityValue: String {
        let sort = activeSectionSort
        let criterion: String
        switch sort.criterion {
        case .name: criterion = String(localized: "vault.sort.criterion.name")
        case .createdAt: criterion = String(localized: "vault.sort.criterion.created")
        case .updatedAt: criterion = String(localized: "vault.sort.criterion.updated")
        case .custom: return String(localized: "vault.sort.criterion.custom")
        }
        let direction = String(
            localized: sort.ascending ? "vault.sort.ascending" : "vault.sort.descending"
        )
        return "\(criterion), \(direction)"
    }

    func reorderableSectionItems() -> [ReorderableNamedItem] {
        sections.compactMap { section in
            switch section.kind {
            case .platform(let id, let title):
                let platform = accounts.first { $0.id == id }?.platform ?? ""
                return ReorderableNamedItem(
                    id: id,
                    title: title,
                    symbolName: AppSymbols.platform(id: platform)
                )
            case .consumer(let id, let title):
                let tool = tools.first { $0.id == id }
                return ReorderableNamedItem(
                    id: id,
                    title: title,
                    symbolName: AppSymbols.tool(name: tool?.name ?? title, storedSymbol: tool?.iconSymbol)
                )
            case .shared, .unassigned:
                return nil
            }
        }
    }

    func selectSectionSortCriterion(_ criterion: SectionSortCriterion) async {
        let current = activeSectionSort
        if criterion == current.criterion { return }
        if criterion == .custom {
            await seedCustomOrderIfNeeded()
            assignActiveSort(SectionSortPreference(criterion: .custom, ascending: current.ascending))
        } else {
            assignActiveSort(.naturalDefault(for: criterion))
        }
        persistSectionSort()
        rebuildSections()
    }

    func setSectionSortAscending(_ ascending: Bool) {
        var current = activeSectionSort
        guard current.usesDirection, current.ascending != ascending else { return }
        current.ascending = ascending
        assignActiveSort(current)
        persistSectionSort()
        rebuildSections()
    }

    func reorderSections(orderedIds: [UUID]) async {
        do {
            switch groupingMode {
            case .byPlatform:
                try await vault.reorderAccounts(orderedIds: orderedIds)
            case .byConsumer:
                try await environment.consumerTools.reorderTools(orderedIds: orderedIds)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assignActiveSort(_ value: SectionSortPreference) {
        switch groupingMode {
        case .byPlatform: platformSectionSort = value
        case .byConsumer: consumerSectionSort = value
        }
    }

    private func persistSectionSort() {
        var patch = PreferencesPatch()
        patch.platformSectionSort = platformSectionSort
        patch.consumerSectionSort = consumerSectionSort
        environment.preferences.persist(patch)
    }

    private func seedCustomOrderIfNeeded() async {
        switch groupingMode {
        case .byPlatform:
            guard SectionSortPreference.needsCustomSeed(sortOrders: accounts.map(\.sortOrder)) else { return }
            let ids = sections.compactMap { section -> UUID? in
                if case .platform(let id, _) = section.kind { return id }
                return nil
            }
            try? await vault.reorderAccounts(orderedIds: ids)
            if let next = try? await vault.accounts() { accounts = next }
        case .byConsumer:
            guard SectionSortPreference.needsCustomSeed(sortOrders: tools.map(\.sortOrder)) else { return }
            let ids = sections.compactMap { section -> UUID? in
                if case .consumer(let id, _) = section.kind { return id }
                return nil
            }
            try? await environment.consumerTools.reorderTools(orderedIds: ids)
            if let next = try? await environment.consumerTools.tools(includeHidden: false) {
                tools = next
            }
        }
    }

    private func rebuildSections() {
        sections = KeyGrouping.group(
            keys: allKeys,
            accounts: accounts,
            tools: tools,
            mode: groupingMode,
            sectionSort: activeSectionSort
        )
    }

    @discardableResult
    func createAccount(
        platform: String,
        name: String,
        customPlatformName: String? = nil,
        customBaseURL: String?
    ) async -> UpstreamAccountDTO? {
        let isCustom = platform == PresetCatalog.customPlatformID
        let trimmedCustom = customPlatformName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isCustom, trimmedCustom.isEmpty {
            errorMessage = String(localized: "vault.account.customNameRequired")
            return nil
        }
        do {
            let id = try await vault.createAccount(UpstreamAccountDraft(
                platform: platform,
                customPlatformName: isCustom ? trimmedCustom : nil,
                displayName: name,
                customBaseURL: customBaseURL
            ))
            await refresh()
            return accounts.first { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createKey(accountId: UUID, name: String, secret: String, ackDuplicate: Bool, notes: String?) async -> KeySaveResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if trimmedName.isEmpty {
            let count = allKeys.filter { $0.accountId == accountId }.count
            resolvedName = String(localized: "vault.key.defaultName \(count + 1)")
        } else {
            resolvedName = trimmedName
        }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await vault.createKey(
                KeyDraft(
                    accountId: accountId,
                    displayName: resolvedName,
                    notes: (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
                ),
                secret: secret,
                acknowledgePossibleDuplicate: ackDuplicate
            )
            await refresh()
            return .saved
        } catch ApiRelayError.quotaExceededFreeTier {
            showQuotaAlert = true
            return .failed
        } catch let error as ApiRelayError {
            if let name = await duplicateKeyName(from: error) {
                return .possibleDuplicate(existingName: name)
            }
            errorMessage = error.localizedDescription
            return .failed
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    func editKey(
        keyId: UUID,
        name: String,
        secret: String?,
        ackDuplicate: Bool,
        notes: String?,
        accountName: String,
        platform: String,
        customPlatformName: String?,
        customBaseURL: String?,
        avatarSymbol: String?,
        avatarColor: String?
    ) async -> KeySaveResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = String(localized: "vault.key.edit.nameRequired")
            return .failed
        }
        let trimmedAccount = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else {
            errorMessage = String(localized: "vault.key.edit.accountRequired")
            return .failed
        }
        do {
            try await vault.editKey(
                keyId,
                draft: KeyEditDraft(
                    displayName: trimmedName,
                    secret: secret,
                    acknowledgePossibleDuplicate: ackDuplicate,
                    notes: notes,
                    accountDisplayName: trimmedAccount,
                    platform: platform,
                    customPlatformName: customPlatformName,
                    customBaseURL: customBaseURL,
                    avatarSymbol: avatarSymbol,
                    avatarColor: avatarColor
                )
            )
            await refresh()
            return .saved
        } catch let error as ApiRelayError {
            if let name = await duplicateKeyName(from: error) {
                return .possibleDuplicate(existingName: name)
            }
            errorMessage = error.localizedDescription
            return .failed
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    private func duplicateKeyName(from error: ApiRelayError) async -> String? {
        guard let id = error.possibleDuplicateKeyId else { return nil }
        let unnamed = String(localized: "vault.key.duplicate.unnamed")
        if let name = allKeys.first(where: { $0.id == id })?.displayName,
           !name.isEmpty {
            return name
        }
        if let key = try? await vault.keys(in: nil).first(where: { $0.id == id }),
           !key.displayName.isEmpty {
            return key.displayName
        }
        return unnamed
    }

    func updateAccount(
        id: UUID,
        platform: String,
        name: String,
        customPlatformName: String?,
        customBaseURL: String?,
        notes: String?,
        usesDefaultAvatar: Bool,
        avatar: AvatarChoice
    ) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = String(localized: "vault.key.edit.accountRequired")
            return false
        }
        let trimmedPlatform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlatform.isEmpty else {
            errorMessage = String(localized: "vault.account.edit.platformRequired")
            return false
        }
        let isCustom = trimmedPlatform == PresetCatalog.customPlatformID
        let trimmedCustom = customPlatformName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isCustom, trimmedCustom.isEmpty {
            errorMessage = String(localized: "vault.account.customNameRequired")
            return false
        }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            try await vault.updateAccount(
                id,
                patch: UpstreamAccountPatch(
                    platform: trimmedPlatform,
                    customPlatformName: isCustom ? trimmedCustom : "",
                    displayName: trimmedName,
                    customBaseURL: isCustom ? (customBaseURL ?? "") : "",
                    notes: trimmedNotes,
                    updatesAvatar: true,
                    avatarSymbol: usesDefaultAvatar ? nil : avatar.symbol,
                    avatarColor: usesDefaultAvatar ? nil : avatar.color.rawValue
                )
            )
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func renameTool(
        id: UUID,
        name: String,
        notes: String?,
        usesDefaultAvatar: Bool,
        avatar: AvatarChoice
    ) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "vault.consumer.edit.nameRequired")
            return false
        }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            var patch = ConsumerToolPatch()
            patch.name = trimmed
            patch.notes = trimmedNotes
            patch.updatesAvatar = true
            patch.avatarSymbol = usesDefaultAvatar ? nil : avatar.symbol
            patch.avatarColor = usesDefaultAvatar ? nil : avatar.color.rawValue
            try await environment.consumerTools.updateTool(id: id, patch: patch)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func assign(keyId: UUID, toolId: UUID) async {
        do {
            try await vault.addAssignment(keyId: keyId, consumerToolId: toolId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unassign(keyId: UUID, toolId: UUID) async {
        do {
            try await vault.removeAssignment(keyId: keyId, consumerToolId: toolId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderKeys(orderedIds: [UUID]) async {
        do {
            try await vault.reorderKeys(orderedIds: orderedIds)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 可指派到该使用方的密钥候选（排除已挂在该使用方上的）。
    /// - Parameter filter: `.unassignedOnly` 只含尚未指派给任何使用方的密钥；`.allowShared` 含全部其余密钥。
    func keysAssignable(to toolId: UUID, filter: AssignPickerFilter) -> [KeyRecordDTO] {
        let notOnThisTool = allKeys.filter { !$0.consumerToolIds.contains(toolId) }
        switch filter {
        case .unassignedOnly:
            return notOnThisTool.filter { $0.consumerToolIds.isEmpty }
        case .allowShared:
            return notOnThisTool
        }
    }

    func revealReturning(keyId: UUID, masterPassword: String?) async -> String? {
        needsMasterPassword = false
        revealWasCancelled = false
        do {
            return try await vault.revealSecret(
                keyId: keyId,
                purpose: .display,
                masterPassword: masterPassword
            )
        } catch let ApiRelayError.validationFailed(_, reason)
            where reason == "required" || reason == "master_password_prompt_required"
        {
            needsMasterPassword = true
            return nil
        } catch let ApiRelayError.validationFailed(_, reason)
            where reason == "master_password_not_set"
        {
            errorMessage = String(localized: "settings.policy.masterPassword.notConfigured")
            return nil
        } catch ApiRelayError.authenticationCancelled {
            revealWasCancelled = true
            return nil
        } catch ApiRelayError.secretMissingOnDevice {
            errorMessage = String(localized: "error.secretMissingOnDevice")
            return nil
        } catch let ApiRelayError.keychainFailure(status) where status == -25300 {
            errorMessage = String(localized: "error.secretMissingOnDevice")
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func copyReturning(keyId: UUID, masterPassword: String?) async -> Bool {
        needsMasterPassword = false
        do {
            try await vault.copySecretToClipboard(keyId: keyId, masterPassword: masterPassword)
            await announceCopied()
            return true
        } catch let ApiRelayError.validationFailed(_, reason)
            where reason == "required" || reason == "master_password_prompt_required"
        {
            needsMasterPassword = true
            return false
        } catch let ApiRelayError.validationFailed(_, reason)
            where reason == "master_password_not_set"
        {
            errorMessage = String(localized: "settings.policy.masterPassword.notConfigured")
            return false
        } catch ApiRelayError.authenticationCancelled {
            return false
        } catch ApiRelayError.secretMissingOnDevice {
            toastDetail = nil
            toastMessage = String(localized: "error.secretMissingOnDevice")
            return false
        } catch let ApiRelayError.keychainFailure(status) where status == -25300 {
            toastDetail = nil
            toastMessage = String(localized: "error.secretMissingOnDevice")
            return false
        } catch {
            toastDetail = nil
            toastMessage = String(localized: "vault.copy.failed")
            return false
        }
    }

    func copyRevealedSecret(_ secret: String) async {
        do {
            try await vault.copyRevealedSecretToClipboard(secret)
            await announceCopied()
        } catch {
            toastDetail = nil
            toastMessage = String(localized: "vault.copy.failed")
        }
    }

    /// 复制成功提示。剩余时长 MUST 取设置里的真实值，MUST NOT 写死；
    /// Mac 与 iPhone 的清除边界不同，说明也分开写。
    private func announceCopied() async {
        let prefs = try? await environment.preferences.load()
        let enabled = prefs?.clipboardClearEnabled ?? true
        let seconds = prefs?.clipboardClearSeconds
        copySecondsRemaining = enabled ? seconds : nil
        toastMessage = String(localized: "vault.copied.toast")
        toastDetail = Self.copiedDetail(seconds: seconds, enabled: enabled)
    }

    static func copiedDetail(seconds: Int?, enabled: Bool = true) -> String? {
        guard enabled else {
            #if os(macOS) || targetEnvironment(macCatalyst)
            return String(localized: "vault.copied.detail.off.mac")
            #else
            return String(localized: "vault.copied.detail.off")
            #endif
        }
        guard let seconds else { return nil }
        #if os(macOS) || targetEnvironment(macCatalyst)
        return String(localized: "vault.copied.detail.mac \(seconds)")
        #else
        return String(localized: "vault.copied.detail.ios \(seconds)")
        #endif
    }

    func copy(keyId: UUID, masterPassword: String?) async {
        _ = await copyReturning(keyId: keyId, masterPassword: masterPassword)
    }

    func deleteKey(_ id: UUID) async {
        do {
            try await vault.deleteKey(id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRecentlyDeleted() async -> [KeyRecordDTO] {
        do {
            return try await vault.recentlyDeletedKeys()
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func loadRecentlyDeletedBundle() async throws -> (
        keys: [KeyRecordDTO],
        accounts: [UpstreamAccountDTO],
        tools: [ConsumerToolDTO]
    ) {
        let keys = try await vault.recentlyDeletedKeys()
        let accounts = try await vault.recentlyDeletedAccounts()
        let tools = try await environment.consumerTools.recentlyDeletedTools()
        return (keys, accounts, tools)
    }

    func restoreTrashBatch(_ selection: TrashBatchSelection) async -> Result<TrashBatchOutcome, Error> {
        do {
            let outcome = try await environment.trashBatch.restore(selection)
            await refresh()
            return .success(outcome)
        } catch {
            return .failure(error)
        }
    }

    func permanentlyDeleteTrashBatch(
        _ selection: TrashBatchSelection
    ) async -> Result<TrashBatchOutcome, Error> {
        do {
            let outcome = try await environment.trashBatch.permanentlyDelete(selection)
            await refresh()
            return .success(outcome)
        } catch {
            return .failure(error)
        }
    }

    func restoreKey(_ id: UUID) async {
        do {
            try await vault.restoreKey(id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func permanentlyDeleteKey(_ id: UUID) async {
        do {
            try await vault.permanentlyDeleteKey(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount(_ id: UUID) async {
        do {
            try await vault.deleteAccount(id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreAccount(_ id: UUID) async {
        do {
            try await vault.restoreAccount(id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func permanentlyDeleteAccount(_ id: UUID) async {
        do {
            try await vault.permanentlyDeleteAccount(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createTool(name: String) async -> ConsumerToolDTO? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: String
        if trimmed.isEmpty {
            let count = tools.filter { !$0.isPreset }.count
            resolved = String(localized: "vault.consumer.defaultName \(count + 1)")
        } else {
            resolved = trimmed
        }
        do {
            let base = PresetCatalog.consumerTools.first { resolved == $0.name || resolved.hasPrefix("\($0.name) · ") || resolved.hasPrefix("\($0.name) - ") }?.name
            let icon = PresetCatalog.toolIconForNewBase(base ?? resolved)
            let id = try await environment.consumerTools.createTool(
                ConsumerToolDraft(name: resolved, iconSymbol: icon)
            )
            await refresh()
            return tools.first { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteTool(_ id: UUID) async {
        do {
            try await environment.consumerTools.deleteTool(id: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreTool(_ id: UUID) async {
        do {
            try await environment.consumerTools.restoreTool(id: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func permanentlyDeleteTool(_ id: UUID) async {
        do {
            try await environment.consumerTools.permanentlyDeleteTool(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 刷新并等待本次可观测的 CloudKit 活动；明文仍由钥匙串自行同步。
    func requestSyncNow() async -> CloudSyncNowOutcome {
        let outcome = await environment.cloudSync.requestMetadataSync()
        await refresh()
        return outcome
    }
}
