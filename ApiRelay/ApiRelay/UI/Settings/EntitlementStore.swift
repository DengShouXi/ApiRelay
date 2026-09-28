import Combine
import Foundation
import StoreKit

/// One presentation state per composition root, not one "member" flag per page.
@MainActor
final class EntitlementStore: ObservableObject {
    enum Operation { case idle, purchasing, restoring }
    @Published private(set) var state: EntitlementDisplayState = .checking
    @Published private(set) var product: StoreProductInfo?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var operation: Operation = .idle
    @Published private(set) var approvalPending = false
    @Published private(set) var message = ""
    private let service: any EntitlementServing
    private var revision: UInt64 = 0
    private var productRevision: UInt64 = 0
    private var refreshQueued = false
    private var observer: AnyCancellable?

    init(service: any EntitlementServing) {
        self.service = service
        observer = NotificationCenter.default.publisher(for: .entitlementDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }
    }

    var isBusy: Bool { operation != .idle }
    var canPurchase: Bool { state.canPurchase && product != nil && !isBusy && !approvalPending }

    func refresh() async {
        guard !isBusy else {
            // An approval/revocation arriving during a payment or restore must
            // be rechecked afterwards, not silently dropped.
            refreshQueued = true
            return
        }
        revision &+= 1
        let request = revision
        state = .checking
        do {
            let tier = try await service.currentTier()
            guard request == revision else { return }
            state = EntitlementDisplayState(tier: tier)
            if state.isOwned { approvalPending = false }
        } catch {
            guard request == revision else { return }
            state = .unavailable
        }
    }

    func loadProduct() async {
        productRevision &+= 1
        let request = productRevision
        isLoadingProduct = true
        do {
            let loaded = try await service.productInfo()
            guard request == productRevision else { return }
            product = loaded
        } catch {
            guard request == productRevision else { return }
            product = nil
        }
        if request == productRevision { isLoadingProduct = false }
    }

    /// A declined Ask-to-Buy sends no transaction. Only an explicit user action
    /// releases this UI latch; an empty entitlement query does not imply denial.
    func retryPendingPurchase() async {
        guard !isBusy else { return }
        approvalPending = false
        message = ""
        await refresh()
    }

    func purchase() async {
        guard canPurchase else { return }
        beginNativePurchase()
        do { complete(tier: try await service.purchaseUnlimitedKeys()) }
        catch { complete(error: error) }
    }

    func beginNativePurchase() {
        guard !isBusy else { return }
        revision &+= 1
        operation = .purchasing
        message = ""
    }

    func completeNativePurchase(_ result: Result<Product.PurchaseResult, any Error>) async {
        do { complete(tier: try await service.completeNativePurchase(result)) }
        catch { complete(error: error) }
    }

    @discardableResult
    func restore() async -> String {
        guard !isBusy else { return message }
        revision &+= 1
        operation = .restoring
        state = .checking
        defer { endOperation() }
        do {
            let tier = try await service.restorePurchases()
            state = EntitlementDisplayState(tier: tier)
            if state.isOwned { approvalPending = false }
            message = tier == .free ? String(localized: "settings.restorePurchases.none")
                : String(localized: "settings.restorePurchases.done")
        } catch {
            state = .unavailable
            message = error.localizedDescription
        }
        return message
    }

    private func complete(tier: EntitlementTier) {
        revision &+= 1
        state = EntitlementDisplayState(tier: tier)
        approvalPending = false
        message = String(localized: "paywall.success")
        endOperation()
    }

    private func complete(error: any Error) {
        switch error {
        case ApiRelayError.authenticationCancelled:
            message = ""
        case ApiRelayError.validationFailed(let field, let reason)
            where field == "product" && reason == "purchase_pending":
            approvalPending = true
            message = String(localized: "paywall.purchasePending")
        case ApiRelayError.validationFailed(let field, let reason)
            where field == "product" && reason == "unverified_transaction":
            state = .unavailable
            message = String(localized: "paywall.verificationFailed")
        default:
            message = error.localizedDescription
        }
        endOperation()
    }

    private func endOperation() {
        operation = .idle
        guard refreshQueued else { return }
        refreshQueued = false
        Task { [weak self] in await self?.refresh() }
    }
}
