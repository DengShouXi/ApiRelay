import SwiftUI
import StoreKit

struct PaywallView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var message = ""
    @State private var product: Product?
    @State private var isLoadingProduct = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseApprovalPending = false
    @State private var purchaseAwaitingEntitlement = false
    @State private var isCheckingActivation = false
    @State private var entitlementState: EntitlementDisplayState = .checking
    @State private var entitlementRequestRevision: UInt64 = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("paywall.body")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isLoadingProduct {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        unlimitedPlanCard
                    }

                    if entitlementState == .checking {
                        Text("paywall.entitlementChecking")
                            .accessibilityIdentifier("paywall.entitlement.checking")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if entitlementState == .unavailable {
                        Text("paywall.entitlementUnavailable")
                            .accessibilityIdentifier("paywall.entitlement.unavailable")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("paywall.retry") {
                            Task { await refreshTier() }
                        }
                        .accessibilityIdentifier("paywall.entitlement.retry")
                    }
                    if purchaseAwaitingEntitlement {
                        Text("paywall.activationPending")
                            .accessibilityIdentifier("paywall.entitlement.activationPending")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("paywall.retry") {
                            Task { await waitForPurchaseActivation() }
                        }
                        .accessibilityIdentifier("paywall.entitlement.activationRetry")
                        .disabled(isPurchasing || isRestoring || isCheckingActivation)
                    }

                    Button {
                        Task { await purchase() }
                    } label: {
                        Group {
                            if isPurchasing {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else if entitlementState.isOwned {
                                Text("paywall.owned")
                                    .frame(maxWidth: .infinity)
                            } else if let product {
                                Text("paywall.upgradeWithPrice \(product.displayPrice)")
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("paywall.upgrade")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("paywall.purchase")
                    .controlSize(.large)
                    .disabled(
                        isPurchasing || isRestoring || purchaseApprovalPending || purchaseAwaitingEntitlement
                            || product == nil || !entitlementState.canPurchase
                    )

                    Button("paywall.restore") {
                        Task { await restore() }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isPurchasing || isRestoring)

                    if !message.isEmpty {
                        Text(message)
                            .accessibilityIdentifier(
                                purchaseApprovalPending ? "paywall.purchasePending" : "paywall.message"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(paywallBackground.ignoresSafeArea())
            .navigationTitle("paywall.nav")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #if !targetEnvironment(macCatalyst)
            .toolbarBackground(paywallBackground, for: .navigationBar)
            #endif
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
            .task {
                await loadProduct()
            }
            .task { await refreshTier() }
            .onReceive(NotificationCenter.default.publisher(for: .entitlementDidChange)) { _ in
                Task { await refreshTier() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshTier() }
                }
            }
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 520, minHeight: 620)
            #endif
        }
    }

    private var unlimitedPlanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("paywall.plan.unlimited.title")
                    .font(.headline)
                Spacer(minLength: 8)
                if entitlementState.isOwned {
                    Text("paywall.plan.badge.owned")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.green.opacity(0.15))
                        )
                } else if entitlementState == .free {
                    Text("paywall.plan.badge.current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
            }

            Text("paywall.plan.unlimited.detail")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let product {
                    Text(product.displayPrice)
                        .font(.title2.weight(.bold))
                    Text("paywall.plan.once")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("paywall.productUnavailable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .accessibilityIdentifier("paywall.entitlement.state.\(entitlementState.accessibilityCode)")
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(paywallCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(entitlementState.isOwned ? 0.15 : 0.35), lineWidth: 1)
        )
    }

    private var paywallBackground: Color {
        if colorScheme == .dark {
            return Color(white: 0.14)
        }
        #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(red: 0.949, green: 0.949, blue: 0.969)
        #endif
    }

    private var paywallCardFill: Color {
        if colorScheme == .dark {
            return Color(white: 0.18)
        }
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color.white
        #endif
    }

    private func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(
                for: [EntitlementService.unlimitedKeysProductID]
            )
            product = products.first
            if products.isEmpty {
                message = String(localized: "paywall.productUnavailable")
            }
        } catch {
            message = error.localizedDescription
            product = nil
        }
    }

    private func refreshTier() async {
        guard !isRestoring, !isPurchasing else { return }
        entitlementRequestRevision &+= 1
        let revision = entitlementRequestRevision
        entitlementState = .checking
        do {
            let tier = try await environment.entitlements.currentTier()
            guard revision == entitlementRequestRevision else { return }
            if purchaseAwaitingEntitlement {
                if tier == .free {
                    entitlementState = .checking
                } else {
                    purchaseApprovalPending = false
                    purchaseAwaitingEntitlement = false
                    entitlementState = .owned
                    dismiss()
                }
            } else {
                entitlementState = EntitlementDisplayState(tier: tier)
                if entitlementState.isOwned { purchaseApprovalPending = false }
            }
        } catch {
            guard revision == entitlementRequestRevision else { return }
            entitlementState = purchaseAwaitingEntitlement ? .checking : .unavailable
        }
    }

    private func purchase() async {
        guard entitlementState.canPurchase, product != nil else { return }
        message = ""
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let tier = try await environment.entitlements.purchaseUnlimitedKeys()
            entitlementRequestRevision &+= 1
            if tier == .free {
                entitlementState = .free
            } else {
                // Verified purchase can precede Transaction.currentEntitlements.
                // Keep the sheet open until the same authoritative check used by
                // the fourth-key write gate sees the grant; never trust snapshot.
                purchaseAwaitingEntitlement = true
                entitlementState = .checking
                await waitForPurchaseActivation()
            }
        } catch ApiRelayError.authenticationCancelled {
            // 用户取消，不刷错误文案
        } catch ApiRelayError.validationFailed(let field, let reason)
            where field == "product" && reason == "purchase_pending" {
            purchaseApprovalPending = true
            message = String(localized: "paywall.purchasePending")
        } catch ApiRelayError.validationFailed(let field, let reason)
            where field == "product" && reason == "unverified_transaction" {
            message = String(localized: "paywall.verificationFailed")
        } catch {
            message = error.localizedDescription
        }
    }

    private func waitForPurchaseActivation() async {
        guard purchaseAwaitingEntitlement, !isCheckingActivation else { return }
        isCheckingActivation = true
        defer { isCheckingActivation = false }
        entitlementState = .checking
        for attempt in 0..<20 {
            guard !Task.isCancelled, purchaseAwaitingEntitlement else { return }
            if let tier = try? await environment.entitlements.currentTier(), tier != .free {
                guard purchaseAwaitingEntitlement else { return }
                purchaseAwaitingEntitlement = false
                entitlementState = .owned
                message = String(localized: "paywall.success")
                dismiss()
                return
            }
            if attempt < 19 {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        guard purchaseAwaitingEntitlement else { return }
        message = String(localized: "paywall.activationPending")
    }

    private func restore() async {
        message = ""
        isRestoring = true
        entitlementRequestRevision &+= 1
        let revision = entitlementRequestRevision
        entitlementState = .checking
        defer { isRestoring = false }
        do {
            let tier = try await environment.entitlements.restorePurchases()
            guard revision == entitlementRequestRevision else { return }
            if purchaseAwaitingEntitlement, tier != .free {
                purchaseApprovalPending = false
                purchaseAwaitingEntitlement = false
                entitlementState = .owned
                dismiss()
            } else {
                entitlementState = purchaseAwaitingEntitlement
                    ? .checking : EntitlementDisplayState(tier: tier)
                if entitlementState.isOwned { purchaseApprovalPending = false }
            }
            message = entitlementState.isOwned
                ? String(localized: "paywall.restored")
                : purchaseAwaitingEntitlement
                    ? String(localized: "paywall.activationPending")
                    : purchaseApprovalPending
                        ? String(localized: "paywall.purchasePending")
                        : String(localized: "paywall.restore.none")
        } catch {
            guard revision == entitlementRequestRevision else { return }
            entitlementState = purchaseAwaitingEntitlement ? .checking : .unavailable
            message = error.localizedDescription
        }
    }
}
