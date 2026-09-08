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

/// 列表/编辑页头像：角上铅笔表示可点进去改。
struct EditableAvatarButton: View {
    var choice: AvatarChoice
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 14
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                VaultAvatarView(choice: choice, size: size, cornerRadius: cornerRadius)
                Image(systemName: AppSymbols.Action.edit)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.accentColor))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("vault.avatar"))
        .accessibilityHint(Text("vault.avatar.edit.hint"))
    }
}

/// 编辑某一条时选用符号与底色。
struct AvatarPicker: View {
    @Binding var choice: AvatarChoice

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AvatarCatalog.symbols, id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(choice.symbol == symbol ? Color.white : Color.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(choice.symbol == symbol ? choice.color.fill : Color.primary.opacity(0.06))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { choice.symbol = symbol }
                        .accessibilityElement()
                        .accessibilityLabel(Text(symbol))
                        .accessibilityAddTraits(choice.symbol == symbol ? [.isButton, .isSelected] : .isButton)
                }
            }
            HStack(spacing: 8) {
                ForEach(AvatarColorToken.allCases, id: \.self) { token in
                    Circle()
                        .fill(token.fill)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(choice.color == token ? 0.9 : 0.12), lineWidth: choice.color == token ? 2 : 1)
                        )
                        .contentShape(Circle())
                        .onTapGesture { choice.color = token }
                        .accessibilityElement()
                        .accessibilityLabel(Text(token.rawValue))
                        .accessibilityAddTraits(choice.color == token ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }
}

/// 某一条的头像：打开编辑即可选；未改过则用产品默认，可一键恢复。
struct AvatarOverrideEditor: View {
    var defaultChoice: AvatarChoice
    @Binding var usesDefault: Bool
    @Binding var customChoice: AvatarChoice

    private var displayed: AvatarChoice {
        usesDefault ? defaultChoice : customChoice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VaultAvatarView(choice: displayed, size: 36, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("vault.avatar")
                    Text(usesDefault ? "vault.avatar.usingDefault" : "vault.avatar.custom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            AvatarPicker(
                choice: Binding(
                    get: { displayed },
                    set: { newValue in
                        customChoice = newValue
                        usesDefault = false
                    }
                )
            )
            if !usesDefault {
                Button("vault.avatar.useDefault") {
                    usesDefault = true
                    customChoice = defaultChoice
                }
            }
        }
    }
}
