import Foundation
import StoreKit

/// 买断权益的放行规则。单测直接打这里，不必等 StoreKit 空序列超时。
///
/// 放行只看：苹果验过签、产品 ID 对、未退款。
/// `.xcode` 是本地假交易，只有显式注入的 StoreKit 自动测试可放行。
/// TestFlight / 审核的 `.sandbox` 与正式店的 `.production` 均放行。
nonisolated enum EntitlementGrantPolicy: Sendable {
    nonisolated static func grantsUnlimitedKeys(
        productID: String,
        environment: AppStore.Environment,
        revocationDate: Date?,
        appEnvironment: AppStore.Environment?,
        localStoreKitTestingAllowed: Bool = false
    ) -> Bool {
        guard revocationDate == nil else { return false }
        guard productID == EntitlementService.unlimitedKeysProductID else { return false }
        if environment == .xcode {
            #if DEBUG
            return localStoreKitTestingAllowed && appEnvironment == .xcode
            #else
            return false
            #endif
        }
        return true
    }
}

/// All new active-key entry points share the same commercial boundary.
/// Existing keys are never deleted when an entitlement later disappears.
nonisolated enum KeyActivationQuotaPolicy: Sendable {
    nonisolated static func ensureCanActivate(
        activeCount: Int,
        additionalCount: Int,
        entitlements: any EntitlementServing
    ) async throws {
        guard additionalCount > 0 else { return }
        let limit = KeyVaultService.freeTierLimit
        if activeCount <= limit, additionalCount <= limit - activeCount {
            return
        }
        guard try await entitlements.currentTier() != .free else {
            throw ApiRelayError.quotaExceededFreeTier(limit: limit)
        }
    }
}
