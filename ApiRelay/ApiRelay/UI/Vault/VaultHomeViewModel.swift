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

    func createAccount(platform: String, name: String, customBaseURL: String?) async {
        do {
            _ = try await vault.createAccount(UpstreamAccountDraft(
                platform: platform,
                customPlatformName: platform == PresetCatalog.customPlatformID ? name : nil,
                displayName: name,
                customBaseURL: customBaseURL
            ))
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createKey(accountId: UUID, name: String, secret: String, ackDuplicate: Bool) async {
        do {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: name),
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
            return true
        } catch let ApiRelayError.validationFailed(_, reason)
            where reason == "required" || reason.contains("master_password")
        {
            needsMasterPassword = true
            return false
        } catch {
            errorMessage = error.localizedDescription
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
}
