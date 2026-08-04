import Foundation

/// V1：仅定义协议与 DTO，不提供实现、不在 UI 暴露入口（DC-028）。
/// V2：填入实现；检测逻辑见 FR-051～FR-054。
protocol KeyHealthServing: Sendable {
    func check(keyId: UUID) async throws -> KeyHealthDTO
    func checkAll(keyIds: [UUID]) async -> [UUID: KeyHealthResult]
}

enum KeyHealthResult: Sendable {
    case completed(KeyHealthDTO)
    case skippedUnsupported          // 自定义平台等未接入检测
    case skippedCoolingDown          // 冷却期内
}
