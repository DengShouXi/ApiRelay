import Foundation
import StoreKit

/// 买断权益的放行规则。单测直接打这里，不必等 StoreKit 空序列超时。
///
/// 放行只看：苹果验过签、产品 ID 对、未退款。
/// 额外只挡一种：`.xcode`（Xcode 本地假商店）。TestFlight / 审核的 `.sandbox`
/// 与正式店的 `.production` 都放行，避免环境和 App 包偶发不一致时「钱扣了却不是会员」。
nonisolated enum EntitlementGrantPolicy: Sendable {
    nonisolated static func grantsUnlimitedKeys(
        productID: String,
        environment: AppStore.Environment,
        revocationDate: Date?,
        appEnvironment: AppStore.Environment?
    ) -> Bool {
        guard revocationDate == nil else { return false }
        guard productID == EntitlementService.unlimitedKeysProductID else { return false }
        if environment == .xcode {
            return appEnvironment == .xcode
        }
        return true
    }
}
