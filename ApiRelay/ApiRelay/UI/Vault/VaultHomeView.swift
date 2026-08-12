import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
#endif

/// 一级导航：按平台 / 按使用方 / 回收站 / 设置。
/// iPhone：底栏 Tab；Mac / Catalyst：左侧边栏。
enum VaultRootTab: Hashable {
    case byPlatform
    case byConsumer
    case trash
    case settings

    /// 底栏 / 侧栏短标题（英文比「By Platform」更不易截断）。
    var titleKey: LocalizedStringKey {
        switch self {
        case .byPlatform: "vault.tab.byPlatform"
        case .byConsumer: "vault.tab.byConsumer"
        case .trash: "vault.tab.trash"
        case .settings: "vault.tab.settings"
        }
    }

    var systemImage: String {
        switch self {
        case .byPlatform: AppSymbols.Tab.byPlatform
        case .byConsumer: AppSymbols.Tab.byConsumer
        case .trash: AppSymbols.Tab.trash
        case .settings: AppSymbols.Tab.settings
        }
    }
}

struct VaultHomeView: View {
    @ObservedObject var viewModel: VaultHomeViewModel
    @State private var selectedTab: VaultRootTab = .byPlatform
    /// 侧栏 `List(selection:)` 在 iOS/Catalyst 需要 Optional。
    private var sidebarSelection: Binding<VaultRootTab?> {
        Binding(
            get: { selectedTab },
            set: { if let tab = $0 { selectedTab = tab } }
        )
    }
    @State private var showAddAccount = false
    @State private var showAddTool = false
    @State private var showAddKeyFor: UpstreamAccountDTO?
    /// 账号 sheet 关闭后再弹出密钥 sheet，避免 macOS 上双 sheet 抢呈现。
    @State private var pendingAddKeyAccount: UpstreamAccountDTO?
    @State private var showTools = false
    @State private var showPaywall = false
    @State private var showAccountPlaceholder = false
    @State private var revealText: String?
    @State private var masterPasswordInput = ""
    @State private var pendingRevealKeyId: UUID?
    @State private var pendingCopyKeyId: UUID?
    @State private var showMasterPrompt = false
    @State private var assignKeyId: UUID?
    /// 「按使用方」：弹出 sheet 为该使用方挑选已有密钥。
    @State private var assignToToolId: UUID?
    /// 分区「⋯」→ 调整该分区下密钥顺序。
    @State private var reorderKeysTarget: ReorderKeysTarget?
    /// 折叠的分区（账号 / 使用方 / 共享等）；不在集合内 = 展开。
    @State private var collapsedSectionIds: Set<String> = []
    @State private var pendingDeleteAccountId: UUID?
    @State private var pendingDeleteToolId: UUID?
    /// 分区「⋯」→ 编辑上游账号（平台 / 显示名）。
    @State private var editAccountId: UUID?
    /// 分区「⋯」→ 重命名使用方。
    @State private var editToolId: UUID?
    /// Mac 三栏：中间列表选中的密钥，右侧展示详情。
    @State private var selectedKeyId: UUID?
    /// Mac 三栏：回收站中栏选中项，右侧展示恢复 / 永久删除。
    @State private var selectedTrashItem: TrashSelection?
    /// 搜索（侧栏右上角放大镜；对齐系统「密码」App）。
    @State private var searchText = ""
    @State private var isSearchPresented = false

    /// Mac / Catalyst 用侧栏；iPhone（及 iPad）用底栏。
    private var usesSidebarNavigation: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    private var keySelection: Binding<UUID?> {
        $selectedKeyId
    }

    var body: some View {
        Group {
            if usesSidebarNavigation {
                sidebarShell
            } else {
                tabShell
            }
        }
        .task {
            await viewModel.onAppear()
            selectedTab = tab(for: viewModel.groupingMode)
        }
        .onChange(of: selectedTab) { _, tab in
            selectedKeyId = nil
            selectedTrashItem = nil
            Task { await applyTab(tab) }
        }
        .onChange(of: viewModel.allKeys.map(\.id)) { _, ids in
            if let selectedKeyId, !ids.contains(selectedKeyId) {
                self.selectedKeyId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            selectedTab = .settings
        }
        .modifier(VaultHomeAlertsModifier(
            viewModel: viewModel,
            showPaywall: $showPaywall,
            pendingDeleteAccountId: $pendingDeleteAccountId,
            pendingDeleteToolId: $pendingDeleteToolId,
            assignKeyId: $assignKeyId,
            revealText: $revealText
        ))
        .modifier(VaultHomeSheetsModifier(
            viewModel: viewModel,
            showAddAccount: $showAddAccount,
            showAddTool: $showAddTool,
            showAddKeyFor: $showAddKeyFor,
            pendingAddKeyAccount: $pendingAddKeyAccount,
            assignToToolId: $assignToToolId,
            reorderKeysTarget: $reorderKeysTarget,
            editAccountId: $editAccountId,
            editToolId: $editToolId,
            showTools: $showTools,
            showPaywall: $showPaywall,
            showAccountPlaceholder: $showAccountPlaceholder,
            showMasterPrompt: $showMasterPrompt,
            masterPasswordInput: $masterPasswordInput,
            pendingRevealKeyId: $pendingRevealKeyId,
            pendingCopyKeyId: $pendingCopyKeyId,
            revealText: $revealText
        ))
    }

    // MARK: - Shells

    /// iPhone / iPad：自定义底栏。系统 TabView 在 iPadOS 18+ 会顶到上方，不可靠。
    private var tabShell: some View {
        tabRootContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomTabBar
            }
    }

    @ViewBuilder
    private var tabRootContent: some View {
        switch selectedTab {
        case .byPlatform:
            keysStack(for: .byPlatform)
        case .byConsumer:
            keysStack(for: .byConsumer)
        case .trash:
            RecentlyDeletedView(
                vault: viewModel,
                showsDismissButton: false,
                onShowAccount: { showAccountPlaceholder = true }
            )
        case .settings:
            SettingsView(
                environment: viewModel.environment,
                showsDismissButton: false,
                onShowAccount: { showAccountPlaceholder = true }
            )
        }
    }

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach([VaultRootTab.byPlatform, .byConsumer, .trash, .settings], id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.titleKey)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.titleKey))
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    /// Mac：密钥 / 回收站 = 左导航 + 中列表 + 右详情；设置 = 左导航 + 内容（无空详情栏）。
    private var sidebarShell: some View {
        Group {
            if usesTwoColumnMacShell {
                NavigationSplitView {
                    macSidebar
                } detail: {
                    macContentColumn
                }
            } else {
                NavigationSplitView {
                    macSidebar
                } content: {
                    macContentColumn
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
                } detail: {
                    macDetailColumn
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: searchText) { _, _ in
            // 搜索结果变化时，若当前选中项已被滤掉则清空右侧详情。
            if let selectedKeyId,
               !displayedSections.flatMap(\.keys).contains(where: { $0.id == selectedKeyId }) {
                self.selectedKeyId = nil
            }
        }
    }

    private var usesTwoColumnMacShell: Bool {
        selectedTab == .settings
    }

    private var macSidebar: some View {
        List(selection: sidebarSelection) {
            Section {
                ForEach([VaultRootTab.byPlatform, .byConsumer, .trash, .settings], id: \.self) { tab in
                    Label(tab.titleKey, systemImage: tab.systemImage)
                        .tag(Optional(tab))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 240)
        .safeAreaInset(edge: .top, spacing: 0) {
            Button {
                showAccountPlaceholder = true
            } label: {
                Image(systemName: AppSymbols.Action.account)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("vault.sync.title"))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var macContentColumn: some View {
        switch selectedTab {
        case .byPlatform:
            macKeysColumn(mode: .byPlatform)
        case .byConsumer:
            macKeysColumn(mode: .byConsumer)
        case .trash:
            RecentlyDeletedView(
                vault: viewModel,
                showsDismissButton: false,
                selection: $selectedTrashItem
            )
        case .settings:
            SettingsView(
                environment: viewModel.environment,
                showsDismissButton: false
            )
        }
    }

    @ViewBuilder
    private var macDetailColumn: some View {
        switch selectedTab {
        case .byPlatform, .byConsumer:
            if let selectedKeyId {
                NavigationStack {
                    KeyDetailView(
                        keyId: selectedKeyId,
                        viewModel: viewModel,
                        allowDelete: selectedTab == .byPlatform,
                        unassignFromToolId: unassignToolIdIfNeeded(for: selectedKeyId),
                        splitPaneStyle: true,
                        onCopy: { id in Task { await beginCopy(id) } },
                        onReveal: { id in Task { await beginReveal(id) } },
                        onAssign: { id in beginAssign(id) },
                        onUnassign: { keyId, toolId in
                            Task { await viewModel.unassign(keyId: keyId, toolId: toolId) }
                        },
                        onDelete: { id in
                            Task {
                                await viewModel.deleteKey(id)
                                self.selectedKeyId = nil
                            }
                        }
                    )
                }
            } else {
                ContentUnavailableView(
                    "vault.detail.pick.title",
                    systemImage: AppSymbols.Key.outline,
                    description: Text("vault.detail.pick.detail")
                )
            }
        case .trash:
            if let selectedTrashItem {
                NavigationStack {
                    RecentlyDeletedDetailHost(
                        selection: selectedTrashItem,
                        vault: viewModel,
                        onCleared: { self.selectedTrashItem = nil }
                    )
                }
            } else {
                ContentUnavailableView(
                    "vault.trash.pick.title",
                    systemImage: AppSymbols.Tab.trash,
                    description: Text("vault.trash.pick.detail")
                )
            }
        case .settings:
            EmptyView()
        }
    }

    private func macKeysColumn(mode: GroupingMode) -> some View {
        NavigationStack {
            vaultList(selectionEnabled: true)
                .navigationTitle(mode == .byPlatform ? "vault.grouping.platform" : "vault.grouping.consumer")
                .modifier(VaultSearchableModifier(
                    searchText: $searchText,
                    isSearchPresented: $isSearchPresented
                ))
                .toolbar {
                    // 中栏右上角「+」：加账号 / 加工具（对齐系统「密码」中栏 +）。
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            switch mode {
                            case .byPlatform: showAddAccount = true
                            case .byConsumer: showAddTool = true
                            }
                        } label: {
                            Image(systemName: AppSymbols.Action.add)
                        }
                        .accessibilityLabel(
                            mode == .byPlatform
                                ? Text("vault.account.add")
                                : Text("vault.consumer.add")
                        )
                    }
                }
        }
        .id(mode)
    }

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !normalizedSearchQuery.isEmpty
    }

    /// 搜索过滤后的分区（密钥名 / 账号 / 平台显示名 / 使用方）。
    private var displayedSections: [KeyGroupSection] {
        filteredSections(from: viewModel.sections, query: normalizedSearchQuery)
    }

    private func filteredSections(from sections: [KeyGroupSection], query: String) -> [KeyGroupSection] {
        guard !query.isEmpty else { return sections }
        return sections.compactMap { section in
            let titleHit = sectionTitle(section).localizedCaseInsensitiveContains(query)
            let keys = section.keys.filter { keyMatchesSearch($0, query: query) }
            if titleHit {
                // 分区标题命中：仍优先只显示匹配密钥；若无匹配密钥则展示整区。
                return KeyGroupSection(kind: section.kind, keys: keys.isEmpty ? section.keys : keys)
            }
            guard !keys.isEmpty else { return nil }
            return KeyGroupSection(kind: section.kind, keys: keys)
        }
    }

    private func keyMatchesSearch(_ key: KeyRecordDTO, query: String) -> Bool {
        if key.displayName.localizedCaseInsensitiveContains(query) { return true }
        if let hint = key.maskedHint, hint.localizedCaseInsensitiveContains(query) { return true }
        if let account = viewModel.accounts.first(where: { $0.id == key.accountId }) {
            if account.displayName.localizedCaseInsensitiveContains(query) { return true }
            if account.platform.localizedCaseInsensitiveContains(query) { return true }
            if let custom = account.customPlatformName,
               custom.localizedCaseInsensitiveContains(query) {
                return true
            }
            if let preset = PresetCatalog.platform(id: account.platform),
               preset.displayName.localizedCaseInsensitiveContains(query) {
                return true
            }
        }
        for toolId in key.consumerToolIds {
            if let tool = viewModel.tools.first(where: { $0.id == toolId }),
               tool.name.localizedCaseInsensitiveContains(query) {
                return true
            }
        }
        return false
    }

    /// 若当前在「按使用方」且选中密钥属于某一工具分区，详情可取消指派。
    private func unassignToolIdIfNeeded(for keyId: UUID) -> UUID? {
        guard selectedTab == .byConsumer,
              let key = viewModel.allKeys.first(where: { $0.id == keyId }),
              key.consumerToolIds.count == 1 else {
            return nil
        }
        return key.consumerToolIds.first
    }

    private func keysStack(for mode: GroupingMode) -> some View {
        NavigationStack {
            vaultList(selectionEnabled: false)
                .navigationTitle("vault.title")
                .modifier(VaultSearchableModifier(
                    searchText: $searchText,
                    isSearchPresented: $isSearchPresented
                ))
                .toolbar {
                    // 左账号、右加号（`.navigation` / `.primaryAction` 在 iOS 与 macOS 均可用；
                    // `.topBarLeading` 仅 iOS，My Mac 编译会失败）。
                    ToolbarItem(placement: .navigation) {
                        Button {
                            showAccountPlaceholder = true
                        } label: {
                            Image(systemName: AppSymbols.Action.account)
                                .symbolRenderingMode(.hierarchical)
                                .font(.title3)
                        }
                        .accessibilityLabel(Text("vault.sync.title"))
                    }
                    // 搜索用标题下 searchable 抽屉；右上角只保留「+」（按平台 / 按使用方共用）。
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            switch viewModel.groupingMode {
                            case .byPlatform:
                                showAddAccount = true
                            case .byConsumer:
                                showAddTool = true
                            }
                        } label: {
                            Image(systemName: AppSymbols.Action.add)
                        }
                        .accessibilityLabel(
                            viewModel.groupingMode == .byPlatform
                                ? Text("vault.account.add")
                                : Text("vault.consumer.add")
                        )
                    }
                }
        }
        .id(mode)
    }

    @ViewBuilder
    private func vaultList(selectionEnabled: Bool) -> some View {
        List(selection: selectionEnabled ? keySelection : .constant(nil)) {
            // 列表内搜索框：Catalyst 上比只依赖系统 searchable 抽屉更可靠。
            if isSearchPresented || isSearching {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: AppSymbols.Action.search)
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "vault.search.prompt"), text: $searchText)
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
                }
            }

            if let quota = viewModel.remainingQuota, !isSearching {
                Section {
                    HStack {
                        Text("vault.quota.remaining \(quota)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("vault.paywall.open") { showPaywall = true }
                            .font(.footnote)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if displayedSections.isEmpty {
                Section {
                    if isSearching {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        emptyState
                    }
                }
            } else {
                ForEach(displayedSections) { section in
                    // 标题放进卡片首行，避免 List section header 被系统洗成淡灰。
                    Section {
                        sectionHeader(section)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
                            .selectionDisabled()
                        if !isSectionCollapsed(section) {
                            sectionBody(section, selectionEnabled: selectionEnabled)
                        }
                    }
                }
            }
        }
        // 对齐设置页：灰底 + 白卡片分区，账号/使用方之间留出缝隙。
        #if os(iOS)
        .listStyle(.insetGrouped)
        .listSectionSpacing(18)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(vaultGroupedBackground)
    }

    /// 与设置页同系的分组灰底，让各账号卡片被浅色缝隔开。
    private var vaultGroupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.gray.opacity(0.12)
        #endif
    }

    @ViewBuilder
    private var emptyState: some View {
        switch viewModel.groupingMode {
        case .byPlatform:
            VStack(alignment: .leading, spacing: 12) {
                Text("vault.empty.platform.title")
                    .font(.headline)
                Text("vault.empty.platform.detail")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("vault.empty.platform.cta") { showAddAccount = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
        case .byConsumer:
            VStack(alignment: .leading, spacing: 12) {
                Text("vault.empty.consumer.title")
                    .font(.headline)
                Text("vault.empty.consumer.detail")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("vault.empty.consumer.cta") { showAddTool = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
        }
    }

    private func tab(for mode: GroupingMode) -> VaultRootTab {
        switch mode {
        case .byPlatform: return .byPlatform
        case .byConsumer: return .byConsumer
        }
    }

    private func applyTab(_ tab: VaultRootTab) async {
        switch tab {
        case .byPlatform:
            // 只改当前会话列表视角，绝不写入 defaultGrouping（设置页才持久化）。
            if viewModel.groupingMode != .byPlatform {
                await viewModel.setGrouping(.byPlatform, persistAsDefault: false)
            }
        case .byConsumer:
            if viewModel.groupingMode != .byConsumer {
                await viewModel.setGrouping(.byConsumer, persistAsDefault: false)
            }
        case .trash, .settings:
            break
        }
    }

    private func sectionTitle(_ section: KeyGroupSection) -> String {
        switch section.kind {
        case .platform(_, let title), .consumer(_, let title):
            return title
        case .shared:
            return String(localized: "vault.group.shared")
        case .unassigned:
            return String(localized: "vault.group.unassigned")
        }
    }

    private func sectionSymbol(_ section: KeyGroupSection) -> String {
        switch section.kind {
        case .platform(let accountId, _):
            let platform = viewModel.accounts.first(where: { $0.id == accountId })?.platform
            return AppSymbols.platform(id: platform ?? "")
        case .consumer(let toolId, _):
            if let tool = viewModel.tools.first(where: { $0.id == toolId }) {
                return AppSymbols.tool(name: tool.name, storedSymbol: tool.iconSymbol)
            }
            return AppSymbols.Entity.tool
        case .shared:
            return AppSymbols.Key.shared
        case .unassigned:
            return AppSymbols.Key.unassigned
        }
    }

    private func sectionCollapseId(_ section: KeyGroupSection) -> String {
        switch section.kind {
        case .platform(let accountId, _):
            return "platform-\(accountId.uuidString)"
        case .consumer(let toolId, _):
            return "consumer-\(toolId.uuidString)"
        case .shared:
            return "shared"
        case .unassigned:
            return "unassigned"
        }
    }

    private func isSectionCollapsed(_ section: KeyGroupSection) -> Bool {
        // 搜索时强制展开，避免匹配项被折进折叠分区里「看起来像没搜到」。
        if isSearching { return false }
        return collapsedSectionIds.contains(sectionCollapseId(section))
    }

    private func toggleSectionCollapsed(_ section: KeyGroupSection) {
        let id = sectionCollapseId(section)
        if collapsedSectionIds.contains(id) {
            collapsedSectionIds.remove(id)
        } else {
            collapsedSectionIds.insert(id)
        }
    }

    /// 分区标题用接近正文的对比度（List `header:` 会被系统洗成浅灰）。
    private var vaultSectionTitleColor: Color {
        #if canImport(UIKit)
        Color(uiColor: .label)
        #elseif canImport(AppKit)
        Color(nsColor: .labelColor)
        #else
        Color.primary
        #endif
    }

    @ViewBuilder
    private func sectionHeader(_ section: KeyGroupSection) -> some View {
        let collapsed = isSectionCollapsed(section)
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    toggleSectionCollapsed(section)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: collapsed ? AppSymbols.Action.chevronRight : AppSymbols.Action.chevronDown)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(vaultSectionTitleColor.opacity(0.7))
                        .frame(width: 12, alignment: .center)
                    Image(systemName: sectionSymbol(section))
                        .font(.body.weight(.semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(vaultSectionTitleColor)
                        .accessibilityHidden(true)
                    Text(sectionTitle(section))
                        .font(.body.weight(.bold))
                        .foregroundStyle(vaultSectionTitleColor)
                        .lineLimit(1)
                    if collapsed {
                        Text("vault.section.keyCount \(section.keys.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(vaultSectionTitleColor.opacity(0.65))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .foregroundStyle(vaultSectionTitleColor)
            }
            .buttonStyle(.plain)
            .tint(vaultSectionTitleColor)
            .accessibilityLabel(Text(sectionTitle(section)))
            .accessibilityHint(
                Text(collapsed ? "vault.a11y.sectionExpand" : "vault.a11y.sectionCollapse")
            )

            // 「+」在分区标题行（密钥列表正上方），与中栏工具栏「+」分工：
            // 工具栏 = 加账号/工具；此处 = 在该分区下加密钥 / 指派。
            switch section.kind {
            case .platform(let accountId, _):
                Button {
                    beginAddKey(for: accountId)
                } label: {
                    Image(systemName: AppSymbols.Action.add)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(vaultSectionTitleColor.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("vault.key.add"))

                Menu {
                    Button("vault.account.edit", systemImage: AppSymbols.Action.edit) {
                        editAccountId = accountId
                    }
                    if section.keys.count >= 2 {
                        Button("vault.reorder.keys") {
                            reorderKeysTarget = ReorderKeysTarget(
                                title: sectionTitle(section),
                                keys: section.keys
                            )
                        }
                    }
                    Button("vault.account.delete", role: .destructive) {
                        pendingDeleteAccountId = accountId
                    }
                } label: {
                    Image(systemName: AppSymbols.Action.more)
                        .foregroundStyle(vaultSectionTitleColor.opacity(0.55))
                }
                .accessibilityLabel(Text("vault.a11y.sectionMenu"))
            case .consumer(let toolId, _):
                Button {
                    beginAssignExistingKey(to: toolId)
                } label: {
                    Image(systemName: AppSymbols.Action.add)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(vaultSectionTitleColor.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("vault.consumer.assignKey"))

                Menu {
                    Button("vault.consumer.edit", systemImage: AppSymbols.Action.edit) {
                        editToolId = toolId
                    }
                    if section.keys.count >= 2 {
                        Button("vault.reorder.keys") {
                            reorderKeysTarget = ReorderKeysTarget(
                                title: sectionTitle(section),
                                keys: section.keys
                            )
                        }
                    }
                    Button("vault.consumer.delete", role: .destructive) {
                        pendingDeleteToolId = toolId
                    }
                } label: {
                    Image(systemName: AppSymbols.Action.more)
                        .foregroundStyle(vaultSectionTitleColor.opacity(0.55))
                }
                .accessibilityLabel(Text("vault.a11y.sectionMenu"))
            case .shared, .unassigned:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sectionBody(_ section: KeyGroupSection, selectionEnabled: Bool) -> some View {
        switch section.kind {
        case .platform:
            ForEach(section.keys) { key in
                keyRow(key, selectionEnabled: selectionEnabled)
            }
        case .consumer(let toolId, _):
            ForEach(section.keys) { key in
                keyRow(
                    key,
                    unassignFromToolId: toolId,
                    allowDelete: false,
                    selectionEnabled: selectionEnabled
                )
            }
            consumerSectionFooter(toolId: toolId, hasAssignedKeys: !section.keys.isEmpty)
        case .shared, .unassigned:
            ForEach(section.keys) { key in
                keyRow(key, allowDelete: false, selectionEnabled: selectionEnabled)
            }
        }
    }

    @ViewBuilder
    private func consumerSectionFooter(toolId: UUID, hasAssignedKeys: Bool) -> some View {
        if !hasAssignedKeys {
            Text("vault.consumer.empty.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Button {
            beginAssignExistingKey(to: toolId)
        } label: {
            Label("vault.consumer.assignKey", systemImage: AppSymbols.Action.addInline)
        }
    }

    @ViewBuilder
    private func keyRow(
        _ key: KeyRecordDTO,
        unassignFromToolId: UUID? = nil,
        allowDelete: Bool = true,
        selectionEnabled: Bool = false
    ) -> some View {
        Group {
            if selectionEnabled {
                // Mac 中栏：点选 → 右侧详情，不再 push 新页。
                keyRowLabel(key)
                    .tag(key.id)
                    .contentShape(Rectangle())
            } else {
                HStack(alignment: .center, spacing: 12) {
                    NavigationLink {
                        KeyDetailView(
                            keyId: key.id,
                            viewModel: viewModel,
                            allowDelete: allowDelete,
                            unassignFromToolId: unassignFromToolId,
                            splitPaneStyle: false,
                            onCopy: { id in Task { await beginCopy(id) } },
                            onReveal: { id in Task { await beginReveal(id) } },
                            onAssign: { id in beginAssign(id) },
                            onUnassign: { keyId, toolId in
                                Task { await viewModel.unassign(keyId: keyId, toolId: toolId) }
                            },
                            onDelete: { id in
                                Task { await viewModel.deleteKey(id) }
                            }
                        )
                    } label: {
                        keyRowLabel(key)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await beginCopy(key.id) }
                    } label: {
                        Image(systemName: AppSymbols.Action.copy)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!key.secretAvailable)
                    .accessibilityLabel(Text("vault.copy"))
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if allowDelete {
                Button("vault.delete", role: .destructive) {
                    Task { await viewModel.deleteKey(key.id) }
                }
            }
        }
        .contextMenu {
            Button("vault.copy") { Task { await beginCopy(key.id) } }
                .disabled(!key.secretAvailable)
            Button("vault.reveal") { Task { await beginReveal(key.id) } }
                .disabled(!key.secretAvailable)
            if let toolId = unassignFromToolId {
                Button("vault.unassign", role: .destructive) {
                    Task { await viewModel.unassign(keyId: key.id, toolId: toolId) }
                }
            } else {
                Button("vault.assign") { beginAssign(key.id) }
            }
            if allowDelete {
                Button("vault.delete", role: .destructive) {
                    Task { await viewModel.deleteKey(key.id) }
                }
            }
        }
    }

    private func keyRowLabel(_ key: KeyRecordDTO) -> some View {
        HStack(spacing: 10) {
            Image(systemName: AppSymbols.Key.default)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(key.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    assignmentBadge(count: key.consumerToolIds.count)
                    Spacer(minLength: 0)
                }
                Text(maskLabel(key))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(maskAccessibility(key)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func maskLabel(_ key: KeyRecordDTO) -> String {
        if !key.secretAvailable { return String(localized: "vault.secret.missing") }
        if let hint = key.maskedHint { return "••••\(hint)" }
        return "••••"
    }

    private func maskAccessibility(_ key: KeyRecordDTO) -> String {
        if !key.secretAvailable { return String(localized: "vault.secret.missing") }
        if let hint = key.maskedHint {
            return String(localized: "vault.a11y.maskedHint \(hint)")
        }
        return String(localized: "vault.a11y.maskedHidden")
    }

    private func beginAssign(_ keyId: UUID) {
        if viewModel.tools.isEmpty {
            viewModel.errorMessage = String(localized: "vault.assign.noConsumer")
            return
        }
        assignKeyId = keyId
    }

    /// 免费档用尽时先弹配额，不打开添加表单。
    private func beginAddKey(for accountId: UUID) {
        if viewModel.remainingQuota == 0 {
            viewModel.showQuotaAlert = true
            return
        }
        showAddKeyFor = viewModel.accounts.first { $0.id == accountId }
    }

    /// 「按使用方」下：弹出 sheet 选择已有密钥。
    private func beginAssignExistingKey(to toolId: UUID) {
        if viewModel.allKeys.isEmpty {
            viewModel.errorMessage = String(localized: "vault.assign.noKey")
            assignToToolId = nil
            return
        }
        assignToToolId = toolId
    }

    private func assignmentBadge(count: Int) -> some View {
        Group {
            if count == 0 {
                Text("vault.assign.badge.none")
                    .foregroundStyle(.secondary)
            } else {
                Text("vault.assign.badge.count \(count)")
                    .foregroundStyle(.tint)
            }
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((count == 0 ? Color.secondary : Color.accentColor).opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel(
            count == 0
                ? Text("vault.assign.badge.none")
                : Text("vault.assign.badge.count \(count)")
        )
    }

    private func beginReveal(_ id: UUID) async {
        if let secret = await viewModel.revealReturning(keyId: id, masterPassword: nil) {
            revealText = secret
        } else if viewModel.needsMasterPassword {
            pendingRevealKeyId = id
            showMasterPrompt = true
        }
    }

    private func beginCopy(_ id: UUID) async {
        let ok = await viewModel.copyReturning(keyId: id, masterPassword: nil)
        if !ok && viewModel.needsMasterPassword {
            pendingCopyKeyId = id
            showMasterPrompt = true
        }
    }
}

// MARK: - Home modifiers

/// `navigationBarDrawer` 仅 iOS / Catalyst 可用；原生 macOS 用默认 placement。
private struct VaultSearchableModifier: ViewModifier {
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    var prompt: LocalizedStringKey = "vault.search.prompt"

    func body(content: Content) -> some View {
        #if os(iOS) || targetEnvironment(macCatalyst)
        content.searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(prompt)
        )
        #else
        content.searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            prompt: Text(prompt)
        )
        #endif
    }
}

private struct VaultHomeAlertsModifier: ViewModifier {
    @ObservedObject var viewModel: VaultHomeViewModel
    @Binding var showPaywall: Bool
    @Binding var pendingDeleteAccountId: UUID?
    @Binding var pendingDeleteToolId: UUID?
    @Binding var assignKeyId: UUID?
    @Binding var revealText: String?

    func body(content: Content) -> some View {
        content
            .alert("vault.error.title", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("gate.cancel", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(viewModel.toastMessage ?? "", isPresented: Binding(
                get: { viewModel.toastMessage != nil },
                set: { if !$0 { viewModel.toastMessage = nil } }
            )) {
                Button("vault.toast.dismiss", role: .cancel) { viewModel.toastMessage = nil }
            }
            .alert("vault.quota.exceeded.title", isPresented: $viewModel.showQuotaAlert) {
                Button("vault.paywall.open") { showPaywall = true }
                Button("gate.cancel", role: .cancel) {}
            } message: {
                Text("vault.quota.exceeded.body")
            }
            .confirmationDialog(
                "vault.account.delete.confirm",
                isPresented: Binding(
                    get: { pendingDeleteAccountId != nil },
                    set: { if !$0 { pendingDeleteAccountId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("vault.account.delete", role: .destructive) {
                    if let id = pendingDeleteAccountId {
                        pendingDeleteAccountId = nil
                        Task { await viewModel.deleteAccount(id) }
                    }
                }
                Button("gate.cancel", role: .cancel) { pendingDeleteAccountId = nil }
            }
            .confirmationDialog(
                "vault.consumer.delete.confirm",
                isPresented: Binding(
                    get: { pendingDeleteToolId != nil },
                    set: { if !$0 { pendingDeleteToolId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("vault.consumer.delete", role: .destructive) {
                    if let id = pendingDeleteToolId {
                        pendingDeleteToolId = nil
                        Task { await viewModel.deleteTool(id) }
                    }
                }
                Button("gate.cancel", role: .cancel) { pendingDeleteToolId = nil }
            }
            .confirmationDialog("vault.assign.title", isPresented: Binding(
                get: { assignKeyId != nil },
                set: { if !$0 { assignKeyId = nil } }
            )) {
                ForEach(viewModel.tools) { tool in
                    Button(tool.name) {
                        if let id = assignKeyId {
                            Task { await viewModel.assign(keyId: id, toolId: tool.id) }
                        }
                    }
                }
            }
            .alert("vault.reveal.title", isPresented: Binding(
                get: { revealText != nil },
                set: { if !$0 { revealText = nil } }
            )) {
                Button("gate.cancel", role: .cancel) { revealText = nil }
            } message: {
                Text(revealText ?? "")
            }
    }
}

private struct VaultHomeSheetsModifier: ViewModifier {
    @ObservedObject var viewModel: VaultHomeViewModel
    @Binding var showAddAccount: Bool
    @Binding var showAddTool: Bool
    @Binding var showAddKeyFor: UpstreamAccountDTO?
    @Binding var pendingAddKeyAccount: UpstreamAccountDTO?
    @Binding var assignToToolId: UUID?
    @Binding var reorderKeysTarget: ReorderKeysTarget?
    @Binding var editAccountId: UUID?
    @Binding var editToolId: UUID?
    @Binding var showTools: Bool
    @Binding var showPaywall: Bool
    @Binding var showAccountPlaceholder: Bool
    @Binding var showMasterPrompt: Bool
    @Binding var masterPasswordInput: String
    @Binding var pendingRevealKeyId: UUID?
    @Binding var pendingCopyKeyId: UUID?
    @Binding var revealText: String?

    private var assignToToolSheet: Binding<AssignToToolSheetTarget?> {
        Binding(
            get: {
                guard let id = assignToToolId else { return nil }
                let name = viewModel.tools.first { $0.id == id }?.name ?? ""
                return AssignToToolSheetTarget(id: id, name: name)
            },
            set: { assignToToolId = $0?.id }
        )
    }

    private var editAccountSheet: Binding<UpstreamAccountDTO?> {
        Binding(
            get: {
                guard let id = editAccountId else { return nil }
                return viewModel.accounts.first { $0.id == id }
            },
            set: { editAccountId = $0?.id }
        )
    }

    private var editToolSheet: Binding<ConsumerToolDTO?> {
        Binding(
            get: {
                guard let id = editToolId else { return nil }
                return viewModel.tools.first { $0.id == id }
            },
            set: { editToolId = $0?.id }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAddAccount, onDismiss: {
                if let account = pendingAddKeyAccount {
                    pendingAddKeyAccount = nil
                    if viewModel.remainingQuota == 0 {
                        viewModel.showQuotaAlert = true
                    } else {
                        showAddKeyFor = account
                    }
                }
            }) {
                AddAccountSheet(existingAccounts: viewModel.accounts) { platform, name, url in
                    if let account = await viewModel.createAccount(
                        platform: platform, name: name, customBaseURL: url
                    ) {
                        pendingAddKeyAccount = account
                    }
                }
            }
            .sheet(isPresented: $showAddTool) {
                AddConsumerToolSheet(existingTools: viewModel.tools) { name in
                    await viewModel.createTool(name: name)
                }
            }
            .sheet(item: $showAddKeyFor) { account in
                AddKeySheet(
                    accountName: account.displayName,
                    existingKeyCount: viewModel.allKeys.filter { $0.accountId == account.id }.count
                ) { name, secret, ack, notes in
                    await viewModel.createKey(
                        accountId: account.id,
                        name: name,
                        secret: secret,
                        ackDuplicate: ack,
                        notes: notes
                    )
                }
            }
            .sheet(item: editAccountSheet) { account in
                EditAccountSheet(account: account) { platform, name, url, notes in
                    await viewModel.updateAccount(
                        id: account.id,
                        platform: platform,
                        name: name,
                        customBaseURL: url,
                        notes: notes
                    )
                }
            }
            .sheet(item: editToolSheet) { tool in
                EditConsumerToolSheet(tool: tool) { name, notes in
                    await viewModel.renameTool(id: tool.id, name: name, notes: notes)
                }
            }
            .sheet(item: assignToToolSheet) { target in
                AssignExistingKeySheet(
                    toolName: target.name,
                    toolId: target.id,
                    viewModel: viewModel
                )
            }
            .sheet(item: $reorderKeysTarget) { target in
                ReorderKeysSheet(
                    title: target.title,
                    initialKeys: target.keys,
                    onSave: { orderedIds in
                        await viewModel.reorderKeys(orderedIds: orderedIds)
                    }
                )
            }
            .sheet(isPresented: $showTools) {
                ConsumerToolsView(environment: viewModel.environment)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(environment: viewModel.environment)
            }
            .sheet(isPresented: $showAccountPlaceholder) {
                AccountPlaceholderSheet {
                    await viewModel.requestSyncNow()
                }
            }
            .sheet(isPresented: $showMasterPrompt) {
                MasterPasswordPrompt(password: $masterPasswordInput) {
                    showMasterPrompt = false
                    let pwd = masterPasswordInput
                    masterPasswordInput = ""
                    if let id = pendingRevealKeyId {
                        pendingRevealKeyId = nil
                        if let secret = await viewModel.revealReturning(keyId: id, masterPassword: pwd) {
                            revealText = secret
                        }
                    } else if let id = pendingCopyKeyId {
                        pendingCopyKeyId = nil
                        await viewModel.copy(keyId: id, masterPassword: pwd)
                    }
                }
            }
    }
}

// MARK: - Sheets

private struct AssignToToolSheetTarget: Identifiable {
    let id: UUID
    let name: String
}

private struct ReorderKeysTarget: Identifiable {
    let id = UUID()
    let title: String
    let keys: [KeyRecordDTO]
}

private struct ReorderKeysSheet: View {
    let title: String
    let initialKeys: [KeyRecordDTO]
    /// 松手后立即持久化（系统重排常见做法）；不负责关闭 sheet。
    let onSave: ([UUID]) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keys: [KeyRecordDTO] = []
    @State private var persistTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                #if os(iOS) || targetEnvironment(macCatalyst)
                List {
                    Section {
                        Text("vault.reorder.keys.hint")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        ForEach(keys) { key in
                            reorderRow(key)
                        }
                        .onMove(perform: move)
                    }
                }
                .environment(\.editMode, .constant(.active))
                .navigationBarTitleDisplayMode(.inline)
                #else
                VStack(alignment: .leading, spacing: 0) {
                    Text("vault.reorder.keys.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    Divider()
                    MacReorderableKeyTable(keys: $keys) { orderedIds in
                        persist(orderedIds)
                    }
                }
                #endif
            }
            .navigationTitle(String(localized: "vault.reorder.keys.title \(title)"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.done") { dismiss() }
                }
            }
            .onAppear { keys = initialKeys }
            .onDisappear { persistTask?.cancel() }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 440, minHeight: 420, idealHeight: 480)
        #endif
    }

    private func reorderRow(_ key: KeyRecordDTO) -> some View {
        HStack(spacing: 12) {
            Image(systemName: AppSymbols.Key.default)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(key.displayName)
                if let hint = key.maskedHint {
                    Text(verbatim: "••••\(hint)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
    }

    private func move(from source: IndexSet, to destination: Int) {
        keys.move(fromOffsets: source, toOffset: destination)
        persist(keys.map(\.id))
    }

    private func persist(_ orderedIds: [UUID]) {
        persistTask?.cancel()
        persistTask = Task {
            await onSave(orderedIds)
        }
    }
}

private struct AssignExistingKeySheet: View {
    let toolName: String
    let toolId: UUID
    @ObservedObject var viewModel: VaultHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter: AssignPickerFilter = .allowShared
    @State private var searchText = ""

    private var candidates: [KeyRecordDTO] {
        let base = viewModel.keysAssignable(to: toolId, filter: filter)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { key in
            if key.displayName.localizedCaseInsensitiveContains(query) { return true }
            let account = viewModel.accounts.first { $0.id == key.accountId }?.displayName ?? ""
            return account.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(filter == .unassignedOnly
                         ? "vault.assign.sheet.filter.unassignedOnly.hint"
                         : "vault.assign.sheet.filter.allowShared.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if candidates.isEmpty {
                    Section {
                        Text(emptyMessage)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(candidates) { key in
                            Button {
                                Task {
                                    await viewModel.assign(keyId: key.id, toolId: toolId)
                                    dismiss()
                                }
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(key.displayName)
                                                .foregroundStyle(.primary)
                                            if key.consumerToolIds.count >= 1 {
                                                Text("vault.assign.badge.count \(key.consumerToolIds.count)")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.tint)
                                            }
                                        }
                                        Text(accountName(for: key))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: AppSymbols.Action.addFilled)
                                        .foregroundStyle(Color.accentColor)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "vault.assign.sheet.title \(toolName)"))
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: Text("vault.assign.sheet.search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
            .task {
                if let prefs = try? await viewModel.environment.preferences.load() {
                    filter = prefs.assignPickerFilter
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 520)
        #endif
    }

    private var emptyMessage: LocalizedStringKey {
        if filter == .unassignedOnly {
            return "vault.assign.sheet.empty.unassignedOnly"
        }
        return "vault.assign.sheet.empty.allowShared"
    }

    private func accountName(for key: KeyRecordDTO) -> String {
        viewModel.accounts.first { $0.id == key.accountId }?.displayName ?? "—"
    }
}

private struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingAccounts: [UpstreamAccountDTO]
    @State private var platform = "openai"
    @State private var name = ""
    /// 上次自动填入的建议名；用户改写后切换平台时不再覆盖。
    @State private var lastSuggested = ""
    @State private var customURL = ""
    let onSave: (String, String, String?) async -> Void

    private var selectedPlatformLabel: String {
        PresetCatalog.platform(id: platform)?.displayName
            ?? String(localized: "vault.custom.platform")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("vault.account.platform", selection: $platform) {
                    ForEach(PresetCatalog.platforms, id: \.id) { p in
                        Label(p.displayName, systemImage: p.iconSymbol).tag(p.id)
                    }
                    Label("vault.custom.platform", systemImage: AppSymbols.platform(id: PresetCatalog.customPlatformID))
                        .tag(PresetCatalog.customPlatformID)
                }
                .pickerStyle(.menu)
                LabeledContent("vault.account.platform.selected") {
                    Text(selectedPlatformLabel)
                        .foregroundStyle(.secondary)
                }
                TextField("vault.account.name", text: $name)
                Text("vault.account.name.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if platform == PresetCatalog.customPlatformID {
                    TextField("vault.account.baseURL", text: $customURL)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("vault.account.add")
            .onAppear { applySuggestion(for: platform, force: true) }
            .onChange(of: platform) { _, newValue in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || name == lastSuggested {
                    applySuggestion(for: newValue, force: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            await onSave(
                                platform,
                                name,
                                platform == PresetCatalog.customPlatformID ? customURL : nil
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func applySuggestion(for platformID: String, force: Bool) {
        let suggested = Self.suggestedDisplayName(
            platformID: platformID,
            existing: existingAccounts
        )
        if force || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = suggested
            lastSuggested = suggested
        }
    }

    /// 按**同一上游平台**已有账号数递增：DeepSeek 已有 2 个 →「DeepSeek 账号 3」。
    static func suggestedDisplayName(
        platformID: String,
        existing: [UpstreamAccountDTO]
    ) -> String {
        let label = PresetCatalog.platform(id: platformID)?.displayName
            ?? String(localized: "vault.custom.platform")
        let count = existing.filter { $0.platform == platformID }.count
        return String(localized: "vault.account.defaultName \(label) \(count + 1)")
    }
}

private struct AddConsumerToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingTools: [ConsumerToolDTO]
    /// 空字符串 = 完全自定义；否则为预置显示名（如 VS Code）。
    @State private var baseName = "VS Code"
    @State private var deviceLabel = ""
    @State private var lastSuggestedDevice = ""
    let onSave: (String) async -> Void

    private var customBaseTag: String { "" }

    private var resolvedDisplayName: String {
        let device = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return device.isEmpty
                ? String(localized: "vault.consumer.defaultName \(customInstanceCount + 1)")
                : device
        }
        if device.isEmpty { return base }
        return String(localized: "vault.consumer.compoundName \(base) \(device)")
    }

    private var customInstanceCount: Int {
        existingTools.filter { !$0.isPreset }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("vault.consumer.base", selection: $baseName) {
                    ForEach(PresetCatalog.consumerTools, id: \.name) { tool in
                        Label(
                            tool.name,
                            systemImage: AppSymbols.tool(name: tool.name, storedSymbol: tool.iconSymbol)
                        )
                            .tag(tool.name)
                    }
                    Label("vault.consumer.base.custom", systemImage: AppSymbols.Entity.toolCustom)
                        .tag(customBaseTag)
                }
                TextField(
                    baseName.isEmpty ? "vault.consumer.name.optional" : "vault.consumer.device",
                    text: $deviceLabel
                )
                Text("vault.consumer.name.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("vault.consumer.preview") {
                    Text(resolvedDisplayName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("vault.consumer.add")
            .onAppear { applyDeviceSuggestion(force: true) }
            .onChange(of: baseName) { _, _ in
                let trimmed = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || deviceLabel == lastSuggestedDevice {
                    applyDeviceSuggestion(force: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            await onSave(resolvedDisplayName)
                            dismiss()
                        }
                    }
                    .disabled(resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    /// 同一基名下递增：预置「VS Code」之外，第一台设备默认「电脑 1」。
    private func applyDeviceSuggestion(force: Bool) {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            if force {
                deviceLabel = ""
                lastSuggestedDevice = ""
            }
            return
        }
        let deviceSpecific = existingTools.filter {
            $0.name.hasPrefix("\(base) · ") || $0.name.hasPrefix("\(base) - ")
        }.count
        let suggested = String(localized: "vault.consumer.deviceDefault \(deviceSpecific + 1)")
        if force || deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deviceLabel = suggested
            lastSuggestedDevice = suggested
        }
    }
}

private struct EditAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let account: UpstreamAccountDTO
    let onSave: (_ platform: String, _ name: String, _ customBaseURL: String?, _ notes: String?) async -> Bool

    @State private var platform: String
    @State private var name: String
    @State private var customURL: String
    @State private var notes: String
    @State private var isSaving = false

    init(
        account: UpstreamAccountDTO,
        onSave: @escaping (_ platform: String, _ name: String, _ customBaseURL: String?, _ notes: String?) async -> Bool
    ) {
        self.account = account
        self.onSave = onSave
        _platform = State(initialValue: account.platform)
        _name = State(initialValue: account.displayName)
        _customURL = State(initialValue: account.customBaseURL ?? "")
        _notes = State(initialValue: account.notes ?? "")
    }

    private var selectedPlatformLabel: String {
        PresetCatalog.platform(id: platform)?.displayName
            ?? String(localized: "vault.custom.platform")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("vault.account.platform", selection: $platform) {
                        ForEach(PresetCatalog.platforms, id: \.id) { p in
                            Label(p.displayName, systemImage: p.iconSymbol).tag(p.id)
                        }
                        Label(
                            "vault.custom.platform",
                            systemImage: AppSymbols.platform(id: PresetCatalog.customPlatformID)
                        )
                        .tag(PresetCatalog.customPlatformID)
                    }
                    .pickerStyle(.menu)
                    LabeledContent("vault.account.platform.selected") {
                        Text(selectedPlatformLabel)
                            .foregroundStyle(.secondary)
                    }
                    TextField("vault.account.name", text: $name)
                    if platform == PresetCatalog.customPlatformID {
                        TextField("vault.account.baseURL", text: $customURL)
                            .autocorrectionDisabled()
                    }
                    Text("vault.account.edit.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("vault.account.notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                    Text("vault.account.notes.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("vault.account.edit")
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            let ok = await onSave(
                                platform,
                                name,
                                platform == PresetCatalog.customPlatformID ? customURL : nil,
                                notes
                            )
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 520)
        #endif
    }
}

private struct EditConsumerToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tool: ConsumerToolDTO
    let onSave: (_ name: String, _ notes: String?) async -> Bool

    @State private var name: String
    @State private var notes: String
    @State private var isSaving = false

    init(tool: ConsumerToolDTO, onSave: @escaping (_ name: String, _ notes: String?) async -> Bool) {
        self.tool = tool
        self.onSave = onSave
        _name = State(initialValue: tool.name)
        _notes = State(initialValue: tool.notes ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("vault.consumer.name", text: $name)
                    Text("vault.consumer.edit.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("vault.consumer.notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                    Text("vault.consumer.notes.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("vault.consumer.edit")
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            if await onSave(name, notes) { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 320, idealHeight: 380)
        #endif
    }
}

private struct AddKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let accountName: String
    let existingKeyCount: Int
    let onSave: (String, String, Bool, String?) async -> Bool
    @State private var name = ""
    @State private var secret = ""
    @State private var notes = ""
    @State private var ackDuplicate = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("vault.key.account") {
                    Text(accountName).foregroundStyle(.secondary)
                }
                TextField("vault.key.name.optional", text: $name)
                Text("vault.key.name.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SecureField("vault.key.secret", text: $secret)
                    .autocorrectionDisabled()
                Toggle("vault.key.ackDuplicate", isOn: $ackDuplicate)
                TextField("vault.key.notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
                Text("vault.key.notes.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("vault.key.add")
            .onAppear {
                if name.isEmpty {
                    name = String(localized: "vault.key.defaultName \(existingKeyCount + 1)")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                            let ok = await onSave(
                                name,
                                secret,
                                ackDuplicate,
                                trimmedNotes.isEmpty ? nil : trimmedNotes
                            )
                            if ok {
                                secret = ""
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct MasterPasswordPrompt: View {
    @Binding var password: String
    let onConfirm: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SecureField("vault.masterPassword", text: $password)
                Text("vault.masterPassword.disclosure")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("vault.masterPassword.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.confirm") { Task { await onConfirm() } }
                }
            }
        }
    }
}

private struct AccountPlaceholderSheet: View {
    let onSyncNow: () async -> SyncNowOutcome
    @Environment(\.dismiss) private var dismiss
    @State private var isSyncing = false
    @State private var syncFeedback: String?
    @State private var syncFeedbackIsError = false

    /// 系统是否已登录可用 iCloud 的粗略信号（不等于钥匙串开关本身）。
    private var isICloudAccountPresent: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

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
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusHero
                    syncNowCard
                    howCard
                    settingsCard
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(pageBackground)
            .navigationTitle("vault.sync.title")
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.done") { dismiss() }
                }
            }
            .disabled(isSyncing)
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 560)
        #endif
    }

    private var statusHero: some View {
        VStack(spacing: 14) {
            Image(systemName: AppSymbols.Sync.iCloud)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .fill(isICloudAccountPresent ? Color.accentColor : Color.secondary)
                )
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("vault.sync.section.account")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(isICloudAccountPresent ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(
                        isICloudAccountPresent
                            ? String(localized: "vault.sync.icloud.status.signedIn")
                            : String(localized: "vault.sync.icloud.status.signedOut")
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isICloudAccountPresent ? Color.primary : Color.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text(
                        "vault.sync.icloud.status.combined \(String(localized: "vault.sync.icloud.status")) \(isICloudAccountPresent ? String(localized: "vault.sync.icloud.status.signedIn") : String(localized: "vault.sync.icloud.status.signedOut"))"
                    )
                )
            }

            Text("vault.sync.icloud.status.footnote")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var syncNowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await performSyncNow() }
            } label: {
                HStack(spacing: 8) {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: AppSymbols.Sync.refresh)
                    }
                    Text(isSyncing ? "vault.sync.now.inProgress" : "vault.sync.now")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing || !isICloudAccountPresent)

            if let syncFeedback {
                Text(syncFeedback)
                    .font(.caption)
                    .foregroundStyle(syncFeedbackIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(syncFeedback))
            } else {
                Text("vault.sync.now.footnote")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private var howCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("vault.sync.section.how", systemImage: AppSymbols.Sync.lockedCloud)
                .font(.headline)
            Text("vault.sync.how.body")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                openSystemSettingsForAppleAccount()
            } label: {
                Label("vault.sync.openSystemSettings", systemImage: AppSymbols.Sync.openSystemSettings)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)

            Text("vault.sync.openSystemSettings.footnote")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
    }

    private func performSyncNow() async {
        syncFeedback = nil
        isSyncing = true
        defer { isSyncing = false }
        let outcome = await onSyncNow()
        switch outcome {
        case .success:
            syncFeedbackIsError = false
            syncFeedback = String(localized: "vault.sync.now.success")
        case .unavailable:
            syncFeedbackIsError = true
            syncFeedback = String(localized: "vault.sync.now.unavailable")
        case .failed(let message):
            syncFeedbackIsError = true
            syncFeedback = message
        }
    }

    private func openSystemSettingsForAppleAccount() {
        #if targetEnvironment(macCatalyst)
        let candidates = [
            "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane",
            "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings",
            UIApplication.openSettingsURLString
        ]
        for raw in candidates {
            if let url = URL(string: raw) {
                UIApplication.shared.open(url)
                return
            }
        }
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        let candidates = [
            "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane",
            "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"
        ]
        for raw in candidates {
            if let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        #endif
    }
}
/// Mac 回收站中栏选中项（密钥 / 账号 / 使用方）。
private enum TrashSelection: Hashable {
    case key(UUID)
    case account(UUID)
    case tool(UUID)
}

private struct RecentlyDeletedView: View {
    @ObservedObject var vault: VaultHomeViewModel
    var showsDismissButton: Bool = true
    /// 左上角账号头像（与密钥列表页同一入口）。
    var onShowAccount: (() -> Void)? = nil
    /// 非 nil = Mac 三栏中栏：行可点选，恢复 / 永久删除放到右侧详情。
    var selection: Binding<TrashSelection?>? = nil
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

    private var usesSplitSelection: Bool { selection != nil }

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

    var body: some View {
        NavigationStack {
            Group {
                if let selection {
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
            // Tab 内用大标题：先见「回收站」，其下再是搜索抽屉（勿用 inline，否则像只有搜索栏）。
            .navigationBarTitleDisplayMode(showsDismissButton ? .inline : .large)
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
                prompt: "vault.trash.search.prompt"
            ))
            .toolbar {
                if let onShowAccount {
                    ToolbarItem(placement: .navigation) {
                        Button(action: onShowAccount) {
                            Image(systemName: AppSymbols.Action.account)
                                .symbolRenderingMode(.hierarchical)
                                .font(.title3)
                        }
                        .accessibilityLabel(Text("vault.sync.title"))
                    }
                }
                if showsDismissButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("vault.recentlyDeleted.done") { dismiss() }
                    }
                }
            }
            .task { await reload() }
            .onAppear { Task { await reload() } }
            .onChange(of: searchText) { _, _ in
                pruneSelectionIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .trashBundleDidChange)) { _ in
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
                Text("vault.recentlyDeleted.empty")
                    .font(.headline)
                Text("vault.recentlyDeleted.empty.detail")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("vault.recentlyDeleted.empty.how")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
            Section {
                Text("vault.recentlyDeleted.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                            onPermanent: { await vault.permanentlyDeleteKey(key.id) }
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
                            onPermanent: { await vault.permanentlyDeleteAccount(account.id) }
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
                            onPermanent: { await vault.permanentlyDeleteTool(tool.id) }
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
        Group {
            if usesSplitSelection {
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
            pruneSelectionIfNeeded()
        } catch {
            loadError = error.localizedDescription
            keys = []
            accounts = []
            tools = []
            selection?.wrappedValue = nil
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
}

/// Mac 回收站右侧详情：展示选中项元数据与恢复 / 永久删除。
private struct RecentlyDeletedDetailHost: View {
    let selection: TrashSelection
    @ObservedObject var vault: VaultHomeViewModel
    var onCleared: () -> Void

    @State private var keys: [KeyRecordDTO] = []
    @State private var accounts: [UpstreamAccountDTO] = []
    @State private var tools: [ConsumerToolDTO] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?

    var body: some View {
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
                RecentlyDeletedDetailView(
                    model: model,
                    onRestore: { await runAction(model.restore) },
                    onPermanent: { await runAction(model.permanent) }
                )
            } else {
                ContentUnavailableView(
                    "vault.trash.missing.title",
                    systemImage: AppSymbols.Tab.trash,
                    description: Text("vault.trash.missing.detail")
                )
                .onAppear { onCleared() }
            }
        }
        .task(id: selection) { await reload() }
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

private extension Notification.Name {
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
    let onRestore: () async -> Void
    let onPermanent: () async -> Void

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
            VStack(spacing: 16) {
                infoCard
                actionsCard
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(pageBackground)
        .navigationTitle(model.title)
        #if os(iOS) || targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("vault.restore") {
                    Task { await onRestore() }
                }
                Button("vault.delete.forever", role: .destructive) {
                    Task { await onPermanent() }
                }
            }
        }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    Text(model.kindTitleKey)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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

    private var actionsCard: some View {
        VStack(spacing: 0) {
            Button {
                Task { await onRestore() }
            } label: {
                Text("vault.restore")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Divider()

            Button("vault.delete.forever", role: .destructive) {
                Task { await onPermanent() }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
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

struct ConsumerToolsView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var tools: [ConsumerToolDTO] = []
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(tools) { tool in
                    HStack {
                        Label(
                            tool.name,
                            systemImage: AppSymbols.tool(name: tool.name, storedSymbol: tool.iconSymbol)
                        )
                        Spacer()
                        Toggle("vault.tools.hidden", isOn: Binding(
                            get: { tool.isHidden },
                            set: { hidden in
                                Task {
                                    var patch = ConsumerToolPatch()
                                    patch.isHidden = hidden
                                    try? await environment.consumerTools.updateTool(id: tool.id, patch: patch)
                                    await reload()
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions {
                        Button("vault.delete", role: .destructive) {
                            Task {
                                try? await environment.consumerTools.deleteTool(id: tool.id)
                                await reload()
                            }
                        }
                    }
                    .contextMenu {
                        Button("vault.delete", role: .destructive) {
                            Task {
                                try? await environment.consumerTools.deleteTool(id: tool.id)
                                await reload()
                            }
                        }
                    }
                }
                Section {
                    TextField("vault.tools.new", text: $newName)
                    Button("vault.tools.add") {
                        Task {
                            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let icon = PresetCatalog.toolIconForNewBase(trimmed)
                            _ = try? await environment.consumerTools.createTool(
                                ConsumerToolDraft(name: trimmed, iconSymbol: icon)
                            )
                            newName = ""
                            await reload()
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("vault.tools.manage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        tools = (try? await environment.consumerTools.tools(includeHidden: true)) ?? []
    }
}
