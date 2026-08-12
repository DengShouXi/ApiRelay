import SwiftUI
import SwiftData
import Combine

@MainActor
final class VaultHomeViewModel: ObservableObject {
    @Published var accounts: [UpstreamAccountDTO] = []
    @Published var tools: [ConsumerToolDTO] = []
    @Published var allKeys: [KeyRecordDTO] = []
    @Published var sections: [KeyGroupSection] = []
    @Published var groupingMode: GroupingMode = .byPlatform
    @Published var remainingQuota: Int?
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var showQuotaAlert = false
    @Published var needsMasterPassword = false
    @Published var copySecondsRemaining: Int?

    let environment: AppEnvironment
    private let vault: KeyVaultService

    var environmentVault: KeyVaultService { vault }

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
            sections = KeyGrouping.group(
                keys: keys,
                accounts: accounts,
                tools: tools,
                mode: groupingMode
            )
            remainingQuota = try await vault.remainingFreeQuota()
        } catch {
            errorMessage = error.localizedDescription
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

    @discardableResult
    func createAccount(platform: String, name: String, customBaseURL: String?) async -> UpstreamAccountDTO? {
        do {
            let id = try await vault.createAccount(UpstreamAccountDraft(
                platform: platform,
                customPlatformName: platform == PresetCatalog.customPlatformID ? name : nil,
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

    func createKey(accountId: UUID, name: String, secret: String, ackDuplicate: Bool, notes: String?) async -> Bool {
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
            return true
        } catch ApiRelayError.quotaExceededFreeTier {
            showQuotaAlert = true
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
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
        customBaseURL: String?
    ) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = String(localized: "vault.key.edit.nameRequired")
            return false
        }
        let trimmedAccount = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else {
            errorMessage = String(localized: "vault.key.edit.accountRequired")
            return false
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
                    customBaseURL: customBaseURL
                )
            )
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateAccount(
        id: UUID,
        platform: String,
        name: String,
        customBaseURL: String?,
        notes: String?
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
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            try await vault.updateAccount(
                id,
                patch: UpstreamAccountPatch(
                    platform: trimmedPlatform,
                    customPlatformName: isCustom ? trimmedName : "",
                    displayName: trimmedName,
                    customBaseURL: isCustom ? (customBaseURL ?? "") : "",
                    notes: trimmedNotes
                )
            )
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func renameTool(id: UUID, name: String, notes: String?) async -> Bool {
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
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func copyReturning(keyId: UUID, masterPassword: String?) async -> Bool {
        needsMasterPassword = false
        do {
            try await vault.copySecretToClipboard(keyId: keyId, masterPassword: masterPassword)
            copySecondsRemaining = 120
            toastMessage = String(localized: "vault.copied.toast")
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
        } catch {
            toastMessage = String(localized: "vault.copy.failed")
            return false
        }
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

    /// 立即同步（尽力而为）：提交本机待写入变更并刷新列表。
    /// 元数据经 CloudKit 由系统后台继续同步；密钥明文由 iCloud 钥匙串自行同步，App 无法强制加速。
    func requestSyncNow() async -> SyncNowOutcome {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return .unavailable
        }
        do {
            let context = environment.modelContainer.mainContext
            if context.hasChanges {
                try context.save()
            }
            await refresh()
            return .success
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

enum SyncNowOutcome: Equatable {
    case success
    case unavailable
    case failed(String)
}
