import CloudKit
import Foundation
import SwiftData

/// SwiftData 双配置 + 迁移骨架。
///
/// T014b（人工）：CloudKit Dashboard 将 Development schema **Deploy to Production**，
/// 并按 data-model §7.1 核对 Production record types。仅 Development 可见不算通过。
enum AppSchema: Sendable {
    nonisolated static let cloudKitContainerID = "iCloud.com.apirelay.ApiRelay"
    /// 与 entitlements `com.apple.security.application-groups` 一致。
    nonisolated static let appGroupID = "group.com.apirelay.shared"

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
    ///
    /// Debug 默认本机（避免未 Deploy Production schema 时持续刷 Server Rejected）。
    /// 需要联调同步时设环境变量 `APIRELAY_CLOUDKIT=1`。
    @MainActor
    static func makeProductionContainer() throws -> ModelContainer {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isTesting {
            return try makeInMemoryContainer()
        }
        #if DEBUG
        let forceCloudKit = ProcessInfo.processInfo.environment["APIRELAY_CLOUDKIT"] == "1"
        if !forceCloudKit {
            return try makeLocalDiskContainer()
        }
        #endif
        // 模拟器未登录 iCloud 时强开 CloudKit 只会刷 CKAccountStatusNoAccount。
        if !isICloudAccountAvailable() {
            print("[ApiRelay] No iCloud account; using local SwiftData store")
            return try makeLocalDiskContainer()
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
        try ensureAppGroupStoreDirectory()
        let group = ModelConfiguration.GroupContainer.identifier(appGroupID)
        let synced = ModelConfiguration(
            "synced",
            schema: syncedSchema,
            groupContainer: group,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        let local = ModelConfiguration(
            "local",
            schema: localSchema,
            groupContainer: group,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: synced, local)
    }

    /// 无 CloudKit 的本机持久化双配置（开发期 / 无付费账号回退）。
    nonisolated static func makeLocalDiskContainer() throws -> ModelContainer {
        try ensureAppGroupStoreDirectory()
        let group = ModelConfiguration.GroupContainer.identifier(appGroupID)
        let synced = ModelConfiguration(
            "synced",
            schema: syncedSchema,
            groupContainer: group,
            cloudKitDatabase: .none
        )
        let local = ModelConfiguration(
            "local",
            schema: localSchema,
            groupContainer: group,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: synced, local)
    }

    /// `groupContainer: .automatic` 会把库放到 App Group；父目录不存在时 CoreData 先刷一长串
    /// errno 2 再自恢复。启动前建好 `Library/Application Support` 可消掉该噪声。
    nonisolated static func ensureAppGroupStoreDirectory() throws {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }
        let support = root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    /// 启动期短超时探测；无账号时勿打开 CloudKit mirroring。
    nonisolated static func isICloudAccountAvailable() -> Bool {
        final class Box: @unchecked Sendable {
            var status: CKAccountStatus = .couldNotDetermine
        }
        let box = Box()
        let sem = DispatchSemaphore(value: 0)
        CKContainer(identifier: cloudKitContainerID).accountStatus { status, _ in
            box.status = status
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 2)
        return box.status == .available
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
