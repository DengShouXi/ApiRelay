import Foundation
import SwiftData

/// 密钥 ↔ 使用方多对多中间表。CloudKit 无唯一约束；读取时按 (keyId, consumerToolId) 去重。
@Model
final class KeyAssignment {
    var id: UUID = UUID()
    var keyId: UUID = UUID()
    var consumerToolId: UUID = UUID()
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        keyId: UUID,
        consumerToolId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.keyId = keyId
        self.consumerToolId = consumerToolId
        self.createdAt = createdAt
    }
}
