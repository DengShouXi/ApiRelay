import SwiftUI
import StoreKit

struct PaywallView: View {
    let environment: AppEnvironment
    @ObservedObject private var store: EntitlementStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var productReloadID = UUID()

    init(environment: AppEnvironment) {
        self.environment = environment
        self.store = environment.entitlementStore
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("paywall.body").font(.subheadline).foregroundStyle(.secondary)
                    Text("paywall.plan.unlimited.title").font(.headline)
                        .accessibilityIdentifier("paywall.entitlement.state.\(store.state.accessibilityCode)")
                    Text("paywall.plan.unlimited.detail").font(.subheadline).foregroundStyle(.secondary)
                    Group {
                        if store.state.isOwned {
                            Text("paywall.owned").frame(maxWidth: .infinity)
                        } else if store.isLoadingProduct {
                            ProgressView().frame(maxWidth: .infinity)
                        } else if store.product == nil {
                            Text("paywall.productUnavailable")
                            Button("paywall.reloadProduct") {
                                productReloadID = UUID()
                                Task { await store.loadProduct() }
                            }
                            .accessibilityIdentifier("paywall.product.retry")
                        } else {
                            purchaseContent
                            Button("paywall.reloadProduct") {
                                productReloadID = UUID()
                                Task { await store.loadProduct() }
                            }
                            .accessibilityIdentifier("paywall.product.reload")
                            .disabled(store.isBusy)
                        }
                    }

                    if store.state == .checking {
                        Text("paywall.entitlementChecking")
                            .accessibilityIdentifier("paywall.entitlement.checking")
                    } else if store.state == .unavailable {
                        Text("paywall.entitlementUnavailable")
                            .accessibilityIdentifier("paywall.entitlement.unavailable")
                        Button("paywall.retry") { Task { await store.refresh() } }
                            .accessibilityIdentifier("paywall.entitlement.retry")
                            .disabled(store.isBusy)
                    }
                    if store.approvalPending {
                        Button("paywall.pendingRetry") { Task { await store.retryPendingPurchase() } }
                            .accessibilityIdentifier("paywall.pending.retry")
                            .disabled(store.isBusy)
                    }
                    Button("paywall.restore") { Task { await store.restore() } }
                        .frame(maxWidth: .infinity)
                        .disabled(store.isBusy)
                    if !store.message.isEmpty {
                        Text(store.message)
                            .accessibilityIdentifier(store.approvalPending ? "paywall.purchasePending" : "paywall.message")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .navigationTitle("paywall.nav")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
            .task {
                async let product: Void = store.loadProduct()
                async let ownership: Void = store.refresh()
                _ = await (product, ownership)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refresh() } }
            }
            .onChange(of: store.state) { _, state in
                if state.isOwned { dismiss() }
            }
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 520, minHeight: 620)
            #endif
        }
    }

    @ViewBuilder private var purchaseContent: some View {
        #if DEBUG
        if AppRuntime.uiTestScenario != nil {
            // No system payment dialog in an explicit in-memory UI test world.
            Button {
                Task { await store.purchase() }
            } label: {
                Text("paywall.upgradeWithPrice \(store.product?.displayPrice ?? "")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("paywall.purchase")
            .disabled(!store.canPurchase)
        } else {
            nativeProduct
        }
        #else
        nativeProduct
        #endif
    }

    private var nativeProduct: some View {
        // Apple owns payment presentation. Never also call Product.purchase
        // from the start/completion callbacks of ProductView.
        ProductView(id: EntitlementService.unlimitedKeysProductID)
            .productViewStyle(.large)
            .id(productReloadID)
            .disabled(!store.canPurchase)
            .onInAppPurchaseStart { _ in store.beginNativePurchase() }
            .onInAppPurchaseCompletion { _, result in await store.completeNativePurchase(result) }
            .accessibilityIdentifier("paywall.nativeProduct")
    }
}
