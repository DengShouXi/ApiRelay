import Foundation
import SwiftData

#if DEBUG
/// T014b：把从未写出非 nil 的可选字段 / 未建实体逼进 CloudKit Development schema。
///
/// 仅在 `APIRELAY_CLOUDKIT=1` 时运行。默认一次性；设
/// `APIRELAY_CLOUDKIT_SCHEMA_BOOTSTRAP=1` 可强制再跑。
/// Production 侧仍须在 Console 再 Deploy 一次。
enum CloudKitSchemaBootstrap {
    private static let defaultsKey = "ApiRelay.cloudKitSchemaBootstrap.v2"

    @MainActor
    static func runIfNeeded(container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["APIRELAY_CLOUDKIT"] == "1" else { return }
        guard AppSchema.isICloudAccountAvailable() else {
            print("[ApiRelay] CloudKitSchemaBootstrap skipped: no iCloud account on this device/simulator")
            return
        }
        let force = ProcessInfo.processInfo.environment["APIRELAY_CLOUDKIT_SCHEMA_BOOTSTRAP"] == "1"
        guard force || !UserDefaults.standard.bool(forKey: defaultsKey) else { return }

        let context = ModelContext(container)
        do {
            try seedAPIKeyOptionalFields(in: context)
            try seedAccountAndToolNotes(in: context)
            try seedDeferredSyncedTypes(in: context)
            try context.save()
            UserDefaults.standard.set(true, forKey: defaultsKey)
            print("[ApiRelay] CloudKitSchemaBootstrap: saved — wait for export, then check Development schema / Deploy")
        } catch {
            print("[ApiRelay] CloudKitSchemaBootstrap failed: \(error)")
        }
    }

    private static func seedAccountAndToolNotes(in context: ModelContext) throws {
        for account in try context.fetch(FetchDescriptor<UpstreamAccount>()) {
            if account.notes == nil { account.notes = "schemaBootstrap" }
            account.updatedAt = Date()
        }
        for tool in try context.fetch(FetchDescriptor<ConsumerTool>()) {
            if tool.notes == nil { tool.notes = "schemaBootstrap" }
        }
    }

    private static func seedAPIKeyOptionalFields(in context: ModelContext) throws {
        let keys = try context.fetch(FetchDescriptor<APIKeyRecord>())
        let now = Date()
        if keys.isEmpty {
            let account = UpstreamAccount(
                platform: "openai",
                displayName: "[Schema Bootstrap — deletable]"
            )
            context.insert(account)
            let key = APIKeyRecord(
                accountId: account.id,
                displayName: "[Schema Bootstrap — deletable]",
                maskedHint: "sk-…boot",
                providerKeyRef: "schemaBootstrap",
                spendLimit: Decimal(1),
                notes: "schemaBootstrap",
                lastVerifiedAt: now,
                lastCheckedAt: now,
                lastCheckNote: "schemaBootstrap",
                secretLength: 8
            )
            context.insert(key)
            return
        }
        for key in keys {
            if key.providerKeyRef == nil { key.providerKeyRef = "schemaBootstrap" }
            if key.spendLimit == nil { key.spendLimit = Decimal(1) }
            if key.notes == nil { key.notes = "schemaBootstrap" }
            if key.lastVerifiedAt == nil { key.lastVerifiedAt = now }
            if key.lastCheckedAt == nil { key.lastCheckedAt = now }
            if key.lastCheckNote == nil { key.lastCheckNote = "schemaBootstrap" }
            key.updatedAt = now
        }
    }

    private static func seedDeferredSyncedTypes(in context: ModelContext) throws {
        var pricingProbe = FetchDescriptor<PricingRule>()
        pricingProbe.fetchLimit = 1
        if try context.fetch(pricingProbe).isEmpty {
            context.insert(
                PricingRule(
                    platform: "schemaBootstrap",
                    inputPricePer1M: 0,
                    outputPricePer1M: 0,
                    source: "schemaBootstrap"
                )
            )
        }
        var balanceProbe = FetchDescriptor<BalanceSnapshot>()
        balanceProbe.fetchLimit = 1
        if try context.fetch(balanceProbe).isEmpty {
            context.insert(
                BalanceSnapshot(
                    accountId: UUID(),
                    currency: "USD",
                    totalBalance: Decimal(0),
                    isSufficient: true
                )
            )
        }
        var usageProbe = FetchDescriptor<UsageSnapshot>()
        usageProbe.fetchLimit = 1
        if try context.fetch(usageProbe).isEmpty {
            context.insert(
                UsageSnapshot(
                    keyId: UUID(),
                    periodStart: Date(),
                    periodTimeZone: "UTC",
                    inputTokens: 0,
                    outputTokens: 0,
                    totalTokens: 0,
                    reportedCostUSD: Decimal(0),
                    estimatedCostUSD: Decimal(0),
                    modelName: "schemaBootstrap",
                    capabilityNote: "schemaBootstrap"
                )
            )
        }
    }
}
#endif
