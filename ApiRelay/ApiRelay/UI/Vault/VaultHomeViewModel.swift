import SwiftUI
import SwiftData
import Combine

@MainActor
final class VaultHomeViewModel: ObservableObject {
    @Published var accounts: [UpstreamAccountDTO] = []
    @Published var keysByAccount: [UUID: [KeyRecordDTO]] = [:]
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
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        do {
            accounts = try await vault.accounts()
            var map: [UUID: [KeyRecordDTO]] = [:]
            for account in accounts {
                map[account.id] = try await vault.keys(in: account.id)
            }
            keysByAccount = map
            remainingQuota = try await vault.remainingFreeQuota()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createAccount(platform: String, name: String) async {
        do {
            _ = try await vault.createAccount(UpstreamAccountDraft(platform: platform, displayName: name))
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

    /// 返回明文仅给调用方局部 @State；本 ViewModel MUST NOT 用 @Published 持有明文。
    func revealReturning(keyId: UUID, masterPassword: String?) async -> String? {
        needsMasterPassword = false
        do {
            return try await vault.revealSecret(
                keyId: keyId,
                purpose: .display,
                masterPassword: masterPassword
            )
        } catch let ApiRelayError.validationFailed(_, reason) where reason == "required" || reason == "master_password_prompt_required" || reason.contains("master_password") {
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
        } catch let ApiRelayError.validationFailed(_, reason) where reason == "required" || reason.contains("master_password") {
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
