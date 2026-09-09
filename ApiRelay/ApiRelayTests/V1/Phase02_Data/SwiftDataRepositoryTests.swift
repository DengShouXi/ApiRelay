@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class SwiftDataRepositoryTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try AppSchema.makeInMemoryContainer()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func testInMemoryContainerInitializes() throws {
        XCTAssertNotNil(container)
    }

    func testUpstreamAccountCRUD() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = try await repo.insert(UpstreamAccountDraft(
            platform: "openai",
            displayName: "Work"
        ))
        let fetched = try await repo.fetch(id: id)
        XCTAssertEqual(fetched?.displayName, "Work")
        XCTAssertEqual(fetched?.platform, "openai")

        try await repo.update(id: id, patch: UpstreamAccountPatch(displayName: "Home"))
        let updated = try await repo.fetch(id: id)
        XCTAssertEqual(updated?.displayName, "Home")

        try await repo.delete(id: id)
        let deleted = try await repo.fetch(id: id)
        XCTAssertNil(deleted)
    }

    func testKeyAssignmentDedupesOnRead() async throws {
        let keyId = UUID()
        let toolId = UUID()
        let repo = KeyAssignmentRepository(modelContainer: container)

        let context = ModelContext(container)
        context.insert(KeyAssignment(keyId: keyId, consumerToolId: toolId))
        context.insert(KeyAssignment(keyId: keyId, consumerToolId: toolId))
        try context.save()

        let tools = try await repo.fetchConsumerToolIDs(keyId: keyId)
        XCTAssertEqual(tools, [toolId])

        let kind = try await repo.assignmentKind(keyId: keyId)
        if case .exclusive(let id) = kind {
            XCTAssertEqual(id, toolId)
        } else {
            XCTFail("expected exclusive")
        }
    }

    func testUserPreferencesIgnoresAppearancePatch() async throws {
        let userRepo = UserPreferencesRepository(modelContainer: container)
        let deviceRepo = DevicePreferencesRepository(modelContainer: container)

        var patch = PreferencesPatch()
        patch.revealPolicy = .masterPassword
        patch.appearance = .dark
        try await userRepo.update(patch)

        let user = try await userRepo.loadOrCreate()
        XCTAssertEqual(user.revealPolicy, .masterPassword)
        XCTAssertEqual(user.appearance, .system)

        try await deviceRepo.update(patch)
        let device = try await deviceRepo.loadOrCreate()
        XCTAssertEqual(device.appearance, .dark)
    }

    func testAPIKeyRecordHealthDefaultsAndNoConsumerToolId() throws {
        // 编译期：APIKeyRecord 初始化器无 consumerToolId。
        // 运行期：V1 health 预留字段默认 unknown。
        let record = APIKeyRecord(accountId: UUID(), displayName: "x")
        XCTAssertEqual(record.healthState, KeyHealthState.unknown.rawValue)
        XCTAssertNil(record.lastCheckedAt)
        XCTAssertNil(record.lastCheckNote)
    }

    func testPresetCatalogCL003() {
        let names = PresetCatalog.consumerTools.map(\.name)
        XCTAssertEqual(PresetCatalog.platforms.map(\.id), [
            "openai", "anthropic", "google", "openrouter", "deepseek",
            "zhipu", "alibaba-bailian", "volcengine", "siliconflow",
        ])
        XCTAssertEqual(PresetCatalog.platform(id: "anthropic")?.displayName, "Anthropic")
        XCTAssertEqual(names, [
            "VS Code", "Cursor", "Claude Code", "Codex", "Cline",
            "OpenCode", "Trae", "Cherry Studio", "Zed", "Continue",
        ])
        XCTAssertFalse(names.contains("Roo Code"))
        XCTAssertNotNil(PresetCatalog.platform(id: "deepseek"))
        XCTAssertNotNil(PresetCatalog.platform(id: "zhipu"))
        XCTAssertEqual(PresetCatalog.platform(id: "custom")?.id, "custom")
    }

    func testEntitlementSnapshotRoundTrip() async throws {
        let repo = EntitlementSnapshotRepository(modelContainer: container)
        try await repo.update(tier: .unlimitedKeys, source: "debugOverride")
        let dto = try await repo.loadOrCreate()
        XCTAssertEqual(dto.tier, .unlimitedKeys)
        XCTAssertEqual(dto.source, "debugOverride")
    }

    func testUpstreamAccountReadKeepsNewerUpdatedAt() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        plantAccount(id: id, name: "Old", createdAt: older, updatedAt: older)
        plantAccount(id: id, name: "New", createdAt: older, updatedAt: newer)
        try ModelContext(container).save()

        let all = try await repo.fetchAll()
        XCTAssertEqual(all.map(\.displayName), ["New"])
        let fetched = try await repo.fetch(id: id)
        XCTAssertEqual(fetched?.displayName, "New")
        XCTAssertEqual(try countAccounts(id), 2)
    }

    func testUpstreamAccountTombstoneWinsOverOlderLiveRow() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        plantAccount(id: id, name: "Live", createdAt: older, updatedAt: older)
        plantAccount(
            id: id,
            name: "Trashed",
            createdAt: older,
            updatedAt: newer,
            deletedAt: newer
        )
        try ModelContext(container).save()

        let visible = try await repo.fetchAll()
        XCTAssertTrue(visible.isEmpty)
        let trashed = try await repo.fetchSoftDeleted()
        XCTAssertEqual(trashed.map(\.displayName), ["Trashed"])
    }

    func testUpstreamAccountEqualTimestampPrefersTombstone() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = UUID()
        let stamp = Date(timeIntervalSince1970: 150)
        plantAccount(id: id, name: "Live", createdAt: stamp, updatedAt: stamp)
        plantAccount(
            id: id,
            name: "Trashed",
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: stamp
        )
        try ModelContext(container).save()

        let visible = try await repo.fetchAll()
        XCTAssertTrue(visible.isEmpty)
        let trashed = try await repo.fetchSoftDeleted()
        XCTAssertEqual(trashed.map(\.id), [id])
    }

    func testUpstreamAccountUpdateAndDeleteHitEveryReplica() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        plantAccount(id: id, name: "Old", createdAt: older, updatedAt: older)
        plantAccount(id: id, name: "New", createdAt: older, updatedAt: newer)
        try ModelContext(container).save()

        try await repo.update(id: id, patch: UpstreamAccountPatch(displayName: "Patched"))
        XCTAssertEqual(try countAccounts(id), 2)
        XCTAssertTrue(try rawAccounts(id).allSatisfy { $0.displayName == "Patched" })

        try await repo.delete(id: id)
        XCTAssertEqual(try countAccounts(id), 0)
    }

    func testUpstreamAccountPruneKeepsNewerReplica() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        plantAccount(id: id, name: "Old", createdAt: older, updatedAt: older)
        plantAccount(id: id, name: "New", createdAt: older, updatedAt: newer)
        try ModelContext(container).save()

        try await repo.pruneDuplicateIdentities()
        XCTAssertEqual(try countAccounts(id), 1)
        let fetched = try await repo.fetch(id: id)
        XCTAssertEqual(fetched?.displayName, "New")
    }

    func testUpstreamAccountIdenticalReplicasAreNotPruned() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = UUID()
        let stamp = Date(timeIntervalSince1970: 100)
        plantAccount(id: id, name: "Same", createdAt: stamp, updatedAt: stamp)
        plantAccount(id: id, name: "Same", createdAt: stamp, updatedAt: stamp)
        try ModelContext(container).save()

        try await repo.pruneDuplicateIdentities()
        XCTAssertEqual(try countAccounts(id), 2)
        let all = try await repo.fetchAll()
        XCTAssertEqual(all.map(\.displayName), ["Same"])
    }

    func testInsertWithExistingAccountIdThrowsAlreadyExists() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = try await repo.insert(UpstreamAccountDraft(platform: "openai", displayName: "One"))
        do {
            _ = try await repo.insert(
                UpstreamAccountDraft(platform: "openai", displayName: "Two"),
                id: id
            )
            XCTFail("expected already_exists")
        } catch ApiRelayError.validationFailed(let field, let reason) {
            XCTAssertEqual(field, "id")
            XCTAssertEqual(reason, "already_exists")
        }
        XCTAssertEqual(try countAccounts(id), 1)
        let fetched = try await repo.fetch(id: id)
        XCTAssertEqual(fetched?.displayName, "One")
    }

    func testInsertIfAbsentSkipsExistingAccountId() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = try await repo.insert(UpstreamAccountDraft(platform: "openai", displayName: "One"))
        let inserted = try await repo.insertIfAbsent(
            UpstreamAccountDraft(platform: "openai", displayName: "Two"),
            id: id
        )
        XCTAssertFalse(inserted)
        XCTAssertEqual(try countAccounts(id), 1)
        let fetched = try await repo.fetch(id: id)
        XCTAssertEqual(fetched?.displayName, "One")
    }

    func testNewerRowWinsWholeLineIncludingDiscardingOlderAvatar() async throws {
        let repo = UpstreamAccountRepository(modelContainer: container)
        let id = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        plantAccount(
            id: id,
            name: "Old",
            notes: "keep-me-not",
            avatarSymbol: "star.fill",
            createdAt: older,
            updatedAt: older
        )
        plantAccount(
            id: id,
            name: "New",
            notes: "newer-notes",
            avatarSymbol: nil,
            createdAt: older,
            updatedAt: newer
        )
        try ModelContext(container).save()

        let fetched = try await repo.fetch(id: id)
        XCTAssertEqual(fetched?.displayName, "New")
        XCTAssertEqual(fetched?.notes, "newer-notes")
        XCTAssertNil(fetched?.avatarSymbol)
    }

    func testUserPreferencesDuplicateRowsReadWinnerAndWriteAll() async throws {
        let repo = UserPreferencesRepository(modelContainer: container)
        let ctx = ModelContext(container)
        let low = UserPreferences()
        low.displayCurrency = "AAA"
        let high = UserPreferences()
        high.displayCurrency = "ZZZ"
        ctx.insert(low)
        ctx.insert(high)
        try ctx.save()

        let loaded = try await repo.loadOrCreate()
        XCTAssertEqual(loaded.displayCurrency, "ZZZ")

        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOnly
        try await repo.update(patch)
        let rows = try rawPreferences()
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.revealPolicy == RevealPolicy.biometricOnly.rawValue })

        try await repo.pruneDuplicateIdentities()
        XCTAssertEqual(try rawPreferences().count, 2)
        let after = try await repo.loadOrCreate()
        XCTAssertEqual(after.revealPolicy, .biometricOnly)
        XCTAssertEqual(after.displayCurrency, "ZZZ")
    }

    func testEntitlementSnapshotDuplicateRowsPreferNewerUpdatedAt() async throws {
        let repo = EntitlementSnapshotRepository(modelContainer: container)
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let ctx = ModelContext(container)
        ctx.insert(EntitlementSnapshot(tier: .free, source: "old", updatedAt: older))
        ctx.insert(EntitlementSnapshot(tier: .unlimitedKeys, source: "new", updatedAt: newer))
        try ctx.save()

        let loaded = try await repo.loadOrCreate()
        XCTAssertEqual(loaded.tier, .unlimitedKeys)
        XCTAssertEqual(loaded.source, "new")

        try await repo.pruneDuplicateIdentities()
        XCTAssertEqual(try rawEntitlements().count, 1)

        try await repo.update(tier: .free, source: "storekit")
        XCTAssertEqual(try rawEntitlements().count, 1)
        XCTAssertEqual(try rawEntitlements().first?.tier, EntitlementTier.free.rawValue)
    }

    func testConsumerToolSoftDeleteBumpsUpdatedAtOnEveryReplica() async throws {
        let repo = ConsumerToolRepository(modelContainer: container)
        let id = UUID()
        let older = Date(timeIntervalSince1970: 100)
        plantTool(id: id, name: "Old", createdAt: older, updatedAt: older)
        plantTool(id: id, name: "New", createdAt: older, updatedAt: Date(timeIntervalSince1970: 200))
        try ModelContext(container).save()

        try await repo.softDelete(id: id)
        let rows = try rawTools(id)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.deletedAt != nil })
        XCTAssertTrue(rows.allSatisfy { $0.updatedAt > older })
        let visible = try await repo.fetchAll()
        XCTAssertTrue(visible.isEmpty)
        let trashed = try await repo.fetchSoftDeleted()
        XCTAssertEqual(trashed.count, 1)
    }

    func testAPIKeyCountAndFetchDedupesDuplicateIds() async throws {
        let repo = APIKeyRecordRepository(modelContainer: container)
        let accountId = UUID()
        let keyId = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        plantKey(id: keyId, accountId: accountId, name: "Old", createdAt: older, updatedAt: older)
        plantKey(id: keyId, accountId: accountId, name: "New", createdAt: older, updatedAt: newer)
        try ModelContext(container).save()

        let counted = try await repo.countActiveNonDeleted()
        XCTAssertEqual(counted, 1)
        let fetched = try await repo.fetch(accountId: accountId, lifecycles: [.active])
        XCTAssertEqual(fetched.map(\.displayName), ["New"])
        try await repo.softDelete(id: keyId)
        let afterDelete = try await repo.countActiveNonDeleted()
        XCTAssertEqual(afterDelete, 0)
        XCTAssertEqual(try rawKeys(keyId).count, 2)
        XCTAssertTrue(try rawKeys(keyId).allSatisfy { $0.deletedAt != nil })
    }

    private func plantAccount(
        id: UUID,
        name: String,
        notes: String? = nil,
        avatarSymbol: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        let ctx = ModelContext(container)
        ctx.insert(UpstreamAccount(
            id: id,
            platform: "openai",
            displayName: name,
            notes: notes,
            avatarSymbol: avatarSymbol,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            purgeAfter: deletedAt
        ))
        try? ctx.save()
    }

    private func plantTool(id: UUID, name: String, createdAt: Date, updatedAt: Date) {
        let ctx = ModelContext(container)
        ctx.insert(ConsumerTool(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt
        ))
        try? ctx.save()
    }

    private func plantKey(
        id: UUID,
        accountId: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        let ctx = ModelContext(container)
        ctx.insert(APIKeyRecord(
            id: id,
            accountId: accountId,
            displayName: name,
            createdAt: createdAt,
            updatedAt: updatedAt
        ))
        try? ctx.save()
    }

    private func countAccounts(_ id: UUID) throws -> Int {
        try rawAccounts(id).count
    }

    private func rawAccounts(_ id: UUID) throws -> [UpstreamAccount] {
        let ctx = ModelContext(container)
        return try ctx.fetch(FetchDescriptor<UpstreamAccount>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    private func rawTools(_ id: UUID) throws -> [ConsumerTool] {
        let ctx = ModelContext(container)
        return try ctx.fetch(FetchDescriptor<ConsumerTool>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    private func rawKeys(_ id: UUID) throws -> [APIKeyRecord] {
        let ctx = ModelContext(container)
        return try ctx.fetch(FetchDescriptor<APIKeyRecord>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    private func rawPreferences() throws -> [UserPreferences] {
        let ctx = ModelContext(container)
        let id = UserPreferences.singletonID
        return try ctx.fetch(FetchDescriptor<UserPreferences>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    private func rawEntitlements() throws -> [EntitlementSnapshot] {
        let ctx = ModelContext(container)
        let id = EntitlementSnapshot.singletonID
        return try ctx.fetch(FetchDescriptor<EntitlementSnapshot>(
            predicate: #Predicate { $0.id == id }
        ))
    }
}
