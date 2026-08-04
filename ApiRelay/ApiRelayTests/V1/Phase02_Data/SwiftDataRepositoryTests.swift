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
        XCTAssertEqual(PresetCatalog.platforms.count, 8)
        XCTAssertEqual(PresetCatalog.consumerTools.count, 9)
        XCTAssertTrue(PresetCatalog.consumerTools.map(\.name).contains("VS Code"))
        XCTAssertNotNil(PresetCatalog.platform(id: "deepseek"))
        XCTAssertEqual(PresetCatalog.platform(id: "custom")?.id, "custom")
    }

    func testEntitlementSnapshotRoundTrip() async throws {
        let repo = EntitlementSnapshotRepository(modelContainer: container)
        try await repo.update(tier: .unlimitedKeys, source: "debugOverride")
        let dto = try await repo.loadOrCreate()
        XCTAssertEqual(dto.tier, .unlimitedKeys)
        XCTAssertEqual(dto.source, "debugOverride")
    }
}
