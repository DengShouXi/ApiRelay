import SwiftUI

extension AvatarColorToken {
    var fill: Color {
        switch self {
        case .accent: return Color.accentColor
        case .blue: return Color(red: 0.22, green: 0.40, blue: 0.78)
        case .indigo: return Color(red: 0.28, green: 0.36, blue: 0.72)
        case .teal: return Color(red: 0.12, green: 0.56, blue: 0.44)
        case .orange: return Color(red: 0.82, green: 0.42, blue: 0.12)
        case .plum: return Color(red: 0.52, green: 0.28, blue: 0.62)
        case .slate: return Color(red: 0.36, green: 0.42, blue: 0.52)
        }
    }
}

struct VaultAvatarView: View {
    var choice: AvatarChoice
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 6

    var body: some View {
        Image(systemName: choice.symbol)
            .font(size >= 48 ? .title.weight(.semibold) : .caption.weight(.bold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(choice.color.fill)
            )
            .accessibilityHidden(true)
    }
}

/// 编辑页 / 设置页共用的符号 + 底色网格。
struct AvatarPicker: View {
    @Binding var choice: AvatarChoice

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AvatarCatalog.symbols, id: \.self) { symbol in
                    Button {
                        choice.symbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(choice.symbol == symbol ? Color.white : Color.primary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(choice.symbol == symbol ? choice.color.fill : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(symbol))
                }
            }
            HStack(spacing: 8) {
                ForEach(AvatarColorToken.allCases, id: \.self) { token in
                    Button {
                        choice.color = token
                    } label: {
                        Circle()
                            .fill(token.fill)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(choice.color == token ? 0.9 : 0.12), lineWidth: choice.color == token ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(token.rawValue))
                }
            }
        }
    }
}

/// 某一条的头像：默认可一键恢复。
struct AvatarOverrideEditor: View {
    var defaultChoice: AvatarChoice
    @Binding var usesDefault: Bool
    @Binding var customChoice: AvatarChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VaultAvatarView(choice: usesDefault ? defaultChoice : customChoice, size: 36, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("vault.avatar")
                    Text(usesDefault ? "vault.avatar.usingDefault" : "vault.avatar.custom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if usesDefault {
                Button("vault.avatar.customize") {
                    customChoice = defaultChoice
                    usesDefault = false
                }
            } else {
                AvatarPicker(choice: $customChoice)
                Button("vault.avatar.useDefault") {
                    usesDefault = true
                }
            }
        }
    }
}
