# v1.13.10 界面回归测试

`ApiRelayUITests` 是独立的 XCUITest runner。通过 `APIRELAY_UI_TEST_SCENARIO` 让 Debug 应用启动内存 fixture；fixture 不读写正式 Keychain、CloudKit、SwiftData 库或正式偏好。测试密码只用于 fixture，不进入产品数据。

运行方式：选择 `ApiRelay` scheme 和 iPhone、iPad 或 Mac 目的地，运行 `ApiRelayUITests`。界面测试不会代替真机的 Face ID、Touch ID 与设备密码验证；这些仍需设备验收。测试失败必须保留诊断结果，不能按平台跳过后宣称通过。
