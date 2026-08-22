import Foundation

/// 未通过门闩取出明文时的密钥遮罩。
///
/// 点数**固定**，不接受任何参数：长密钥与短密钥呈现完全一致，界面 MUST NOT 由此泄露真实长度。
/// 若将来需要「按长度画点」，那是对宪法 VII 的违反，MUST NOT 加回来。
enum SecretMask {
    static let dotCount = 12

    static let dots = String(repeating: "•", count: dotCount)
}
