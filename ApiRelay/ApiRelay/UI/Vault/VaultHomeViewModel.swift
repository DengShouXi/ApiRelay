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

    func setGrouping(_ mode: GroupingMode) async {
        groupingMode = mode
        var patch = PreferencesPatch()
        patch.defaultGrouping = mode
        try? await environment.preferences.update(patch)
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

    func createKey(accountId: UUID, name: String, secret: String, ackDuplicate: Bool) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if trimmedName.isEmpty {
            let count = allKeys.filter { $0.accountId == accountId }.count
            resolvedName = String(localized: "vault.key.defaultName \(count + 1)")
        } else {
            resolvedName = trimmedName
        }
        do {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: resolvedName),
                secret: secret,
                acknowledgePossibleDuplicate: ackDuplicate
            )
            await refresh()
        } catch let ApiRelayError.quotaExceededFreeTier {
            showQuotaAlert = true
        } catch {
            errorMessage = error.localizedDescription
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

    /// 尚未指派到该使用端的密钥（仍可挂到其他使用端，一钥多端）。
    func keysAssignable(to toolId: UUID) -> [KeyRecordDTO] {
        allKeys.filter { !$0.consumerToolIds.contains(toolId) }
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
            where reason == "required" || reason.contains("master_password")
        {
            needsMasterPassword = true
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
            where reason == "required" || reason.contains("master_password")
        {
            needsMasterPassword = true
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
            let id = try await environment.consumerTools.createTool(
                ConsumerToolDraft(name: resolved)
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
}
