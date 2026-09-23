@testable import ApiRelay

extension KeychainStore {
    /// 测试统一入口。MUST NOT 在测试里直接 `KeychainStore(accessGroup: nil)`——
    /// 测试跑在 `ApiRelay.app` 宿主进程里，省略 access group 会落进 App 自己的那个组，
    /// setUp 的 `reset()` 与 `eraseAllUserData()` 会删掉用户本机真实的主密码和密钥明文。
    ///
    /// - Parameters:
    ///   - disableSynchronizable: 沿用各用例原有取值；只有专门校验
    ///     `kSecAttrSynchronizable` 的用例需要传 `false`。
    ///   - accessGroup: 仅供签名宿主 access-group / Keychain 域迁移测试显式指定。
    ///   - servicePrefix: 默认使用全局测试前缀；迁移测试必须传入唯一测试前缀。
    static func makeForTests(
        disableSynchronizable: Bool = true,
        accessGroup: String? = nil,
        servicePrefix: String = KeychainStore.testServicePrefix
    ) -> KeychainStore {
        KeychainStore(
            accessGroup: accessGroup,
            disableSynchronizableForTesting: disableSynchronizable,
            servicePrefix: servicePrefix
        )
    }
}
