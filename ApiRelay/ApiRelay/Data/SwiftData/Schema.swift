import Foundation
import SwiftData

/// SwiftData 双配置 + 迁移骨架。
///
/// T014b（人工）：CloudKit Dashboard 将 Development schema **Deploy to Production**，
/// 并按 data-model §7.1 核对 Production record types。仅 Development 可见不算通过。
enum AppSchema: Sendable {
    nonisolated static let cloudKitContainerID = "iCloud.com.apirelay.ApiRelay"

    nonisolated static let syncedModels: [any PersistentModel.Type] = [
        UpstreamAccount.self,
        APIKeyRecord.self,
        ConsumerTool.self,
        KeyAssignment.self,
        UsageSnapshot.self,
        BalanceSnapshot.self,
        PricingRule.self,
        UserPreferences.self,
    ]

    nonisolated static let localModels: [any PersistentModel.Type] = [
        DevicePreferences.self,
        EntitlementSnapshot.self,
    ]

    nonisolated static var allModels: [any PersistentModel.Type] {
        syncedModels + localModels
    }

    nonisolated static var fullSchema: Schema {
        Schema(allModels)
    }

    nonisolated static var syncedSchema: Schema {
        Schema(syncedModels)
    }

    nonisolated static var localSchema: Schema {
        Schema(localModels)
    }

    /// 生产容器：优先 CloudKit private DB；Portal/签名未就绪或单元测试时回退本机。
    @MainActor
    static func makeProductionContainer() throws -> ModelContainer {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isTesting {
            return try makeInMemoryContainer()
        }
        do {
            return try makeCloudKitContainer()
        } catch {
            // 容器未在 Portal 勾选、或首次签名未完成时不阻断启动。
            return try makeLocalDiskContainer()
        }
    }

    /// CloudKit private DB + local（需付费账号；T014b Deploy Production 后 TestFlight 才完整可用）。
    @MainActor
    static func makeCloudKitContainer() throws -> ModelContainer {
        let synced = ModelConfiguration(
            "synced",
            schema: syncedSchema,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        let local = ModelConfiguration(
            "local",
            schema: localSchema,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: synced, local)
    }

    /// 无 CloudKit 的本机持久化双配置（开发期 / 无付费账号回退）。
    nonisolated static func makeLocalDiskContainer() throws -> ModelContainer {
        let synced = ModelConfiguration(
            "synced",
            schema: syncedSchema,
            cloudKitDatabase: .none
        )
        let local = ModelConfiguration(
            "local",
            schema: localSchema,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: synced, local)
    }

    /// 单元测试 / Preview：双配置均内存、无 CloudKit。
    nonisolated static func makeInMemoryContainer() throws -> ModelContainer {
        let synced = ModelConfiguration(
            "synced",
            schema: syncedSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let local = ModelConfiguration(
            "local",
            schema: localSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: synced, local)
    }
}

enum AppSchemaVersion: VersionedSchema {
    nonisolated static let versionIdentifier = Schema.Version(1, 0, 0)

    nonisolated static var models: [any PersistentModel.Type] {
        AppSchema.allModels
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] {
        [AppSchemaVersion.self]
    }

    nonisolated static var stages: [MigrationStage] {
        []
    }
}
