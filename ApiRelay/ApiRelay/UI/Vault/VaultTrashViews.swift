import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Mac 回收站中栏选中项（密钥 / 账号 / 使用方）。
enum TrashSelection: Hashable {
    case key(UUID)
    case account(UUID)
    case tool(UUID)
}

/// The parent owns split-view selection; the trash child reports current
/// filtered visibility and empty state through bindings. Keep the bridge in
/// one value so checked IDs outside the filter never become batch actions.
struct VaultTrashPresentationState {
    var isSelecting = false
    var checkedItems: Set<TrashSelection> = []
    var visibleItems: Set<TrashSelection> = []
    var hasItems: Bool?

    var actionSelection: TrashBatchSelection {
        trashBatchSelection(from: checkedItems.intersection(visibleItems))
    }

    mutating func resetSelection() {
        isSelecting = false
        checkedItems = []
        visibleItems = []
    }
}

struct RecentlyDeletedView: View {
    @ObservedObject var vault: VaultHomeViewModel
    var showsDismissButton: Bool = true
    /// 左上角账号头像（与密钥列表页同一入口）。
    var onShowAccount: (() -> Void)? = nil
    /// 非 nil = Mac 三栏中栏：行可点选，恢复 / 永久删除放到右侧详情。
    var selection: Binding<TrashSelection?>? = nil
    /// Mac 右栏：加载完成后报告是否有条目（nil = 尚未加载）。
    var reportsHasItems: Binding<Bool?>? = nil
    @Binding var isSelecting: Bool
    @Binding var checkedItems: Set<TrashSelection>
    var visibleItems: Binding<Set<TrashSelection>>? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var keys: [KeyRecordDTO] = []
    @State private var accounts: [UpstreamAccountDTO] = []
    @State private var tools: [ConsumerToolDTO] = []
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var isLoading = true
    @State private var searchText = ""
    /// 必须为 false：true 会立刻进入「搜索激活态」，大标题「回收站」被顶掉、右侧冒出取消 X。
    /// 搜索栏靠 `navigationBarDrawer(displayMode: .always)` 常驻在标题下方（与密钥页一致）。
    @State private var isSearchPresented = false
    @State private var confirmPermanentBatch = false
    @State private var pendingSinglePermanent: TrashSelection?
    @State private var batchBusy = false

    private var usesSplitSelection: Bool { selection != nil && !isSelecting }
    /// Mac 三栏：用自定义顶栏，不用系统 toolbar（否则「完成 / 全选」会变成灰色胶囊）。
    private var usesSplitChrome: Bool { selection != nil }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !searchQuery.isEmpty }

    private var isEmpty: Bool {
        keys.isEmpty && accounts.isEmpty && tools.isEmpty
    }

    private var filteredKeys: [KeyRecordDTO] {
        guard isSearching else { return keys }
        return keys.filter { key in
            if key.displayName.localizedCaseInsensitiveContains(searchQuery) { return true }
            if let platform = platformSubtitle(for: key),
               platform.localizedCaseInsensitiveContains(searchQuery) {
                return true
            }
            return false
        }
    }

    private var filteredAccounts: [UpstreamAccountDTO] {
        guard isSearching else { return accounts }
        return accounts.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchQuery)
                || $0.platform.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var filteredTools: [ConsumerToolDTO] {
        guard isSearching else { return tools }
        return tools.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var isFilterEmpty: Bool {
        !isEmpty && filteredKeys.isEmpty && filteredAccounts.isEmpty && filteredTools.isEmpty
    }

    private var visibleSelections: Set<TrashSelection> {
        Set(filteredKeys.map { TrashSelection.key($0.id) }
            + filteredAccounts.map { TrashSelection.account($0.id) }
            + filteredTools.map { TrashSelection.tool($0.id) })
    }

    private var actionSelection: TrashBatchSelection {
        trashBatchSelection(from: checkedItems.intersection(visibleSelections))
    }

    private var allVisibleChecked: Bool {
        let visible = visibleSelections
        return !visible.isEmpty && visible.isSubset(of: checkedItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            if usesSplitChrome {
                splitTrashChrome
            }
            NavigationStack {
            Group {
                if !isLoading, loadError == nil, isEmpty, selection == nil {
                    emptyCanvas
                } else if let selection, !isSelecting {
                    List(selection: selection) {
                        listBody
                    }
                } else {
                    List {
                        listBody
                    }
                }
            }
            .navigationTitle("vault.recentlyDeleted")
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(
                usesSplitChrome || showsDismissButton ? .inline : .large
            )
            .toolbar(usesSplitChrome ? .hidden : .automatic, for: .navigationBar)
            #endif
            #if os(macOS)
            .navigationSubtitle(isLoading
                ? String(localized: "vault.recentlyDeleted.loading")
                : String(localized: "vault.recentlyDeleted.subtitle \(keys.count) \(accounts.count) \(tools.count)")
            )
            #endif
            .modifier(VaultSearchableModifier(
                searchText: $searchText,
                isSearchPresented: $isSearchPresented,
                prompt: "vault.trash.search.prompt",
                enabled: !usesSplitChrome
            ))
            .toolbar {
                if !usesSplitChrome {
                    if let onShowAccount, !isSelecting {
                        ToolbarItem(placement: .navigation) {
                            Button(action: onShowAccount) {
                                Image(systemName: AppSymbols.Action.account)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.title3)
                            }
                            .accessibilityLabel(Text("vault.sync.title"))
                        }
                    }
                    if isSelecting {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("vault.recentlyDeleted.done") {
                                exitSelectMode()
                            }
                            .disabled(batchBusy)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button(allVisibleChecked ? "vault.trash.deselectAll" : "vault.trash.selectAll") {
                                toggleSelectAll()
                            }
                            .disabled(visibleSelections.isEmpty || batchBusy)
                        }
                    } else {
                        if !visibleSelections.isEmpty {
                            ToolbarItem(placement: .primaryAction) {
                                Button("vault.trash.select") {
                                    enterSelectMode()
                                }
                            }
                        }
                        if showsDismissButton {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("vault.recentlyDeleted.done") { dismiss() }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting, selection == nil, !isEmpty {
                    trashBatchBottomBar
                }
            }
            .confirmationDialog(
                "vault.trash.batch.confirmDelete.title",
                isPresented: $confirmPermanentBatch,
                titleVisibility: .visible
            ) {
                Button("vault.delete.forever", role: .destructive) {
                    Task { await runPermanentBatch() }
                }
                Button("gate.cancel", role: .cancel) {}
            } message: {
                Text("vault.trash.batch.confirmDelete \(actionSelection.itemCount)")
            }
            .confirmationDialog(
                "vault.trash.batch.confirmDelete.title",
                isPresented: Binding(
                    get: { pendingSinglePermanent != nil },
                    set: { if !$0 { pendingSinglePermanent = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("vault.delete.forever", role: .destructive) {
                    if let item = pendingSinglePermanent {
                        pendingSinglePermanent = nil
                        Task { await runSinglePermanent(item) }
                    }
                }
                Button("gate.cancel", role: .cancel) { pendingSinglePermanent = nil }
            } message: {
                Text("vault.trash.batch.confirmDelete \(1)")
            }
            .task { await reload() }
            .onAppear { Task { await reload() } }
            .onChange(of: searchText) { _, _ in
                pruneSelectionIfNeeded()
                publishVisibleItems()
            }
            .onReceive(NotificationCenter.default.publisher(for: .trashBundleDidChange)) { _ in
                Task { await reload() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .userDataDidErase)) { _ in
                selection?.wrappedValue = nil
                Task { await reload() }
            }
            .alert("vault.error.title", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("gate.cancel", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            }
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if isLoading {
            HStack {
                ProgressView()
                Text("vault.recentlyDeleted.loading")
                    .foregroundStyle(.secondary)
            }
        } else if let loadError {
            Section {
                Label(loadError, systemImage: AppSymbols.Action.warning)
                    .foregroundStyle(.secondary)
                Button("vault.recentlyDeleted.retry") {
                    Task { await reload() }
                }
            }
        } else if isEmpty {
            Section {
                emptyHeader
                    .selectionDisabled()
            }
        } else if isFilterEmpty {
            Section {
                Text("vault.trash.search.empty")
                    .font(.headline)
                Text("vault.trash.search.empty.detail")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            if !isSelecting {
                Section {
                    Text("vault.recentlyDeleted.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !filteredKeys.isEmpty {
                Section("vault.recentlyDeleted.section.keys") {
                    ForEach(filteredKeys) { key in
                        trashItemRow(
                            selection: .key(key.id),
                            title: key.displayName,
                            subtitle: platformSubtitle(for: key),
                            deletedAt: key.deletedAt,
                            purgeAfter: key.purgeAfter,
                            onRestore: { await vault.restoreKey(key.id) },
                            onPermanent: { pendingSinglePermanent = .key(key.id) }
                        )
                    }
                }
            }
            if !filteredAccounts.isEmpty {
                Section("vault.recentlyDeleted.section.accounts") {
                    ForEach(filteredAccounts) { account in
                        trashItemRow(
                            selection: .account(account.id),
                            title: account.displayName,
                            subtitle: account.platform,
                            deletedAt: account.deletedAt,
                            purgeAfter: account.purgeAfter,
                            onRestore: { await vault.restoreAccount(account.id) },
                            onPermanent: { pendingSinglePermanent = .account(account.id) }
                        )
                    }
                }
            }
            if !filteredTools.isEmpty {
                Section("vault.recentlyDeleted.section.tools") {
                    ForEach(filteredTools) { tool in
                        trashItemRow(
                            selection: .tool(tool.id),
                            title: tool.name,
                            deletedAt: tool.deletedAt,
                            purgeAfter: tool.purgeAfter,
                            onRestore: { await vault.restoreTool(tool.id) },
                            onPermanent: { pendingSinglePermanent = .tool(tool.id) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trashItemRow(
        selection tag: TrashSelection,
        title: String,
        subtitle: String? = nil,
        deletedAt: Date?,
        purgeAfter: Date?,
        onRestore: @escaping () async -> Void,
        onPermanent: @escaping () async -> Void
    ) -> some View {
        if isSelecting {
            Button {
                toggleChecked(tag)
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    trashCheckbox(for: tag)
                    if selection != nil {
                        trashCompactRow(title: title, subtitle: subtitle, deletedAt: deletedAt)
                    } else {
                        trashInlineInfo(
                            title: title,
                            subtitle: subtitle,
                            deletedAt: deletedAt,
                            purgeAfter: purgeAfter
                        )
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
            .accessibilityAddTraits(checkedItems.contains(tag) ? [.isSelected] : [])
        } else if usesSplitSelection {
            trashCompactRow(title: title, subtitle: subtitle, deletedAt: deletedAt)
                .tag(tag)
        } else {
            trashInlineRow(
                title: title,
                subtitle: subtitle,
                deletedAt: deletedAt,
                purgeAfter: purgeAfter,
                onRestore: onRestore,
                onPermanent: onPermanent
            )
        }
    }

    private func trashCheckbox(for tag: TrashSelection) -> some View {
        Image(systemName: checkedItems.contains(tag) ? AppSymbols.Action.checked : AppSymbols.Action.unchecked)
            .foregroundStyle(checkedItems.contains(tag) ? Color.accentColor : Color.secondary)
            .font(.body)
            .frame(width: 22, alignment: .center)
            .accessibilityHidden(true)
    }

    private func trashCompactRow(
        title: String,
        subtitle: String?,
        deletedAt: Date?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let deletedAt {
                Text(String(localized: "vault.recentlyDeleted.deletedAt \(deletedAt.formatted(date: .abbreviated, time: .shortened))"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func trashInlineRow(
        title: String,
        subtitle: String?,
        deletedAt: Date?,
        purgeAfter: Date?,
        onRestore: @escaping () async -> Void,
        onPermanent: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            trashInlineInfo(
                title: title,
                subtitle: subtitle,
                deletedAt: deletedAt,
                purgeAfter: purgeAfter
            )
            HStack {
                Button("vault.restore") {
                    Task { await runAction(onRestore) }
                }
                Button("vault.delete.forever", role: .destructive) {
                    Task { await runAction(onPermanent) }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func trashInlineInfo(
        title: String,
        subtitle: String?,
        deletedAt: Date?,
        purgeAfter: Date?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let deletedAt {
                Text(String(localized: "vault.recentlyDeleted.deletedAt \(deletedAt.formatted(date: .abbreviated, time: .shortened))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let purgeAfter {
                Text(String(localized: "vault.recentlyDeleted.purgeAt \(purgeAfter.formatted(date: .abbreviated, time: .omitted))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("vault.recentlyDeleted.empty")
                .font(.headline)
            Spacer(minLength: 8)
            InlineHelpButton(
                title: "vault.recentlyDeleted.help.title",
                message: "vault.recentlyDeleted.empty.detail",
                secondaryMessage: "vault.recentlyDeleted.empty.how"
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var emptyCanvas: some View {
        VStack(spacing: 16) {
            Image(systemName: AppSymbols.Tab.trash)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.quaternary)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                Text("vault.recentlyDeleted.empty")
                    .font(.title3.weight(.semibold))
                InlineHelpButton(
                    title: "vault.recentlyDeleted.help.title",
                    message: "vault.recentlyDeleted.empty.detail",
                    secondaryMessage: "vault.recentlyDeleted.empty.how"
                )
            }
            .accessibilityElement(children: .contain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(emptyCanvasBackground)
    }

    private var emptyCanvasBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.gray.opacity(0.12)
        #endif
    }

    private func platformSubtitle(for key: KeyRecordDTO) -> String? {
        if let account = vault.accounts.first(where: { $0.id == key.accountId }) {
            return account.platform
        }
        return accounts.first(where: { $0.id == key.accountId })?.platform
    }

    private func reload() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let bundle = try await vault.loadRecentlyDeletedBundle()
            keys = bundle.keys
            accounts = bundle.accounts
            tools = bundle.tools
            reportsHasItems?.wrappedValue = !(keys.isEmpty && accounts.isEmpty && tools.isEmpty)
            if keys.isEmpty && accounts.isEmpty && tools.isEmpty {
                exitSelectMode()
            }
            pruneSelectionIfNeeded()
            publishVisibleItems()
            if isSelecting {
                checkedItems = checkedItems.intersection(visibleSelections)
            }
        } catch {
            loadError = error.localizedDescription
            keys = []
            accounts = []
            tools = []
            reportsHasItems?.wrappedValue = nil
            selection?.wrappedValue = nil
            exitSelectMode()
            publishVisibleItems()
        }
    }

    private func pruneSelectionIfNeeded() {
        guard let selection, let current = selection.wrappedValue else { return }
        let stillExists: Bool = {
            switch current {
            case .key(let id): return filteredKeys.contains { $0.id == id }
            case .account(let id): return filteredAccounts.contains { $0.id == id }
            case .tool(let id): return filteredTools.contains { $0.id == id }
            }
        }()
        if !stillExists {
            selection.wrappedValue = nil
        }
    }

    private func runAction(_ action: () async -> Void) async {
        vault.errorMessage = nil
        await action()
        if let message = vault.errorMessage {
            actionError = message
            vault.errorMessage = nil
        }
        await reload()
    }

    private func runSinglePermanent(_ item: TrashSelection) async {
        switch item {
        case .key(let id):
            await runAction { await vault.permanentlyDeleteKey(id) }
        case .account(let id):
            await runAction { await vault.permanentlyDeleteAccount(id) }
        case .tool(let id):
            await runAction { await vault.permanentlyDeleteTool(id) }
        }
    }

    private var trashBatchBottomBar: some View {
        HStack(spacing: 12) {
            Text("vault.trash.batch.selected \(actionSelection.itemCount)")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button("vault.restore") {
                Task { await runRestoreBatch() }
            }
            .buttonStyle(.bordered)
            .disabled(actionSelection.isEmpty || batchBusy)
            Button("vault.delete.forever", role: .destructive) {
                confirmPermanentBatch = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(actionSelection.isEmpty || batchBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var splitTrashChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("vault.recentlyDeleted")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                splitTrashChromeActions
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)

            splitSearchField
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider()
        }
        .background(.bar)
    }

    @ViewBuilder
    private var splitTrashChromeActions: some View {
        if isSelecting {
            Button(allVisibleChecked ? "vault.trash.deselectAll" : "vault.trash.selectAll") {
                toggleSelectAll()
            }
            .buttonStyle(.plain)
            .disabled(visibleSelections.isEmpty || batchBusy)
            Button("vault.recentlyDeleted.done") {
                exitSelectMode()
            }
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .disabled(batchBusy)
        } else if !visibleSelections.isEmpty {
            Button("vault.trash.select") {
                enterSelectMode()
            }
            .buttonStyle(.plain)
        }
    }

    private var splitSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: AppSymbols.Action.search)
                .foregroundStyle(.secondary)
            TextField(String(localized: "vault.trash.search.prompt"), text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS) || targetEnvironment(macCatalyst)
                .textInputAutocapitalization(.never)
                #endif
            if isSearching {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: AppSymbols.Action.searchClear)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("vault.search.clear"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("vault.trash.search.prompt"))
    }

    private func enterSelectMode() {
        isSelecting = true
        if checkedItems.isEmpty, let current = selection?.wrappedValue {
            checkedItems.insert(current)
        }
        publishVisibleItems()
    }

    private func exitSelectMode() {
        isSelecting = false
        checkedItems = []
        visibleItems?.wrappedValue = []
    }

    private func toggleSelectAll() {
        if allVisibleChecked {
            checkedItems = []
        } else {
            checkedItems = visibleSelections
        }
    }

    private func toggleChecked(_ tag: TrashSelection) {
        if checkedItems.contains(tag) {
            checkedItems.remove(tag)
        } else {
            checkedItems.insert(tag)
        }
    }

    private func publishVisibleItems() {
        visibleItems?.wrappedValue = visibleSelections
    }

    private func runRestoreBatch() async {
        await runBatch { await vault.restoreTrashBatch($0) }
    }

    private func runPermanentBatch() async {
        await runBatch { await vault.permanentlyDeleteTrashBatch($0) }
    }

    private func runBatch(
        _ operation: (TrashBatchSelection) async -> Result<TrashBatchOutcome, Error>
    ) async {
        let selection = actionSelection
        guard !selection.isEmpty else { return }
        batchBusy = true
        defer { batchBusy = false }
        switch await operation(selection) {
        case .success(let outcome):
            if outcome.hasFailures {
                actionError = trashBatchPartialMessage(outcome)
                await reload()
            } else {
                exitSelectMode()
                await reload()
            }
        case .failure(let error):
            if vault.hasPendingSensitiveRetry { return }
            actionError = error.localizedDescription
        }
    }
}

func trashBatchSelection(from items: Set<TrashSelection>) -> TrashBatchSelection {
    var keyIds: [UUID] = []
    var accountIds: [UUID] = []
    var toolIds: [UUID] = []
    for item in items {
        switch item {
        case .key(let id): keyIds.append(id)
        case .account(let id): accountIds.append(id)
        case .tool(let id): toolIds.append(id)
        }
    }
    return TrashBatchSelection(keyIds: keyIds, accountIds: accountIds, toolIds: toolIds)
}

private func trashBatchPartialMessage(_ outcome: TrashBatchOutcome) -> String {
    let names = outcome.failures.map(\.name).joined(separator: "、")
    return String(localized: "vault.trash.batch.partial \(outcome.successCount) \(names)")
}

/// Mac 回收站右侧：选择模式下的批量恢复 / 永久删除。
struct RecentlyDeletedBatchDetailView: View {
    let selection: TrashBatchSelection
    @ObservedObject var vault: VaultHomeViewModel
    var onFinished: (_ shouldExitSelectMode: Bool) -> Void

    @State private var confirmPermanent = false
    @State private var isBusy = false
    @State private var actionError: String?

    private var pageBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.gray.opacity(0.08)
        #endif
    }

    private var cardFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.primary.opacity(0.04)
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            MacPaneChrome {
                HStack(spacing: 8) {
                    Text("vault.trash.batch.selected \(selection.itemCount)")
                        .font(.headline)
                        .lineLimit(1)
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } trailing: {
                HStack(spacing: 12) {
                    Button("vault.restore") {
                        Task { await runRestore() }
                    }
                    .buttonStyle(.plain)
                    .disabled(selection.isEmpty || isBusy)
                    Button("vault.delete.forever", role: .destructive) {
                        confirmPermanent = true
                    }
                    .buttonStyle(.plain)
                    .disabled(selection.isEmpty || isBusy)
                }
            }

            if selection.isEmpty {
                ContentUnavailableView(
                    "vault.trash.select",
                    systemImage: AppSymbols.Action.unchecked,
                    description: Text("vault.trash.batch.pick")
                )
            } else {
                ScrollView {
                    summaryCard
                        .padding(20)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                }
                .background(pageBackground)
            }
        }
        .background(pageBackground)
        .confirmationDialog(
            "vault.trash.batch.confirmDelete.title",
            isPresented: $confirmPermanent,
            titleVisibility: .visible
        ) {
            Button("vault.delete.forever", role: .destructive) {
                Task { await runPermanent() }
            }
            Button("gate.cancel", role: .cancel) {}
        } message: {
            Text("vault.trash.batch.confirmDelete \(selection.itemCount)")
        }
        .alert("vault.error.title", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("gate.cancel", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !selection.keyIds.isEmpty {
                countRow("vault.recentlyDeleted.section.keys", count: selection.keyIds.count)
            }
            if !selection.accountIds.isEmpty {
                if !selection.keyIds.isEmpty { cardDivider() }
                countRow("vault.recentlyDeleted.section.accounts", count: selection.accountIds.count)
            }
            if !selection.toolIds.isEmpty {
                if !selection.keyIds.isEmpty || !selection.accountIds.isEmpty { cardDivider() }
                countRow("vault.recentlyDeleted.section.tools", count: selection.toolIds.count)
            }
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private func countRow(_ title: LocalizedStringKey, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text("\(count)")
                .monospacedDigit()
        }
        .font(.body)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func cardDivider() -> some View {
        Divider()
    }

    private func runRestore() async {
        await run { await vault.restoreTrashBatch($0) }
    }

    private func runPermanent() async {
        await run { await vault.permanentlyDeleteTrashBatch($0) }
    }

    private func run(
        _ operation: (TrashBatchSelection) async -> Result<TrashBatchOutcome, Error>
    ) async {
        guard !selection.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        switch await operation(selection) {
        case .success(let outcome):
            NotificationCenter.default.post(name: .trashBundleDidChange, object: nil)
            if outcome.hasFailures {
                actionError = trashBatchPartialMessage(outcome)
                onFinished(false)
            } else {
                onFinished(true)
            }
        case .failure(let error):
            if vault.hasPendingSensitiveRetry { return }
            actionError = error.localizedDescription
        }
    }
}

/// Mac 回收站右侧详情：展示选中项元数据与恢复 / 永久删除。
struct RecentlyDeletedDetailHost: View {
    let selection: TrashSelection
    @ObservedObject var vault: VaultHomeViewModel
    var onCleared: () -> Void

    @State private var keys: [KeyRecordDTO] = []
    @State private var accounts: [UpstreamAccountDTO] = []
    @State private var tools: [ConsumerToolDTO] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var confirmPermanent = false

    var body: some View {
        VStack(spacing: 0) {
            MacPaneChrome {
                Text(resolvedModel?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
            } trailing: {
                if let model = resolvedModel {
                    HStack(spacing: 12) {
                        Button("vault.restore") {
                            Task { await runAction(model.restore) }
                        }
                        .buttonStyle(.plain)
                        Button("vault.delete.forever", role: .destructive) {
                            confirmPermanent = true
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    ContentUnavailableView {
                        Label(loadError, systemImage: AppSymbols.Action.warning)
                    } actions: {
                        Button("vault.recentlyDeleted.retry") {
                            Task { await reload() }
                        }
                    }
                } else if let model = resolvedModel {
                    RecentlyDeletedDetailView(model: model)
                } else {
                    ContentUnavailableView(
                        "vault.trash.missing.title",
                        systemImage: AppSymbols.Tab.trash,
                        description: Text("vault.trash.missing.detail")
                    )
                    .onAppear { onCleared() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: selection) { await reload() }
        .confirmationDialog(
            "vault.trash.batch.confirmDelete.title",
            isPresented: $confirmPermanent,
            titleVisibility: .visible
        ) {
            Button("vault.delete.forever", role: .destructive) {
                if let model = resolvedModel {
                    Task { await runAction(model.permanent) }
                }
            }
            Button("gate.cancel", role: .cancel) {}
        } message: {
            Text("vault.trash.batch.confirmDelete \(1)")
        }
        .alert("vault.error.title", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("gate.cancel", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var resolvedModel: TrashDetailModel? {
        switch selection {
        case .key(let id):
            guard let key = keys.first(where: { $0.id == id }) else { return nil }
            let platform = vault.accounts.first(where: { $0.id == key.accountId })?.platform
                ?? accounts.first(where: { $0.id == key.accountId })?.platform
            return TrashDetailModel(
                title: key.displayName,
                subtitle: platform,
                kindTitleKey: "vault.recentlyDeleted.section.keys",
                systemImage: AppSymbols.Key.default,
                deletedAt: key.deletedAt,
                purgeAfter: key.purgeAfter,
                restore: { await vault.restoreKey(key.id) },
                permanent: { await vault.permanentlyDeleteKey(key.id) }
            )
        case .account(let id):
            guard let account = accounts.first(where: { $0.id == id }) else { return nil }
            return TrashDetailModel(
                title: account.displayName,
                subtitle: account.platform,
                kindTitleKey: "vault.recentlyDeleted.section.accounts",
                systemImage: AppSymbols.Entity.accountFill,
                deletedAt: account.deletedAt,
                purgeAfter: account.purgeAfter,
                restore: { await vault.restoreAccount(account.id) },
                permanent: { await vault.permanentlyDeleteAccount(account.id) }
            )
        case .tool(let id):
            guard let tool = tools.first(where: { $0.id == id }) else { return nil }
            return TrashDetailModel(
                title: tool.name,
                subtitle: nil,
                kindTitleKey: "vault.recentlyDeleted.section.tools",
                systemImage: AppSymbols.Entity.tool,
                deletedAt: tool.deletedAt,
                purgeAfter: tool.purgeAfter,
                restore: { await vault.restoreTool(tool.id) },
                permanent: { await vault.permanentlyDeleteTool(tool.id) }
            )
        }
    }

    private func reload() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let bundle = try await vault.loadRecentlyDeletedBundle()
            keys = bundle.keys
            accounts = bundle.accounts
            tools = bundle.tools
        } catch {
            loadError = error.localizedDescription
            keys = []
            accounts = []
            tools = []
        }
    }

    private func runAction(_ action: () async -> Void) async {
        vault.errorMessage = nil
        await action()
        if let message = vault.errorMessage {
            actionError = message
            vault.errorMessage = nil
            return
        }
        onCleared()
        await reload()
        // 让中栏列表也刷新：详情侧已清选中；列表靠 onAppear/task 可能未触发，
        // 通过再拉一次主列表数据由 RecentlyDeletedView.onAppear 不够——发通知太重。
        // 切 tab 会清；此处依赖列表的 .task 不会重跑。补：列表用 onChange of selectedTrashItem。
        NotificationCenter.default.post(name: .trashBundleDidChange, object: nil)
    }
}

extension Notification.Name {
    static let trashBundleDidChange = Notification.Name("ApiRelay.trashBundleDidChange")
}

private struct TrashDetailModel {
    let title: String
    let subtitle: String?
    let kindTitleKey: LocalizedStringKey
    let systemImage: String
    let deletedAt: Date?
    let purgeAfter: Date?
    let restore: () async -> Void
    let permanent: () async -> Void
}

private struct RecentlyDeletedDetailView: View {
    let model: TrashDetailModel

    private var pageBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.gray.opacity(0.08)
        #endif
    }

    private var cardFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.primary.opacity(0.04)
        #endif
    }

    var body: some View {
        ScrollView {
            infoCard
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
        .background(pageBackground)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: model.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary)
                    )
                    .accessibilityHidden(true)
                Text(model.kindTitleKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)

            if let subtitle = model.subtitle, !subtitle.isEmpty {
                detailRow("vault.detail.platform", value: subtitle)
                cardDivider()
            }
            if let deletedAt = model.deletedAt {
                detailRow(
                    "vault.trash.field.deletedAt",
                    value: deletedAt.formatted(date: .abbreviated, time: .shortened)
                )
                cardDivider()
            }
            if let purgeAfter = model.purgeAfter {
                detailRow(
                    "vault.trash.field.purgeAt",
                    value: purgeAfter.formatted(date: .abbreviated, time: .omitted)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private func detailRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
        .padding(.vertical, 10)
    }

    private func cardDivider() -> some View {
        Divider()
    }
}
