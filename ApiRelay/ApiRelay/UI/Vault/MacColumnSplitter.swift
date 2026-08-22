import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Mac 三栏宽度：默认 / 夹紧范围。窗口变窄时只压缩显示，不改用户记住的宽度。
enum MacColumnLayout {
    static let sidebarDefault: CGFloat = 200
    static let sidebarMin: CGFloat = 160
    static let sidebarMax: CGFloat = 280
    static let contentDefault: CGFloat = 340
    static let contentMin: CGFloat = 280
    static let contentMax: CGFloat = 520
    static let detailMinIdeal: CGFloat = 360
    static let detailMinFloor: CGFloat = 200
    static let settingsContentMin: CGFloat = 400
    static let splitterThickness: CGFloat = 1

    static var sidebarRange: ClosedRange<CGFloat> { sidebarMin...sidebarMax }
    static var contentRange: ClosedRange<CGFloat> { contentMin...contentMax }

    struct Fitted: Equatable {
        var sidebar: CGFloat
        var content: CGFloat
    }

    static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// 大窗口保证详情约 360；720 宽的窗口按剩余空间降到下限，避免和窗口最小宽度打架。
    static func detailMin(containerWidth: CGFloat) -> CGFloat {
        let available = containerWidth - sidebarMin - contentMin - splitterThickness * 2
        return min(detailMinIdeal, max(detailMinFloor, available))
    }

    static func fitted(
        storedSidebar: CGFloat,
        storedContent: CGFloat,
        containerWidth: CGFloat,
        twoColumn: Bool
    ) -> Fitted {
        var sidebar = clamp(storedSidebar, to: sidebarRange)
        var content = clamp(storedContent, to: contentRange)
        guard containerWidth > 0 else {
            return Fitted(sidebar: sidebar, content: twoColumn ? 0 : content)
        }

        if twoColumn {
            let maxSidebar = min(
                sidebarMax,
                max(sidebarMin, containerWidth - settingsContentMin - splitterThickness)
            )
            return Fitted(sidebar: min(sidebar, maxSidebar), content: 0)
        }

        let dMin = detailMin(containerWidth: containerWidth)
        let budget = containerWidth - dMin - splitterThickness * 2
        let overflow = sidebar + content - budget
        if overflow > 0 {
            let contentShrink = min(overflow, content - contentMin)
            content -= contentShrink
            let rest = overflow - contentShrink
            if rest > 0 {
                sidebar = max(sidebarMin, sidebar - rest)
            }
        }
        return Fitted(sidebar: sidebar, content: content)
    }

    static func maxSidebar(
        containerWidth: CGFloat,
        contentWidth: CGFloat,
        twoColumn: Bool
    ) -> CGFloat {
        if twoColumn {
            return min(
                sidebarMax,
                max(sidebarMin, containerWidth - settingsContentMin - splitterThickness)
            )
        }
        let dMin = detailMin(containerWidth: containerWidth)
        return min(
            sidebarMax,
            max(sidebarMin, containerWidth - contentWidth - dMin - splitterThickness * 2)
        )
    }

    static func maxContent(containerWidth: CGFloat, sidebarWidth: CGFloat) -> CGFloat {
        let dMin = detailMin(containerWidth: containerWidth)
        return min(
            contentMax,
            max(contentMin, containerWidth - sidebarWidth - dMin - splitterThickness * 2)
        )
    }
}

/// 1pt 竖线 + 约 10pt 热区。拖动改栏宽；双击回到默认。
struct MacColumnSplitter: View {
    var displayedWidth: CGFloat
    @Binding var width: CGFloat
    var range: ClosedRange<CGFloat>
    var defaultWidth: CGFloat
    var additionalMax: CGFloat

    @State private var widthAtDragStart: CGFloat?

    private var lowerBound: CGFloat { range.lowerBound }
    private var upperBound: CGFloat {
        max(lowerBound, min(range.upperBound, additionalMax))
    }

    var body: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        ExclusiveGesture(
                            dragGesture,
                            TapGesture(count: 2).onEnded(reset)
                        )
                    )
                    .macColumnResizePointer()
            }
            .zIndex(1)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if widthAtDragStart == nil {
                    widthAtDragStart = displayedWidth
                }
                let proposed = (widthAtDragStart ?? displayedWidth) + value.translation.width
                width = MacColumnLayout.clamp(proposed, to: lowerBound...upperBound)
            }
            .onEnded { _ in
                widthAtDragStart = nil
            }
    }

    private func reset() {
        width = MacColumnLayout.clamp(defaultWidth, to: lowerBound...upperBound)
        widthAtDragStart = nil
    }
}

private extension View {
    /// Catalyst 走 iOS SwiftUI，没有 `pointerStyle`；用 AppKit 光标。
    func macColumnResizePointer() -> some View {
        #if canImport(AppKit)
        self.onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        #else
        self
        #endif
    }
}
