#if os(macOS)
import AppKit
import SwiftUI

/// macOS 列表内重排：NSTableView + gap；拖影截取真实 rowView（业界常用修法，避免离屏假单元格错位）。
struct MacReorderableKeyTable: NSViewRepresentable {
    @Binding var keys: [KeyRecordDTO]
    var onOrderChanged: ([UUID]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(keys: keys)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ReorderTableScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init()

        let table = NSTableView()
        table.headerView = nil
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.allowsColumnResizing = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.rowHeight = 56
        table.intercellSpacing = .zero
        table.backgroundColor = .windowBackgroundColor
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .none
        table.gridStyleMask = []
        table.draggingDestinationFeedbackStyle = .gap
        table.style = .fullWidth
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.registerForDraggedTypes([Coordinator.pasteboardType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 160
        table.addTableColumn(column)

        scrollView.documentView = table
        context.coordinator.tableView = table
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onOrderChanged = onOrderChanged
        context.coordinator.onKeysBound = { keys = $0 }
        (scrollView as? ReorderTableScrollView)?.fitColumnToVisibleWidth()

        let oldIDs = context.coordinator.keys.map(\.id)
        let newIDs = keys.map(\.id)
        context.coordinator.keys = keys
        guard oldIDs != newIDs,
              let table = context.coordinator.tableView,
              !context.coordinator.isMutatingRows else { return }
        table.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let pasteboardType = NSPasteboard.PasteboardType("com.apirelay.vault.key-reorder")
        static let cellID = NSUserInterfaceItemIdentifier("KeyReorderCell")

        var keys: [KeyRecordDTO]
        var onOrderChanged: (([UUID]) -> Void)?
        var onKeysBound: (([KeyRecordDTO]) -> Void)?
        weak var tableView: NSTableView?
        var isMutatingRows = false
        /// 自绘跟手层：系统 gap 拖影在 view-based 表格上经常是空白，不能依赖它。
        private var dragProxy: NSImageView?
        private var dragProxyGrabOffset = NSPoint.zero
        private var pendingDragImage: NSImage?
        private var pendingDragRow: Int?

        init(keys: [KeyRecordDTO]) {
            self.keys = keys
        }

        func numberOfRows(in tableView: NSTableView) -> Int { keys.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard keys.indices.contains(row) else { return nil }
            let cell: KeyReorderCell
            if let reused = tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? KeyReorderCell {
                cell = reused
            } else {
                cell = KeyReorderCell()
                cell.identifier = Self.cellID
            }
            cell.configure(with: keys[row])
            return cell
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard keys.indices.contains(row) else { return nil }
            let size = tableView.rect(ofRow: row).size
            pendingDragRow = row
            pendingDragImage = KeyReorderCell.makeOpaqueDragImage(for: keys[row], size: size)

            let item = NSPasteboardItem()
            item.setString(keys[row].id.uuidString, forType: Self.pasteboardType)
            return item
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            session.animatesToStartingPositionsOnCancelOrFail = true

            // 关掉系统拖影（gap 下常为空白），改用窗口内跟手 proxy。
            session.enumerateDraggingItems(
                options: [],
                for: tableView,
                classes: [NSPasteboardItem.self],
                searchOptions: [:]
            ) { dragItem, _, _ in
                dragItem.imageComponentsProvider = { [] }
            }

            guard
                let image = pendingDragImage,
                let row = pendingDragRow ?? rowIndexes.first,
                let window = tableView.window,
                let content = window.contentView
            else { return }

            let rowRectInWindow = tableView.convert(tableView.rect(ofRow: row), to: nil)
            let mouseInWindow = window.convertPoint(fromScreen: screenPoint)
            dragProxyGrabOffset = NSPoint(
                x: mouseInWindow.x - rowRectInWindow.minX,
                y: mouseInWindow.y - rowRectInWindow.minY
            )

            let proxy = NSImageView(image: image)
            proxy.imageScaling = .scaleNone
            proxy.wantsLayer = true
            proxy.layer?.shadowColor = NSColor.black.cgColor
            proxy.layer?.shadowOpacity = 0.22
            proxy.layer?.shadowRadius = 8
            proxy.layer?.shadowOffset = CGSize(width: 0, height: -2)
            proxy.frame = rowRectInWindow
            content.addSubview(proxy)
            dragProxy = proxy
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            movedTo screenPoint: NSPoint
        ) {
            guard let window = tableView.window, let proxy = dragProxy else { return }
            let mouseInWindow = window.convertPoint(fromScreen: screenPoint)
            proxy.setFrameOrigin(NSPoint(
                x: mouseInWindow.x - dragProxyGrabOffset.x,
                y: mouseInWindow.y - dragProxyGrabOffset.y
            ))
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            clearDragProxy()
        }

        private func clearDragProxy() {
            dragProxy?.removeFromSuperview()
            dragProxy = nil
            pendingDragImage = nil
            pendingDragRow = nil
            dragProxyGrabOffset = .zero
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard
                info.draggingSource as? NSTableView === tableView,
                dropOperation == .above
            else { return [] }
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard
                info.draggingSource as? NSTableView === tableView,
                let raw = info.draggingPasteboard.string(forType: Self.pasteboardType),
                let id = UUID(uuidString: raw),
                let from = keys.firstIndex(where: { $0.id == id })
            else { return false }

            var to = row
            if from < to { to -= 1 }
            guard to >= 0, to < keys.count, from != to else { return false }

            var next = keys
            let item = next.remove(at: from)
            next.insert(item, at: to)

            isMutatingRows = true
            keys = next
            onKeysBound?(next)
            clearDragProxy()
            tableView.beginUpdates()
            tableView.moveRow(at: from, to: to)
            tableView.endUpdates()
            isMutatingRows = false

            onOrderChanged?(next.map(\.id))
            return true
        }
    }
}

private final class ReorderTableScrollView: NSScrollView {
    override func layout() {
        super.layout()
        fitColumnToVisibleWidth()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitColumnToVisibleWidth()
    }

    func fitColumnToVisibleWidth() {
        guard
            let table = documentView as? NSTableView,
            let column = table.tableColumns.first
        else { return }
        let visible = contentView.bounds.width
        guard visible > 1 else { return }
        if abs(column.width - visible) > 0.5 {
            column.width = visible
        }
        table.sizeLastColumnToFit()
        if contentView.bounds.origin.x != 0 {
            contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y))
        }
    }
}

private final class KeyReorderCell: NSTableCellView {
    private let iconBadge = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let handleView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with key: KeyRecordDTO) {
        titleLabel.stringValue = key.displayName
        if let hint = key.maskedHint {
            subtitleLabel.stringValue = "••••\(hint)"
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.stringValue = ""
            subtitleLabel.isHidden = true
        }
    }

    /// 不依赖表格截图：按行尺寸离屏画出不透明拖影，保证跟手可见。
    static func makeOpaqueDragImage(for key: KeyRecordDTO, size: NSSize) -> NSImage {
        let drawSize = NSSize(width: max(size.width, 120), height: max(size.height, 44))
        let cell = KeyReorderCell(frame: NSRect(origin: .zero, size: drawSize))
        cell.configure(with: key)
        cell.wantsLayer = true
        cell.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cell.layer?.cornerRadius = 8
        cell.layer?.masksToBounds = true

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: drawSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .controlBackgroundColor
        window.contentView = cell
        cell.layoutSubtreeIfNeeded()
        defer {
            window.contentView = nil
            window.close()
        }

        guard let rep = cell.bitmapImageRepForCachingDisplay(in: cell.bounds) else {
            return NSImage(size: drawSize)
        }
        cell.cacheDisplay(in: cell.bounds, to: rep)
        let image = NSImage(size: drawSize)
        image.addRepresentation(rep)
        return image
    }

    private func setup() {
        iconBadge.wantsLayer = true
        iconBadge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        iconBadge.layer?.cornerRadius = 7
        iconBadge.translatesAutoresizingMaskIntoConstraints = false

        let keyConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(keyConfig)
        iconView.contentTintColor = .white
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignCenter
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let handleConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        handleView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(handleConfig)
        handleView.contentTintColor = .secondaryLabelColor
        handleView.imageScaling = .scaleProportionallyUpOrDown
        handleView.imageAlignment = .alignCenter

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let root = NSStackView(views: [iconBadge, textStack, spacer, handleView])
        root.orientation = .horizontal
        root.alignment = .centerY
        root.distribution = .fill
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            iconBadge.widthAnchor.constraint(equalToConstant: 28),
            iconBadge.heightAnchor.constraint(equalToConstant: 28),
            iconView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            handleView.widthAnchor.constraint(equalToConstant: 22),
            handleView.heightAnchor.constraint(equalToConstant: 22),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        iconBadge.setContentHuggingPriority(.required, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        handleView.setContentHuggingPriority(.required, for: .horizontal)
        handleView.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
}
#endif
