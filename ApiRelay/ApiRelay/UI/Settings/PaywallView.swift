import SwiftUI
import StoreKit

struct PaywallView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var message = ""
    @State private var product: Product?
    @State private var isLoadingProduct = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var alreadyOwned = false

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

                    Button {
                        Task { await purchase() }
                    } label: {
                        Group {
                            if isPurchasing {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else if alreadyOwned {
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
                    .controlSize(.large)
                    .disabled(isPurchasing || isRestoring || product == nil || alreadyOwned)

                    Button("paywall.restore") {
                        Task { await restore() }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isPurchasing || isRestoring)

                    if !message.isEmpty {
                        Text(message)
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
                await loadProductAndTier()
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
                if alreadyOwned {
                    Text("paywall.plan.badge.owned")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.green.opacity(0.15))
                        )
                } else {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(paywallCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(alreadyOwned ? 0.15 : 0.35), lineWidth: 1)
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

    private func loadProductAndTier() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let tier = try await environment.entitlements.currentTier()
            alreadyOwned = (tier == .unlimitedKeys || tier == .relay)
        } catch {
            alreadyOwned = false
        }

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

    private func purchase() async {
        message = ""
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let tier = try await environment.entitlements.purchaseUnlimitedKeys()
            alreadyOwned = (tier == .unlimitedKeys || tier == .relay)
            message = String(localized: "paywall.success")
            if alreadyOwned {
                dismiss()
            }
        } catch ApiRelayError.authenticationCancelled {
            // 用户取消，不刷错误文案
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() async {
        message = ""
        isRestoring = true
        defer { isRestoring = false }
        do {
            let tier = try await environment.entitlements.restorePurchases()
            alreadyOwned = (tier == .unlimitedKeys || tier == .relay)
            message = alreadyOwned
                ? String(localized: "paywall.restored")
                : String(localized: "paywall.restore.none")
        } catch {
            message = error.localizedDescription
        }
    }
}
