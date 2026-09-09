import Foundation
import SwiftData

#if DEBUG
/// T014b：把从未写出非 nil 的可选字段 / 未建实体逼进 CloudKit Development schema。
///
/// 只有同时显式设置 `APIRELAY_CLOUDKIT=1` 与
/// `APIRELAY_CLOUDKIT_SCHEMA_BOOTSTRAP=1` 才运行，且每个版本最多一次。
/// Production 侧仍须在 Console 再 Deploy 一次。
enum CloudKitSchemaBootstrap {
    private static let defaultsKey = "ApiRelay.cloudKitSchemaBootstrap.v4"

    @MainActor
    static func runIfNeeded(container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["APIRELAY_CLOUDKIT"] == "1" else { return }
        let force = ProcessInfo.processInfo.environment["APIRELAY_CLOUDKIT_SCHEMA_BOOTSTRAP"] == "1"
        // 仅显式人工动作可运行。普通 Debug 启动绝不能写 schema 探针。
        guard force else { return }
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }

        let context = ModelContext(container)
        do {
            // 探针只允许在全新的 Development 空库运行，避免改写真实账号、备注或密钥元数据。
            guard try isCleanDevelopmentStore(context) else {
                print("[ApiRelay] CloudKitSchemaBootstrap refused: synced store is not empty")
                return
            }
            seedProbeRecords(in: context)
            try context.save()
            UserDefaults.standard.set(true, forKey: defaultsKey)
            print("[ApiRelay] CloudKitSchemaBootstrap: saved — wait for export, then check Development schema / Deploy")
        } catch {
            print("[ApiRelay] CloudKitSchemaBootstrap failed: \(CloudKitSyncMonitor.diagnosticMessage(for: error))")
        }
    }

    private static func isCleanDevelopmentStore(_ context: ModelContext) throws -> Bool {
        try context.fetch(FetchDescriptor<UpstreamAccount>()).isEmpty
            && context.fetch(FetchDescriptor<APIKeyRecord>()).isEmpty
            && context.fetch(FetchDescriptor<ConsumerTool>()).isEmpty
            && context.fetch(FetchDescriptor<KeyAssignment>()).isEmpty
            && context.fetch(FetchDescriptor<UsageSnapshot>()).isEmpty
            && context.fetch(FetchDescriptor<BalanceSnapshot>()).isEmpty
            && context.fetch(FetchDescriptor<PricingRule>()).isEmpty
            && context.fetch(FetchDescriptor<UserPreferences>()).isEmpty
    }

    private static func seedProbeRecords(in context: ModelContext) {
        let now = Date()
        let marker = "[Schema Bootstrap — deletable]"
        let account = UpstreamAccount(
            platform: "schemaBootstrap",
            customPlatformName: marker,
            displayName: marker,
            customBaseURL: "https://example.invalid",
            hasManagementCredential: false,
            notes: marker,
            avatarSymbol: "sparkles",
            avatarColor: "blue",
            createdAt: now,
            updatedAt: now
        )
        let key = APIKeyRecord(
            accountId: account.id,
            displayName: marker,
            providerKeyRef: "schema-bootstrap-record",
            spendLimit: Decimal(1),
            notes: marker,
            createdAt: now,
            updatedAt: now,
            lastVerifiedAt: now,
            lastCheckedAt: now,
            lastCheckNote: "schemaBootstrap",
            avatarSymbol: "key.fill",
            avatarColor: "accent"
        )
        let tool = ConsumerTool(
            name: marker,
            iconSymbol: "laptopcomputer",
            avatarSymbol: "laptopcomputer",
            avatarColor: "indigo",
            notes: marker,
            createdAt: now,
            updatedAt: now
        )
        context.insert(account)
        context.insert(key)
        context.insert(tool)
        context.insert(KeyAssignment(keyId: key.id, consumerToolId: tool.id, createdAt: now))
        context.insert(PricingRule(
            platform: "schemaBootstrap",
            inputPricePer1M: 0,
            outputPricePer1M: 0,
            source: "schemaBootstrap"
        ))
        context.insert(BalanceSnapshot(
            accountId: account.id,
            currency: "USD",
            totalBalance: Decimal(0),
            grantedBalance: Decimal(0),
            toppedUpBalance: Decimal(0),
            isSufficient: true
        ))
        context.insert(UsageSnapshot(
            keyId: key.id,
            periodStart: now,
            periodTimeZone: "UTC",
            inputTokens: 0,
            outputTokens: 0,
            totalTokens: 0,
            reportedCostUSD: Decimal(0),
            estimatedCostUSD: Decimal(0),
            pricingRuleId: UUID(),
            modelName: "schemaBootstrap",
            capabilityNote: "schemaBootstrap"
        ))
        context.insert(UserPreferences(
            id: UUID(),
            autoLockDurationOptionsJSON: "[0,60]",
            clipboardClearEnabled: true,
            clipboardClearDurationOptionsJSON: "[30,120]"
        ))
    }
}
#endif
