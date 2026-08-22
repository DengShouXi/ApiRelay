import SwiftUI

/// 设置子页共用的分组底与卡片，避免 Catalyst `Form` 漂在白底中间。
enum SettingsChrome {
    static var isMacDesktop: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// 设置卡片可读宽度上限。窗口再宽也不把一行拉满。
    static let columnMaxWidth: CGFloat = 560
    /// 右栏窄于此时贴左；更宽则水平居中。
    static let columnCenterThreshold: CGFloat = 560

    static var contentMaxWidth: CGFloat { columnMaxWidth }

    struct ColumnPlacement: Equatable {
        var centersColumn: Bool
        var horizontalPadding: CGFloat
        var topPadding: CGFloat
        var bottomPadding: CGFloat
    }

    /// iPhone 铺满；Mac / iPad 宽屏按右栏宽度在「贴左」和「居中」之间切换。
    static func columnPlacement(
        containerWidth: CGFloat,
        sizeClass: UserInterfaceSizeClass?
    ) -> ColumnPlacement {
        #if os(macOS) || targetEnvironment(macCatalyst)
        _ = sizeClass
        return adaptiveColumn(containerWidth: containerWidth)
        #else
        if sizeClass != .regular {
            return ColumnPlacement(
                centersColumn: false,
                horizontalPadding: 20,
                topPadding: 12,
                bottomPadding: 28
            )
        }
        return adaptiveColumn(containerWidth: containerWidth)
        #endif
    }

    private static func adaptiveColumn(containerWidth: CGFloat) -> ColumnPlacement {
        if containerWidth <= columnCenterThreshold {
            return ColumnPlacement(
                centersColumn: false,
                horizontalPadding: 16,
                topPadding: 16,
                bottomPadding: 40
            )
        }
        return ColumnPlacement(
            centersColumn: true,
            horizontalPadding: 28,
            topPadding: 28,
            bottomPadding: 40
        )
    }

    static func groupedBackground(_ colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(white: isMacDesktop ? 0.12 : 0.14)
        }
        if isMacDesktop {
            // Catalyst 的 systemGroupedBackground 接近纯白，白卡片会贴在白窗上。
            return Color(red: 0.918, green: 0.918, blue: 0.933)
        }
        #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(red: 0.949, green: 0.949, blue: 0.969)
        #endif
    }

    static func cardFill(_ colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(white: isMacDesktop ? 0.17 : 0.18)
        }
        if isMacDesktop {
            return Color.white
        }
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color.white
        #endif
    }

    static func fieldFill(_ colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(white: 0.22)
        }
        #if canImport(UIKit)
        return Color(uiColor: .tertiarySystemFill)
        #else
        return Color(white: 0.96)
        #endif
    }

    static func cardStroke(_ colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.06)
    }
}

/// 设置首页 / 子页共用：铺满右栏，宽则居中窄栏，窄则贴左。滚动条贴窗口右侧。
struct SettingsColumnScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS) || targetEnvironment(macCatalyst)
    @State private var containerWidth: CGFloat = 900
    #else
    @State private var containerWidth: CGFloat = 390
    #endif

    var body: some View {
        let placement = SettingsChrome.columnPlacement(
            containerWidth: containerWidth,
            sizeClass: horizontalSizeClass
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(.horizontal, placement.horizontalPadding)
            .padding(.top, placement.topPadding)
            .padding(.bottom, placement.bottomPadding)
            .frame(maxWidth: SettingsChrome.columnMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: placement.centersColumn ? .center : .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { containerWidth = $0 }
        .background(SettingsChrome.groupedBackground(colorScheme))
    }
}

/// Mac 两栏右栏自己的顶栏。MUST NOT 用系统 toolbar，否则标题会跑到红绿灯旁。
struct SettingsMacChromeBar: View {
    var title: LocalizedStringKey
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let onBack {
                    Button(action: onBack) {
                        Label("settings.back", systemImage: AppSymbols.Action.chevronBackward)
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 24, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            Divider()
        }
        .background(.bar)
    }
}

struct SettingsSubpage<Content: View>: View {
    var title: LocalizedStringKey
    /// 设置两栏推入为 true；sheet（如从访达打开备份）保持系统导航。
    var usesMacColumnChrome: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if pinLeading {
                VStack(spacing: 0) {
                    SettingsMacChromeBar(title: title) { dismiss() }
                    scrollContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                scrollContent
            }
        }
        .background(SettingsChrome.groupedBackground(colorScheme).ignoresSafeArea())
        .navigationTitle(pinLeading ? "" : title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(pinLeading)
        .toolbar(pinLeading ? .hidden : .automatic, for: .navigationBar)
        #if !targetEnvironment(macCatalyst)
        .toolbarBackground(SettingsChrome.groupedBackground(colorScheme), for: .navigationBar)
        #endif
        #endif
    }

    private var scrollContent: some View {
        SettingsColumnScroll {
            content()
        }
    }

    private var pinLeading: Bool {
        usesMacColumnChrome && SettingsChrome.isMacDesktop
    }
}

struct SettingsCard<Content: View>: View {
    var title: LocalizedStringKey? = nil
    var danger: Bool = false
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(danger ? Color.red.opacity(0.85) : Color.secondary)
                    .padding(.horizontal, 16)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsChrome.cardFill(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SettingsChrome.cardStroke(colorScheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(
                color: SettingsChrome.isMacDesktop
                    ? Color.clear
                    : Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04),
                radius: 2,
                y: 1
            )
        }
    }
}

struct SettingsCardDivider: View {
    var leadingInset: CGFloat = 16

    var body: some View {
        Divider()
            .opacity(0.7)
            .padding(.leading, leadingInset)
    }
}

struct SettingsFooterNote: View {
    var text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }
}

struct SettingsPrimaryButton: View {
    var title: LocalizedStringKey
    var disabled: Bool = false
    var role: ButtonRole? = nil
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled)
        .tint(role == .destructive ? .red : nil)
    }
}

struct SettingsSecureField: View {
    var title: LocalizedStringKey
    @Binding var text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SecureField("", text: $text)
                .textContentType(.none)
                .textFieldStyle(.plain)
                .accessibilityLabel(Text(title))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SettingsChrome.fieldFill(colorScheme))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct SettingsChoiceRow: View {
    var title: LocalizedStringKey
    var selected: Bool
    var enabled: Bool = true
    var subtitle: LocalizedStringKey? = nil
    var helpTitle: LocalizedStringKey? = nil
    var helpMessage: LocalizedStringResource? = nil
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: action) {
                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let helpTitle, let helpMessage {
                InlineHelpButton(title: helpTitle, message: helpMessage, showsTitle: false)
            }

            Button(action: action) {
                Image(systemName: AppSymbols.Settings.checkmark)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!enabled)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, SettingsChrome.isMacDesktop ? 10 : 12)
        .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct SettingsTaskSheet: ViewModifier {
    func body(content: Content) -> some View {
        content
            #if os(iOS) || targetEnvironment(macCatalyst)
            .presentationDragIndicator(.visible)
            #endif
            #if os(iOS) && !targetEnvironment(macCatalyst)
            .presentationDetents([.large])
            #endif
    }
}

extension View {
    /// 一次性任务（购买等）盖在当前页上，不推进设置导航栈。
    func settingsTaskSheet() -> some View {
        modifier(SettingsTaskSheet())
    }
}

struct SettingsStatusBanner: View {
    var text: String
    var isError: Bool = false

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
    }
}
