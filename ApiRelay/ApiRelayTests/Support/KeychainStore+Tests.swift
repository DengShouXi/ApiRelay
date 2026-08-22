@testable import ApiRelay

extension KeychainStore {
    /// 测试统一入口。MUST NOT 在测试里直接 `KeychainStore(accessGroup: nil)`——
    /// 测试跑在 `ApiRelay.app` 宿主进程里，省略 access group 会落进 App 自己的那个组，
    /// setUp 的 `reset()` 与 `eraseAllUserData()` 会删掉用户本机真实的主密码和密钥明文。
    ///
    /// - Parameter disableSynchronizable: 沿用各用例原有取值；只有专门校验
    ///   `kSecAttrSynchronizable` 的用例需要传 `false`。
    static func makeForTests(disableSynchronizable: Bool = true) -> KeychainStore {
        KeychainStore(
            accessGroup: nil,
            disableSynchronizableForTesting: disableSynchronizable,
            servicePrefix: KeychainStore.testServicePrefix
        )
    }
}
