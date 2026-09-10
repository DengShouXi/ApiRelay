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

    /// 搜索结果里点账号 / 使用方后，清关键词并滚到对应分区。
    fileprivate enum SearchLocateTarget: Equatable {
        case account(UUID)
        case tool(UUID)
    }

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
    @State private var showAddAccount = false
    @State private var showAddTool = false
    @State private var showAddKeyFor: UpstreamAccountDTO?
    @State private var showPaywall = false
    @State private var showAccountPlaceholder = false
    @State private var revealedSecret: String?
    @State private var masterPasswordInput = ""
    @State private var pendingRevealKeyId: UUID?
    @State private var pendingCopyKeyId: UUID?
    @State private var showMasterPrompt = false
    @State private var assignKeyId: UUID?
    /// 「按使用方」：弹出 sheet 为该使用方挑选已有密钥。
    @State private var assignToToolId: UUID?
    /// 分区「⋯」→ 调整该分区下密钥顺序。
    @State private var reorderKeysTarget: ReorderKeysTarget?
    /// 排序菜单「调整顺序」→ 调整账号 / 使用方分区顺序。
    @State private var reorderSectionsTarget: ReorderSectionsTarget?
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
    /// 回收站选择模式（三端同一套；不改平时的单选 List）。
    @State private var trashIsSelecting = false
    @State private var trashCheckedItems: Set<TrashSelection> = []
    @State private var trashVisibleItems: Set<TrashSelection> = []
    /// Mac 右栏占位：`false` 表示回收站为空（不要显示「选择一项」）。
    @State private var trashHasItems: Bool?
    /// 整库搜索（密钥 / 上游账号 / 使用方）。Mac 挂在右栏工具栏；iPhone 用系统搜索抽屉。
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var pendingSearchLocate: VaultRootTab.SearchLocateTarget?
    /// Files / 访达打开 `.apirelaybackup` 时带进来的拷贝，不是密钥明文。
    @State private var incomingBackup: IncomingBackupPayload?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var keyDetailIsEditing = false
    @State private var keyDetailChromeCommand: KeyDetailChromeCommand = .none
    /// 本窗口记住的 Mac 栏宽；只存界面层，不进 iCloud。
    @SceneStorage("vault.macSidebarWidth") private var storedSidebarWidth = 200.0
    @SceneStorage("vault.macContentWidth") private var storedContentWidth = 340.0
    @Environment(\.colorScheme) private var colorScheme
    /// 侧栏身份块下方那一行；未取到状态时显示「账号」。
    @State private var sidebarCloudAccount: CloudAccountState = .unknown

    private var macSidebarWidth: Binding<CGFloat> {
        Binding(
            get: { CGFloat(storedSidebarWidth) },
            set: { storedSidebarWidth = Double($0) }
        )
    }

    private var macContentWidth: Binding<CGFloat> {
        Binding(
            get: { CGFloat(storedContentWidth) },
            set: { storedContentWidth = Double($0) }
        )
    }

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

    private var trashActionSelection: TrashBatchSelection {
        trashBatchSelection(from: trashCheckedItems.intersection(trashVisibleItems))
    }

    private func resetTrashSelectMode() {
        trashIsSelecting = false
        trashCheckedItems = []
        trashVisibleItems = []
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
            resetTrashSelectMode()
            revealedSecret = nil
            keyDetailIsEditing = false
            keyDetailChromeCommand = .none
            if tab != .trash {
                trashHasItems = nil
            }
            Task { await applyTab(tab) }
        }
        .onChange(of: viewModel.allKeys.map(\.id)) { _, ids in
            if let selectedKeyId, !ids.contains(selectedKeyId) {
                self.selectedKeyId = nil
                revealedSecret = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            guard !viewModel.environment.appPrivacy.session.isSessionLocked else { return }
            selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .newKey)) { _ in
            beginNewKeyFromMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDataDidErase)) { _ in
            selectedKeyId = nil
            selectedTrashItem = nil
            resetTrashSelectMode()
            revealedSecret = nil
            trashHasItems = nil
            searchText = ""
            Task { await viewModel.handleUserDataDidErase() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidImportBackup)) { _ in
            selectedKeyId = nil
            selectedTrashItem = nil
            resetTrashSelectMode()
            Task { await viewModel.handleUserDataDidErase() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiRelayCloudMetadataDidImport)) { _ in
            Task { await viewModel.refresh() }
        }
        .onOpenURL { url in
            handleIncomingBackupURL(url)
        }
        .sheet(item: $incomingBackup) { payload in
            NavigationStack {
                BackupImportView(
                    environment: viewModel.environment,
                    incomingData: payload.data
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("gate.cancel") { incomingBackup = nil }
                    }
                }
            }
            .settingsTaskSheet()
        }
        .modifier(VaultHomeAlertsModifier(
            viewModel: viewModel,
            showPaywall: $showPaywall,
            pendingDeleteAccountId: $pendingDeleteAccountId,
            pendingDeleteToolId: $pendingDeleteToolId
        ))
        .modifier(VaultHomeSheetsModifier(
            viewModel: viewModel,
            showAddAccount: $showAddAccount,
            showAddTool: $showAddTool,
            showAddKeyFor: $showAddKeyFor,
            assignKeyId: $assignKeyId,
            assignToToolId: $assignToToolId,
            reorderKeysTarget: $reorderKeysTarget,
            reorderSectionsTarget: $reorderSectionsTarget,
            editAccountId: $editAccountId,
            editToolId: $editToolId,
            showPaywall: $showPaywall,
            showAccountPlaceholder: $showAccountPlaceholder,
            showMasterPrompt: $showMasterPrompt,
            masterPasswordInput: $masterPasswordInput,
            pendingRevealKeyId: $pendingRevealKeyId,
            pendingCopyKeyId: $pendingCopyKeyId,
            revealedSecret: $revealedSecret
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
                onShowAccount: { showAccountPlaceholder = true },
                isSelecting: $trashIsSelecting,
                checkedItems: $trashCheckedItems,
                visibleItems: $trashVisibleItems
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

    /// Mac：三列通顶，各栏自己的顶栏。不用 NavigationSplitView，避免中栏和右栏被收成一条系统总顶栏。
    /// 分界线是可拖分割条（不是装饰 Divider）。
    private var sidebarShell: some View {
        GeometryReader { geo in
            let fitted = MacColumnLayout.fitted(
                storedSidebar: CGFloat(storedSidebarWidth),
                storedContent: CGFloat(storedContentWidth),
                containerWidth: geo.size.width,
                twoColumn: usesTwoColumnMacShell
            )
            HStack(spacing: 0) {
                macSidebar
                    .frame(width: fitted.sidebar)
                    .frame(maxHeight: .infinity)
                MacColumnSplitter(
                    displayedWidth: fitted.sidebar,
                    width: macSidebarWidth,
                    range: MacColumnLayout.sidebarRange,
                    defaultWidth: MacColumnLayout.sidebarDefault,
                    additionalMax: MacColumnLayout.maxSidebar(
                        containerWidth: geo.size.width,
                        contentWidth: fitted.content,
                        twoColumn: usesTwoColumnMacShell
                    )
                )
                if usesTwoColumnMacShell {
                    macContentColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    macContentColumn
                        .frame(width: fitted.content)
                        .frame(maxHeight: .infinity)
                    MacColumnSplitter(
                        displayedWidth: fitted.content,
                        width: macContentWidth,
                        range: MacColumnLayout.contentRange,
                        defaultWidth: MacColumnLayout.contentDefault,
                        additionalMax: MacColumnLayout.maxContent(
                            containerWidth: geo.size.width,
                            sidebarWidth: fitted.sidebar
                        )
                    )
                    macDetailColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .onChange(of: searchText) { _, _ in
            if let selectedKeyId, !visibleKeyIds.contains(selectedKeyId) {
                self.selectedKeyId = nil
                revealedSecret = nil
            }
        }
        .onChange(of: selectedKeyId) { _, _ in
            revealedSecret = nil
            keyDetailIsEditing = false
            keyDetailChromeCommand = .none
        }
        .background { keySelectionShortcuts }
    }

    private var usesTwoColumnMacShell: Bool {
        selectedTab == .settings
    }

    /// 钱迹式侧栏：头像钉在顶；已登录到「按平台」空三行（84pt），四项之间空一行（28pt）。
    private var macSidebar: some View {
        VStack(spacing: 0) {
            macSidebarIdentity
            VStack(spacing: 28) {
                macSidebarRow(.byPlatform)
                macSidebarRow(.byConsumer)
                macSidebarRow(.trash)
                macSidebarRow(.settings)
            }
            .padding(.top, 84)
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sidebarColumnBackground)
        .task { await refreshSidebarCloudAccount() }
        .onChange(of: showAccountPlaceholder) { _, presented in
            guard !presented else { return }
            Task { await refreshSidebarCloudAccount() }
        }
    }

    private var macSidebarIdentity: some View {
        Button {
            showAccountPlaceholder = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: AppSymbols.Action.account)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(sidebarAccountCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("vault.sync.title"))
        .accessibilityValue(Text(sidebarAccountCaption))
    }

    private var sidebarAccountCaption: String {
        switch sidebarCloudAccount {
        case .signedIn:
            String(localized: "vault.sync.icloud.status.signedIn")
        case .signedOut:
            String(localized: "vault.sync.icloud.status.signedOut")
        case .restricted, .temporarilyUnavailable, .unknown:
            String(localized: "vault.sidebar.account")
        }
    }

    private func refreshSidebarCloudAccount() async {
        sidebarCloudAccount = await viewModel.environment.cloudSync.snapshot().account
    }

    private func macSidebarRow(_ tab: VaultRootTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .frame(width: 20, alignment: .center)
                Text(tab.titleKey)
                    .font(selected ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.titleKey))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var sidebarColumnBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color.gray.opacity(0.12)
        #endif
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
                selection: $selectedTrashItem,
                reportsHasItems: $trashHasItems,
                isSelecting: $trashIsSelecting,
                checkedItems: $trashCheckedItems,
                visibleItems: $trashVisibleItems
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
            VStack(spacing: 0) {
                macDetailChromeBar
                NavigationStack {
                    macKeysDetailRoot
                        #if os(iOS) || targetEnvironment(macCatalyst)
                        .toolbar(.hidden, for: .navigationBar)
                        #endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .trash:
            if trashIsSelecting {
                RecentlyDeletedBatchDetailView(
                    selection: trashActionSelection,
                    vault: viewModel,
                    onFinished: { success in
                        if success {
                            resetTrashSelectMode()
                            selectedTrashItem = nil
                        }
                    }
                )
            } else if let selectedTrashItem {
                RecentlyDeletedDetailHost(
                    selection: selectedTrashItem,
                    vault: viewModel,
                    onCleared: { self.selectedTrashItem = nil }
                )
            } else if trashHasItems == false {
                macTrashPlaceholder(
                    title: "vault.recentlyDeleted.empty",
                    description: nil
                )
            } else {
                macTrashPlaceholder(
                    title: "vault.trash.pick.title",
                    description: "vault.trash.pick.detail"
                )
            }
        case .settings:
            EmptyView()
        }
    }

    private func macKeysColumn(mode: GroupingMode) -> some View {
        VStack(spacing: 0) {
            macContentChromeBar(mode: mode)
            NavigationStack {
                vaultList(selectionEnabled: true)
                    #if os(iOS) || targetEnvironment(macCatalyst)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id(mode)
    }

    /// 中栏顶栏：标题左对齐，排序与加号在右。
    private func macContentChromeBar(mode: GroupingMode) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(mode == .byPlatform ? "vault.grouping.platform" : "vault.grouping.consumer")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                sectionSortMenu
                Button {
                    switch mode {
                    case .byPlatform: showAddAccount = true
                    case .byConsumer: showAddTool = true
                    }
                } label: {
                    Image(systemName: AppSymbols.Action.add)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    mode == .byPlatform
                        ? Text("vault.account.add")
                        : Text("vault.consumer.add")
                )
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            Divider()
        }
        .background(.bar)
    }

    @ViewBuilder
    private var macKeysDetailRoot: some View {
        if let selectedKeyId {
            KeyDetailView(
                keyId: selectedKeyId,
                viewModel: viewModel,
                allowDelete: selectedTab == .byPlatform,
                unassignFromToolId: unassignToolIdIfNeeded(for: selectedKeyId),
                splitPaneStyle: true,
                onCopy: { id in Task { await beginCopy(id) } },
                onAssign: { id in beginAssign(id) },
                onUnassign: { keyId, toolId in
                    Task { await viewModel.unassign(keyId: keyId, toolId: toolId) }
                },
                onDelete: { id in
                    Task {
                        await viewModel.deleteKey(id)
                        self.selectedKeyId = nil
                    }
                },
                onRequestMasterPassword: { id in Task { await beginReveal(id) } },
                revealedSecret: $revealedSecret,
                chromeCommand: $keyDetailChromeCommand,
                onEditingChanged: { keyDetailIsEditing = $0 }
            )
        } else {
            ContentUnavailableView(
                "vault.detail.pick.title",
                systemImage: AppSymbols.Key.outline,
                description: Text("vault.detail.pick.detail")
            )
        }
    }

    private var normalizedSearchQuery: String {
        VaultSearch.normalizedQuery(searchText)
    }

    private var isSearching: Bool {
        !normalizedSearchQuery.isEmpty
    }

    private var vaultSearchResults: VaultSearch.Results {
        VaultSearch.results(
            query: normalizedSearchQuery,
            keys: viewModel.allKeys,
            accounts: viewModel.accounts,
            tools: viewModel.tools
        )
    }

    private var visibleKeyIds: Set<UUID> {
        if isSearching {
            return Set(vaultSearchResults.keys.map(\.id))
        }
        return Set(viewModel.sections.flatMap(\.keys).map(\.id))
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
                    ToolbarItemGroup(placement: .primaryAction) {
                        sectionSortMenu
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

    private var sectionSortMenu: some View {
        let isCustom = viewModel.activeSectionSort.criterion == .custom
        return Menu {
            Picker(selection: sortCriterionBinding) {
                Text("vault.sort.criterion.name").tag(SectionSortCriterion.name)
                Text("vault.sort.criterion.created").tag(SectionSortCriterion.createdAt)
                Text("vault.sort.criterion.updated").tag(SectionSortCriterion.updatedAt)
                Text("vault.sort.criterion.custom").tag(SectionSortCriterion.custom)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            if !isCustom {
                Picker(selection: sortAscendingBinding) {
                    Text("vault.sort.ascending").tag(true)
                    Text("vault.sort.descending").tag(false)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            }
            if isCustom {
                Divider()
                Button("vault.sort.reorder") {
                    presentReorderSections()
                }
                .disabled(viewModel.reorderableSectionCount < 2)
            }
        } label: {
            Image(systemName: AppSymbols.Action.sort)
        }
        .accessibilityLabel(Text("vault.sort.menu"))
        .accessibilityValue(Text(viewModel.sectionSortAccessibilityValue))
        .help("vault.sort.menu")
    }

    private var sortCriterionBinding: Binding<SectionSortCriterion> {
        Binding(
            get: { viewModel.activeSectionSort.criterion },
            set: { criterion in
                Task {
                    await viewModel.selectSectionSortCriterion(criterion)
                    if criterion == .custom {
                        presentReorderSections()
                    }
                }
            }
        )
    }

    private var sortAscendingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.activeSectionSort.ascending },
            set: { ascending in
                viewModel.setSectionSortAscending(ascending)
            }
        )
    }

    private func presentReorderSections() {
        guard viewModel.reorderableSectionCount >= 2 else { return }
        let kind: ReorderSectionsTarget.Kind =
            viewModel.groupingMode == .byPlatform ? .accounts : .tools
        reorderSectionsTarget = ReorderSectionsTarget(
            kind: kind,
            items: viewModel.reorderableSectionItems()
        )
    }

    @ViewBuilder
    private func vaultList(selectionEnabled: Bool) -> some View {
        ScrollViewReader { proxy in
            List(selection: selectionEnabled ? keySelection : .constant(nil)) {
                if isSearching {
                    searchResultsBody(selectionEnabled: selectionEnabled)
                } else {
                    groupedListBody(selectionEnabled: selectionEnabled)
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
            .safeAreaInset(edge: .top, spacing: 0) {
                if !isSearching, let quota = viewModel.remainingQuota {
                    quotaBanner(quota)
                        .background(vaultGroupedBackground)
                }
            }
            .onAppear { scrollToPendingLocate(using: proxy) }
            .onChange(of: pendingSearchLocate) { _, _ in
                scrollToPendingLocate(using: proxy)
            }
            .onChange(of: viewModel.groupingMode) { _, _ in
                scrollToPendingLocate(using: proxy)
            }
            .onChange(of: viewModel.sections.map(\.id)) { _, _ in
                scrollToPendingLocate(using: proxy)
            }
        }
    }

    private func quotaBanner(_ quota: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("vault.quota.remaining \(quota)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("vault.paywall.open") { showPaywall = true }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func groupedListBody(selectionEnabled: Bool) -> some View {
        if viewModel.sections.isEmpty {
            Section {
                emptyState
            }
        } else {
            ForEach(viewModel.sections) { section in
                // 标题放进卡片首行，避免 List section header 被系统洗成淡灰。
                Section {
                    sectionHeader(section)
                        .listRowInsets(EdgeInsets(top: 8, leading: VaultListMetrics.rowLeading, bottom: 8, trailing: 8))
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                    if !isSectionCollapsed(section) {
                        sectionBody(section, selectionEnabled: selectionEnabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultsBody(selectionEnabled: Bool) -> some View {
        if vaultSearchResults.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("vault.search.empty")
                        .font(.headline)
                    Text("vault.search.empty.detail")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        } else {
            if !vaultSearchResults.keys.isEmpty {
                Section {
                    searchSectionHeader("vault.search.section.keys")
                    ForEach(vaultSearchResults.keys) { key in
                        keyRow(
                            key,
                            selectionEnabled: selectionEnabled,
                            caption: viewModel.accounts.first(where: { $0.id == key.accountId })?.displayName
                        )
                    }
                }
            }
            if !vaultSearchResults.accounts.isEmpty {
                Section {
                    searchSectionHeader("vault.search.section.accounts")
                    ForEach(vaultSearchResults.accounts) { account in
                        searchEntityRow(
                            title: account.displayName,
                            subtitle: searchMeta(
                                VaultSearch.platformDisplayName(for: account),
                                count: viewModel.allKeys.filter { $0.accountId == account.id }.count
                            ),
                            avatar: viewModel.avatar(for: account),
                            hint: "vault.search.revealAccount"
                        ) {
                            revealSearchAccount(account.id)
                        }
                    }
                }
            }
            if !vaultSearchResults.tools.isEmpty {
                Section {
                    searchSectionHeader("vault.search.section.tools")
                    ForEach(vaultSearchResults.tools) { tool in
                        searchEntityRow(
                            title: tool.name,
                            subtitle: searchCountCaption(
                                viewModel.allKeys.filter { $0.consumerToolIds.contains(tool.id) }.count
                            ),
                            avatar: viewModel.avatar(for: tool),
                            hint: "vault.search.revealConsumer"
                        ) {
                            revealSearchTool(tool.id)
                        }
                    }
                }
            }
        }
    }

    private func macTrashPlaceholder(title: LocalizedStringKey, description: LocalizedStringKey?) -> some View {
        VStack(spacing: 0) {
            MacPaneChrome {
                Spacer(minLength: 0)
            } trailing: {
                EmptyView()
            }
            if let description {
                ContentUnavailableView(
                    title,
                    systemImage: AppSymbols.Tab.trash,
                    description: Text(description)
                )
            } else {
                ContentUnavailableView(title, systemImage: AppSymbols.Tab.trash)
            }
        }
    }

    /// 右栏自己的顶栏：控件贴在这一栏最右侧，不进入下面的详情内容。
    private var macDetailChromeBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                if selectedKeyId != nil {
                    if keyDetailIsEditing {
                        Button("gate.cancel") {
                            keyDetailChromeCommand = .cancel
                        }
                        Button("vault.save") {
                            keyDetailChromeCommand = .save
                        }
                        .fontWeight(.semibold)
                    } else {
                        Button("vault.edit") {
                            keyDetailChromeCommand = .start
                        }
                    }
                }
                macColumnSearchField
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            Divider()
        }
        .background(.bar)
    }

    private var macColumnSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: AppSymbols.Action.search)
                .foregroundStyle(.secondary)
            TextField(String(localized: "vault.search"), text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)
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
        .frame(width: 180)
        .background(.quaternary.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("vault.search"))
    }

    @ViewBuilder
    private func searchSectionHeader(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body.weight(.bold))
                .foregroundStyle(vaultSectionTitleColor)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
        .selectionDisabled()
    }

    private func searchEntityRow(
        title: String,
        subtitle: String,
        avatar: AvatarChoice,
        hint: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VaultAvatarView(choice: avatar)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .padding(.vertical, 2)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(hint))
    }

    private func searchCountCaption(_ count: Int) -> String {
        if count == 0 {
            return String(localized: "vault.search.none.keys")
        }
        return String(localized: "vault.section.keyCount \(count)")
    }

    private func searchMeta(_ leading: String, count: Int) -> String {
        String(localized: "vault.search.meta \(leading) \(searchCountCaption(count))")
    }

    private func platformSectionId(_ accountId: UUID) -> String {
        "platform-\(accountId.uuidString)"
    }

    private func consumerSectionId(_ toolId: UUID) -> String {
        "consumer-\(toolId.uuidString)"
    }

    private func revealSearchAccount(_ accountId: UUID) {
        isSearchPresented = false
        searchText = ""
        selectedKeyId = nil
        collapsedSectionIds.remove(platformSectionId(accountId))
        pendingSearchLocate = .account(accountId)
        if selectedTab != .byPlatform {
            selectedTab = .byPlatform
        }
    }

    private func revealSearchTool(_ toolId: UUID) {
        isSearchPresented = false
        searchText = ""
        selectedKeyId = nil
        collapsedSectionIds.remove(consumerSectionId(toolId))
        pendingSearchLocate = .tool(toolId)
        if selectedTab != .byConsumer {
            selectedTab = .byConsumer
        }
    }

    private func scrollToPendingLocate(using proxy: ScrollViewProxy) {
        guard !isSearching, let target = pendingSearchLocate else { return }
        let sectionId: String
        switch target {
        case .account(let id):
            guard viewModel.groupingMode == .byPlatform,
                  viewModel.accounts.contains(where: { $0.id == id }) else { return }
            sectionId = platformSectionId(id)
        case .tool(let id):
            guard viewModel.groupingMode == .byConsumer,
                  viewModel.tools.contains(where: { $0.id == id }) else { return }
            sectionId = consumerSectionId(id)
        }
        collapsedSectionIds.remove(sectionId)
        pendingSearchLocate = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.snappy(duration: 0.2)) {
                proxy.scrollTo(sectionId, anchor: .top)
            }
        }
    }

    /// 与设置页同系的分组灰底。Catalyst 的 `systemGroupedBackground` 接近纯白，缝隙会看不见。
    private var vaultGroupedBackground: Color {
        SettingsChrome.groupedBackground(colorScheme)
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
            await viewModel.setGrouping(.byPlatform, persistAsDefault: false)
        case .byConsumer:
            await viewModel.setGrouping(.byConsumer, persistAsDefault: false)
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

    private func sectionCollapseId(_ section: KeyGroupSection) -> String {
        switch section.kind {
        case .platform(let accountId, _):
            return platformSectionId(accountId)
        case .consumer(let toolId, _):
            return consumerSectionId(toolId)
        case .shared:
            return "shared"
        case .unassigned:
            return "unassigned"
        }
    }

    private func isSectionCollapsed(_ section: KeyGroupSection) -> Bool {
        collapsedSectionIds.contains(sectionCollapseId(section))
    }

    private func toggleSectionCollapsed(_ section: KeyGroupSection) {
        let id = sectionCollapseId(section)
        if collapsedSectionIds.contains(id) {
            collapsedSectionIds.remove(id)
        } else {
            collapsedSectionIds.insert(id)
        }
    }

    /// 中栏行度量：密钥相对账号缩进一列（箭头宽 + 间距），头像与标题才能上下对齐。
    private enum VaultListMetrics {
        static let rowLeading: CGFloat = 16
        static let rowTrailing: CGFloat = 16
        static let chevronWidth: CGFloat = 14
        static let stackSpacing: CGFloat = 8
        static let glyph: CGFloat = 28
        static var chevronColumn: CGFloat { chevronWidth + stackSpacing }
        static var nestedLeading: CGFloat { rowLeading + chevronColumn }
        static var titleAfterGlyph: CGFloat { glyph + stackSpacing }
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
        HStack(spacing: VaultListMetrics.stackSpacing) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    toggleSectionCollapsed(section)
                }
            } label: {
                Image(systemName: collapsed ? AppSymbols.Action.chevronRight : AppSymbols.Action.chevronDown)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 14, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(sectionTitle(section)))
            .accessibilityHint(
                Text(collapsed ? "vault.a11y.sectionExpand" : "vault.a11y.sectionCollapse")
            )

            sectionAvatarButton(section)

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    toggleSectionCollapsed(section)
                }
            } label: {
                HStack(spacing: VaultListMetrics.stackSpacing) {
                    Text(sectionTitle(section))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(vaultSectionTitleColor)
                        .lineLimit(1)
                    if collapsed {
                        Text("vault.section.keyCount \(section.keys.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            // 工具栏 + = 加账号/工具；此处 + = 在该分区下加密钥 / 指派。
            sectionAddButton(section)
            sectionOverflowMenu(section)
        }
        .id(sectionCollapseId(section))
    }

    /// 账号 / 使用方头像单独成按钮，避免包在折叠热区里点不到「编辑」。
    @ViewBuilder
    private func sectionAvatarButton(_ section: KeyGroupSection) -> some View {
        let avatar = VaultAvatarView(choice: viewModel.avatar(for: section))
        switch section.kind {
        case .platform(let accountId, _):
            Button {
                editAccountId = accountId
            } label: {
                avatar
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("vault.account.edit"))
        case .consumer(let toolId, _):
            Button {
                editToolId = toolId
            } label: {
                avatar
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("vault.consumer.edit"))
        case .shared, .unassigned:
            avatar
        }
    }

    private func sectionHeaderIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sectionAddButton(_ section: KeyGroupSection) -> some View {
        switch section.kind {
        case .platform(let accountId, _):
            Button {
                beginAddKey(for: accountId)
            } label: {
                sectionHeaderIcon(AppSymbols.Action.add)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("vault.key.add"))
        case .consumer(let toolId, _):
            Button {
                beginAssignExistingKey(to: toolId)
            } label: {
                sectionHeaderIcon(AppSymbols.Action.add)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("vault.consumer.assignKey"))
        case .shared, .unassigned:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sectionOverflowMenu(_ section: KeyGroupSection) -> some View {
        switch section.kind {
        case .platform(let accountId, _):
            Menu {
                Button("vault.key.add", systemImage: AppSymbols.Action.add) {
                    beginAddKey(for: accountId)
                }
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
                sectionHeaderIcon(AppSymbols.Action.overflow)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("vault.a11y.sectionMenu"))
        case .consumer(let toolId, _):
            Menu {
                Button("vault.consumer.assignKey", systemImage: AppSymbols.Action.add) {
                    beginAssignExistingKey(to: toolId)
                }
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
                sectionHeaderIcon(AppSymbols.Action.overflow)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("vault.a11y.sectionMenu"))
        case .shared, .unassigned:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sectionBody(_ section: KeyGroupSection, selectionEnabled: Bool) -> some View {
        switch section.kind {
        case .platform:
            ForEach(section.keys) { key in
                keyRow(key, selectionEnabled: selectionEnabled, nested: true)
            }
            if section.keys.isEmpty {
                sectionEmptyRow("vault.account.empty.hint")
            }
        case .consumer(let toolId, _):
            ForEach(section.keys) { key in
                keyRow(
                    key,
                    unassignFromToolId: toolId,
                    allowDelete: false,
                    selectionEnabled: selectionEnabled,
                    nested: true
                )
            }
            if section.keys.isEmpty {
                sectionEmptyRow("vault.consumer.empty.hint")
            }
        case .shared, .unassigned:
            ForEach(section.keys) { key in
                keyRow(key, allowDelete: false, selectionEnabled: selectionEnabled, nested: true)
            }
        }
    }

    private func sectionEmptyRow(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, VaultListMetrics.titleAfterGlyph)
            .listRowInsets(
                EdgeInsets(
                    top: 2,
                    leading: VaultListMetrics.nestedLeading,
                    bottom: 10,
                    trailing: VaultListMetrics.rowTrailing
                )
            )
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }

    @ViewBuilder
    private func keyRow(
        _ key: KeyRecordDTO,
        unassignFromToolId: UUID? = nil,
        allowDelete: Bool = true,
        selectionEnabled: Bool = false,
        caption: String? = nil,
        nested: Bool = false
    ) -> some View {
        Group {
            if selectionEnabled {
                // Mac 中栏：点选 → 右侧详情，不再 push 新页。
                keyRowLabel(key, caption: caption)
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
                            onAssign: { id in beginAssign(id) },
                            onUnassign: { keyId, toolId in
                                Task { await viewModel.unassign(keyId: keyId, toolId: toolId) }
                            },
                            onDelete: { id in
                                Task { await viewModel.deleteKey(id) }
                            },
                            onRequestMasterPassword: { id in Task { await beginReveal(id) } },
                            revealedSecret: $revealedSecret,
                            chromeCommand: $keyDetailChromeCommand,
                            onEditingChanged: { keyDetailIsEditing = $0 }
                        )
                    } label: {
                        keyRowLabel(key, caption: caption)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await beginCopy(key.id) }
                    } label: {
                        Image(systemName: AppSymbols.Action.copy)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel(Text("vault.copy"))
                }
            }
        }
        .padding(.vertical, 2)
        .listRowInsets(
            EdgeInsets(
                top: 6,
                leading: nested ? VaultListMetrics.nestedLeading : VaultListMetrics.rowLeading,
                bottom: 6,
                trailing: VaultListMetrics.rowTrailing
            )
        )
        .accessibilityElement(children: .contain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if allowDelete {
                Button("vault.delete", role: .destructive) {
                    Task { await viewModel.deleteKey(key.id) }
                }
            }
        }
        .contextMenu {
            Button("vault.copy.secret") { Task { await beginCopy(key.id) } }
            if let toolId = unassignFromToolId {
                Button("vault.unassign", role: .destructive) {
                    Task { await viewModel.unassign(keyId: key.id, toolId: toolId) }
                }
            } else {
                Button("vault.assign") { beginAssign(key.id) }
            }
            if allowDelete {
                Divider()
                Button("vault.delete", role: .destructive) {
                    Task { await viewModel.deleteKey(key.id) }
                }
            }
        }
    }

    private func keyRowLabel(_ key: KeyRecordDTO, caption: String? = nil) -> some View {
        HStack(spacing: VaultListMetrics.stackSpacing) {
            VaultAvatarView(choice: viewModel.avatar(for: key))
            VStack(alignment: .leading, spacing: 2) {
                Text(key.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    assignmentCaption(count: key.consumerToolIds.count)
                    if let caption, !caption.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(caption)
                    }
                    if !key.secretAvailable {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("vault.secret.missing")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !key.secretAvailable {
                Image(systemName: AppSymbols.Key.missingSecret)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("vault.secret.missing"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 菜单栏 ⌘N /「添加密钥」：接到 `ApiRelayCommands` 发出的 `.newKey`。
    /// 锁屏遮罩下忽略；无账号时改为新建账号（与空列表 CTA 一致）。
    private func beginNewKeyFromMenu() {
        guard !viewModel.environment.appPrivacy.session.showsAppLockUI else { return }

        if selectedTab == .settings || selectedTab == .trash {
            selectedTab = .byPlatform
        }

        if viewModel.accounts.isEmpty {
            showAddAccount = true
            return
        }

        if let selectedKeyId,
           let key = viewModel.allKeys.first(where: { $0.id == selectedKeyId }) {
            beginAddKey(for: key.accountId)
            return
        }

        beginAddKey(for: viewModel.accounts[0].id)
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

    private func assignmentCaption(count: Int) -> some View {
        Group {
            if count == 0 {
                Text("vault.assign.badge.none")
            } else {
                Text("vault.assign.badge.count \(count)")
            }
        }
        .accessibilityLabel(
            count == 0
                ? Text("vault.assign.badge.none")
                : Text("vault.assign.badge.count \(count)")
        )
    }

    private func beginReveal(_ id: UUID) async {
        if let secret = await viewModel.revealReturning(keyId: id, masterPassword: nil) {
            revealedSecret = secret
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

    @ViewBuilder
    private var keySelectionShortcuts: some View {
        if let id = selectedKeyId,
           !isSearchFieldFocused,
           !keyDetailIsEditing,
           !showMasterPrompt {
            Button("vault.copy.secret") {
                guard !viewModel.environment.appPrivacy.session.isSessionLocked else { return }
                Task { await beginCopy(id) }
            }
            .keyboardShortcut("c", modifiers: .command)
        }
    }

    private func handleIncomingBackupURL(_ url: URL) {
        guard !viewModel.environment.appPrivacy.session.isSessionLocked else { return }
        guard url.isFileURL,
              url.pathExtension.lowercased() == SecureBackupFile.pathExtension else {
            return
        }
        Task {
            do {
                let data = try IncomingBackupPayload.read(from: url)
                incomingBackup = IncomingBackupPayload(data: data)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Home modifiers

/// `navigationBarDrawer` 仅 iOS / Catalyst 可用；原生 macOS 用默认 placement。
private struct VaultSearchableModifier: ViewModifier {
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool
    var prompt: LocalizedStringKey = "vault.search.prompt"
    var enabled: Bool = true

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else {
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
}

/// Mac 分栏顶栏：标题在左、操作在右，避免系统 toolbar 在中栏里变成灰色胶囊。
private struct MacPaneChrome<Leading: View, Trailing: View>: View {
    var leading: Leading
    var trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            Divider()
        }
        .background(.bar)
    }
}

private struct VaultHomeAlertsModifier: ViewModifier {
    @ObservedObject var viewModel: VaultHomeViewModel
    @Binding var showPaywall: Bool
    @Binding var pendingDeleteAccountId: UUID?
    @Binding var pendingDeleteToolId: UUID?

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
                set: {
                    if !$0 {
                        viewModel.toastMessage = nil
                        viewModel.toastDetail = nil
                    }
                }
            )) {
                Button("vault.toast.dismiss", role: .cancel) {
                    viewModel.toastMessage = nil
                    viewModel.toastDetail = nil
                }
            } message: {
                Text(viewModel.toastDetail ?? "")
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
    }
}

private struct VaultHomeSheetsModifier: ViewModifier {
    @ObservedObject var viewModel: VaultHomeViewModel
    @Binding var showAddAccount: Bool
    @Binding var showAddTool: Bool
    @Binding var showAddKeyFor: UpstreamAccountDTO?
    @Binding var assignKeyId: UUID?
    @Binding var assignToToolId: UUID?
    @Binding var reorderKeysTarget: ReorderKeysTarget?
    @Binding var reorderSectionsTarget: ReorderSectionsTarget?
    @Binding var editAccountId: UUID?
    @Binding var editToolId: UUID?
    @Binding var showPaywall: Bool
    @Binding var showAccountPlaceholder: Bool
    @Binding var showMasterPrompt: Bool
    @Binding var masterPasswordInput: String
    @Binding var pendingRevealKeyId: UUID?
    @Binding var pendingCopyKeyId: UUID?
    @Binding var revealedSecret: String?

    private var assignKeySheet: Binding<AssignKeySheetTarget?> {
        Binding(
            get: {
                guard let id = assignKeyId else { return nil }
                return AssignKeySheetTarget(id: id)
            },
            set: { assignKeyId = $0?.id }
        )
    }

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
            .sheet(isPresented: $showAddAccount) {
                AddAccountSheet(existingAccounts: viewModel.accounts) { platform, name, customPlatformName, url in
                    _ = await viewModel.createAccount(
                        platform: platform,
                        name: name,
                        customPlatformName: customPlatformName,
                        customBaseURL: url
                    )
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
                EditAccountSheet(account: account, avatarDefaults: viewModel.avatarDefaults) {
                    platform, name, customPlatformName, url, notes, usesDefaultAvatar, avatar in
                    await viewModel.updateAccount(
                        id: account.id,
                        platform: platform,
                        name: name,
                        customPlatformName: customPlatformName,
                        customBaseURL: url,
                        notes: notes,
                        usesDefaultAvatar: usesDefaultAvatar,
                        avatar: avatar
                    )
                }
            }
            .sheet(item: editToolSheet) { tool in
                EditConsumerToolSheet(tool: tool, avatarDefaults: viewModel.avatarDefaults) {
                    name, notes, usesDefaultAvatar, avatar in
                    await viewModel.renameTool(
                        id: tool.id,
                        name: name,
                        notes: notes,
                        usesDefaultAvatar: usesDefaultAvatar,
                        avatar: avatar
                    )
                }
            }
            .sheet(item: assignKeySheet) { target in
                AssignKeyToConsumerSheet(
                    keyId: target.id,
                    viewModel: viewModel
                )
            }
            .sheet(item: assignToToolSheet) { target in
                AssignExistingKeySheet(
                    toolName: target.name,
                    toolId: target.id,
                    viewModel: viewModel
                )
            }
            .sheet(item: $reorderKeysTarget) { target in
                ReorderNamedItemsSheet(
                    title: String(localized: "vault.reorder.keys.title \(target.title)"),
                    initialItems: target.keys.map { key in
                        ReorderableNamedItem(
                            id: key.id,
                            title: key.displayName,
                            symbolName: AppSymbols.Key.default
                        )
                    },
                    onSave: { orderedIds in
                        await viewModel.reorderKeys(orderedIds: orderedIds)
                    }
                )
            }
            .sheet(item: $reorderSectionsTarget) { target in
                ReorderNamedItemsSheet(
                    title: target.navigationTitle,
                    initialItems: target.items,
                    onSave: { orderedIds in
                        await viewModel.reorderSections(orderedIds: orderedIds)
                    }
                )
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(environment: viewModel.environment)
                    .settingsTaskSheet()
            }
            .sheet(isPresented: $showAccountPlaceholder) {
                AccountPlaceholderSheet(environment: viewModel.environment) {
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
                            revealedSecret = secret
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

private struct AssignKeySheetTarget: Identifiable {
    let id: UUID
}

private struct AssignToToolSheetTarget: Identifiable {
    let id: UUID
    let name: String
}

private struct ReorderKeysTarget: Identifiable {
    let id = UUID()
    let title: String
    let keys: [KeyRecordDTO]
}

private struct ReorderSectionsTarget: Identifiable {
    enum Kind {
        case accounts
        case tools
    }

    let id = UUID()
    let kind: Kind
    let items: [ReorderableNamedItem]

    var navigationTitle: String {
        switch kind {
        case .accounts: String(localized: "vault.reorder.accounts.title")
        case .tools: String(localized: "vault.reorder.tools.title")
        }
    }
}

/// Mac / Catalyst 上系统编辑态常常不画出抓手，自行画三条杠；iPhone 仍用系统自带的排序控件。
private struct ReorderDragHandle: View {
    var body: some View {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        EmptyView()
        #else
        Image(systemName: AppSymbols.Action.reorderHandle)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
        #endif
    }
}

private struct ReorderNamedItemsSheet: View {
    let title: String
    let onSave: ([UUID]) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReorderableNamedItem]
    @State private var persistTask: Task<Void, Never>?

    init(
        title: String,
        initialItems: [ReorderableNamedItem],
        onSave: @escaping ([UUID]) async -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _items = State(initialValue: initialItems)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("vault.reorder.keys.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.symbolName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.accentColor)
                                )
                                .accessibilityHidden(true)
                            Text(item.title)
                            Spacer(minLength: 8)
                            ReorderDragHandle()
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove(perform: move)
                }
            }
            #if os(iOS) || targetEnvironment(macCatalyst)
            .environment(\.editMode, .constant(.active))
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.done") { dismiss() }
                }
            }
            .onDisappear { persistTask?.cancel() }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 440, minHeight: 420, idealHeight: 480)
        #endif
    }

    private func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        persistTask?.cancel()
        persistTask = Task {
            await onSave(items.map(\.id))
        }
    }
}

private struct AssignKeyToConsumerSheet: View {
    let keyId: UUID
    @ObservedObject var viewModel: VaultHomeViewModel
    @Environment(\.dismiss) private var dismiss

    private var key: KeyRecordDTO? {
        viewModel.allKeys.first { $0.id == keyId }
    }

    private var tools: [ConsumerToolDTO] {
        viewModel.tools.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("vault.assign.pick.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if tools.isEmpty {
                    Section {
                        Text("vault.assign.noConsumer")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(tools) { tool in
                            let alreadyAssigned = key?.consumerToolIds.contains(tool.id) == true
                            Button {
                                guard !alreadyAssigned else { return }
                                Task {
                                    await viewModel.assign(keyId: keyId, toolId: tool.id)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: AppSymbols.tool(name: tool.name, storedSymbol: tool.iconSymbol))
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.accentColor)
                                        )
                                        .accessibilityHidden(true)
                                    Text(tool.name)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    if alreadyAssigned {
                                        Image(systemName: AppSymbols.Action.checkmark)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityLabel(Text("vault.assign.alreadyHere"))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyAssigned)
                        }
                    }
                }
            }
            .navigationTitle("vault.assign.title")
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 360, idealHeight: 440)
        #endif
        .settingsTaskSheet()
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
    @State private var customPlatformName = ""
    @State private var instanceLabel = ""
    @State private var lastSuggestedInstance = ""
    @State private var customURL = ""
    let onSave: (String, String, String?, String?) async -> Void

    private var isCustom: Bool {
        platform == PresetCatalog.customPlatformID
    }

    private var resolvedPlatformName: String {
        if isCustom {
            return customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return PresetCatalog.platform(id: platform)?.displayName
            ?? String(localized: "vault.custom.platform")
    }

    private var resolvedDisplayName: String {
        let instance = instanceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let platformName = resolvedPlatformName
        if platformName.isEmpty { return "" }
        if instance.isEmpty { return platformName }
        return String(localized: "vault.consumer.compoundName \(platformName) \(instance)")
    }

    private var canSave: Bool {
        !resolvedPlatformName.isEmpty
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
                if isCustom {
                    TextField("vault.account.platformName", text: $customPlatformName)
                }
                TextField("vault.account.instance", text: $instanceLabel)
                if isCustom {
                    Text("vault.account.name.hint.custom")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("vault.account.name.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("vault.consumer.preview") {
                    Text(resolvedDisplayName.isEmpty ? "—" : resolvedDisplayName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if isCustom {
                    TextField("vault.account.baseURL", text: $customURL)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("vault.account.add")
            .onAppear { applyInstanceSuggestion(force: true) }
            .onChange(of: platform) { _, newValue in
                if newValue == PresetCatalog.customPlatformID {
                    customPlatformName = ""
                    instanceLabel = ""
                    lastSuggestedInstance = ""
                } else {
                    customPlatformName = ""
                    refreshInstanceSuggestionIfNeeded()
                }
            }
            .onChange(of: customPlatformName) { _, _ in
                guard isCustom else { return }
                refreshInstanceSuggestionIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vault.save") {
                        Task {
                            let trimmedCustom = customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
                            await onSave(
                                platform,
                                resolvedDisplayName,
                                isCustom ? trimmedCustom : nil,
                                isCustom ? customURL : nil
                            )
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func refreshInstanceSuggestionIfNeeded() {
        let trimmed = instanceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || instanceLabel == lastSuggestedInstance {
            applyInstanceSuggestion(force: true)
        }
    }

    /// 同一平台下递增：第一份默认「账号 1」。自定义须先有平台名才建议。
    private func applyInstanceSuggestion(force: Bool) {
        let base = resolvedPlatformName
        guard !base.isEmpty else {
            if force {
                instanceLabel = ""
                lastSuggestedInstance = ""
            }
            return
        }
        let count: Int
        if isCustom {
            count = existingAccounts.filter {
                $0.platform == platform
                    && ($0.customPlatformName ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines) == base
            }.count
        } else {
            count = existingAccounts.filter { $0.platform == platform }.count
        }
        let suggested = String(localized: "vault.account.instanceDefault \(count + 1)")
        if force || instanceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            instanceLabel = suggested
            lastSuggestedInstance = suggested
        }
    }
}

private struct AddConsumerToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingTools: [ConsumerToolDTO]
    /// 空字符串 = 完全自定义；否则为预置显示名（如 VS Code）。
    @State private var baseName = "VS Code"
    @State private var customSoftwareName = ""
    @State private var deviceLabel = ""
    @State private var lastSuggestedDevice = ""
    let onSave: (String) async -> Void

    private var customBaseTag: String { "" }

    private var isCustom: Bool {
        baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedSoftwareName: String {
        if isCustom {
            return customSoftwareName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return baseName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedDisplayName: String {
        let device = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let software = resolvedSoftwareName
        if software.isEmpty { return "" }
        if device.isEmpty { return software }
        return String(localized: "vault.consumer.compoundName \(software) \(device)")
    }

    private var canSave: Bool {
        !resolvedSoftwareName.isEmpty
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
                if isCustom {
                    TextField("vault.consumer.software", text: $customSoftwareName)
                }
                TextField("vault.consumer.device", text: $deviceLabel)
                if isCustom {
                    Text("vault.consumer.name.hint.custom")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("vault.consumer.name.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("vault.consumer.preview") {
                    Text(resolvedDisplayName.isEmpty ? "—" : resolvedDisplayName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("vault.consumer.add")
            .onAppear { applyDeviceSuggestion(force: true) }
            .onChange(of: baseName) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customSoftwareName = ""
                    deviceLabel = ""
                    lastSuggestedDevice = ""
                } else {
                    customSoftwareName = ""
                    refreshDeviceSuggestionIfNeeded()
                }
            }
            .onChange(of: customSoftwareName) { _, _ in
                guard isCustom else { return }
                refreshDeviceSuggestionIfNeeded()
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
                    .disabled(!canSave)
                }
            }
        }
    }

    private func refreshDeviceSuggestionIfNeeded() {
        let trimmed = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || deviceLabel == lastSuggestedDevice {
            applyDeviceSuggestion(force: true)
        }
    }

    /// 同一软件名下递增：第一台设备默认「电脑 1」。自定义须先有软件名才建议。
    private func applyDeviceSuggestion(force: Bool) {
        let base = resolvedSoftwareName
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
    let avatarDefaults: AvatarPreferenceDefaults
    let onSave: (
        _ platform: String,
        _ name: String,
        _ customPlatformName: String?,
        _ customBaseURL: String?,
        _ notes: String?,
        _ usesDefaultAvatar: Bool,
        _ avatar: AvatarChoice
    ) async -> Bool

    @State private var platform: String
    @State private var customPlatformName: String
    @State private var name: String
    @State private var customURL: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var usesDefaultAvatar: Bool
    @State private var customAvatar: AvatarChoice
    @State private var showAvatarEditor = false

    init(
        account: UpstreamAccountDTO,
        avatarDefaults: AvatarPreferenceDefaults,
        onSave: @escaping (
            _ platform: String,
            _ name: String,
            _ customPlatformName: String?,
            _ customBaseURL: String?,
            _ notes: String?,
            _ usesDefaultAvatar: Bool,
            _ avatar: AvatarChoice
        ) async -> Bool
    ) {
        self.account = account
        self.avatarDefaults = avatarDefaults
        self.onSave = onSave
        _platform = State(initialValue: account.platform)
        _customPlatformName = State(initialValue: account.customPlatformName ?? "")
        _name = State(initialValue: account.displayName)
        _customURL = State(initialValue: account.customBaseURL ?? "")
        _notes = State(initialValue: account.notes ?? "")
        let override = AvatarChoice.parse(symbol: account.avatarSymbol, color: account.avatarColor)
        _usesDefaultAvatar = State(initialValue: override == nil)
        _customAvatar = State(
            initialValue: override ?? AvatarCatalog.accountDefault(platform: account.platform, defaults: avatarDefaults)
        )
    }

    private var isCustom: Bool {
        platform == PresetCatalog.customPlatformID
    }

    private var selectedPlatformLabel: String {
        PresetCatalog.platform(id: platform)?.displayName
            ?? String(localized: "vault.custom.platform")
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
        if isCustom {
            return hasName && !customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasName
    }

    private var displayedAvatar: AvatarChoice {
        usesDefaultAvatar
            ? AvatarCatalog.accountDefault(platform: platform, defaults: avatarDefaults)
            : customAvatar
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .center, spacing: 14) {
                        EditableAvatarButton(choice: displayedAvatar) {
                            showAvatarEditor = true
                        }
                        TextField("vault.account.name", text: $name)
                            .font(.title3.weight(.semibold))
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
                }

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
                    if isCustom {
                        TextField("vault.account.platformName", text: $customPlatformName)
                    } else {
                        LabeledContent("vault.account.platform.selected") {
                            Text(selectedPlatformLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if isCustom {
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
                            let trimmedCustom = customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let ok = await onSave(
                                platform,
                                name,
                                isCustom ? trimmedCustom : nil,
                                isCustom ? customURL : nil,
                                notes,
                                usesDefaultAvatar,
                                customAvatar
                            )
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showAvatarEditor) {
                NavigationStack {
                    Form {
                        Section {
                            AvatarOverrideEditor(
                                defaultChoice: AvatarCatalog.accountDefault(
                                    platform: platform,
                                    defaults: avatarDefaults
                                ),
                                usesDefault: $usesDefaultAvatar,
                                customChoice: $customAvatar
                            )
                            .buttonStyle(.borderless)
                        }
                    }
                    .navigationTitle("vault.avatar")
                    #if os(iOS) || targetEnvironment(macCatalyst)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("vault.avatar.done") { showAvatarEditor = false }
                        }
                    }
                }
                #if os(macOS) || targetEnvironment(macCatalyst)
                .frame(minWidth: 400, minHeight: 480)
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 440)
        #endif
    }
}

private struct EditConsumerToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tool: ConsumerToolDTO
    let avatarDefaults: AvatarPreferenceDefaults
    let onSave: (_ name: String, _ notes: String?, _ usesDefaultAvatar: Bool, _ avatar: AvatarChoice) async -> Bool

    @State private var name: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var usesDefaultAvatar: Bool
    @State private var customAvatar: AvatarChoice

    init(
        tool: ConsumerToolDTO,
        avatarDefaults: AvatarPreferenceDefaults,
        onSave: @escaping (_ name: String, _ notes: String?, _ usesDefaultAvatar: Bool, _ avatar: AvatarChoice) async -> Bool
    ) {
        self.tool = tool
        self.avatarDefaults = avatarDefaults
        self.onSave = onSave
        _name = State(initialValue: tool.name)
        _notes = State(initialValue: tool.notes ?? "")
        let override = AvatarChoice.parse(symbol: tool.avatarSymbol, color: tool.avatarColor)
        _usesDefaultAvatar = State(initialValue: override == nil)
        _customAvatar = State(
            initialValue: override ?? AvatarCatalog.toolDefault(
                name: tool.name,
                catalogSymbol: tool.iconSymbol,
                defaults: avatarDefaults
            )
        )
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
                Section("vault.avatar") {
                    AvatarOverrideEditor(
                        defaultChoice: AvatarCatalog.toolDefault(
                            name: name,
                            catalogSymbol: tool.iconSymbol,
                            defaults: avatarDefaults
                        ),
                        usesDefault: $usesDefaultAvatar,
                        customChoice: $customAvatar
                    )
                    .buttonStyle(.borderless)
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
                            if await onSave(name, notes, usesDefaultAvatar, customAvatar) { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 600)
        #endif
    }
}

private struct AddKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let accountName: String
    let existingKeyCount: Int
    let onSave: (String, String, Bool, String?) async -> KeySaveResult
    @State private var name = ""
    @State private var secret = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var duplicateExistingName: String?

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
                        Task { await persist(acknowledgeDuplicate: false) }
                    }
                    .disabled(isSaving || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .vaultPossibleDuplicateAlert(existingName: $duplicateExistingName) {
                await persist(acknowledgeDuplicate: true)
            }
        }
    }

    private func persist(acknowledgeDuplicate: Bool) async {
        isSaving = true
        defer { isSaving = false }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await onSave(
            name,
            secret,
            acknowledgeDuplicate,
            trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        switch result {
        case .saved:
            secret = ""
            dismiss()
        case .possibleDuplicate(let existingName):
            duplicateExistingName = existingName
        case .failed:
            break
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
    let environment: AppEnvironment
    let onSyncNow: () async -> CloudSyncNowOutcome
    @Environment(\.dismiss) private var dismiss
    @State private var status = CloudSyncStatusDTO.placeholder
    @State private var isSyncing = false
    @State private var syncFeedback: String?
    @State private var syncFeedbackIsError = false

    private var isSignedIn: Bool { status.account == .signedIn }

    private var accountStatusText: String {
        switch status.account {
        case .signedIn: String(localized: "vault.sync.icloud.status.signedIn")
        case .signedOut: String(localized: "vault.sync.icloud.status.signedOut")
        case .restricted: String(localized: "vault.sync.icloud.status.restricted")
        case .temporarilyUnavailable: String(localized: "vault.sync.icloud.status.temporarilyUnavailable")
        case .unknown: String(localized: "vault.sync.icloud.status.unknown")
        }
    }

    private var accountDotColor: Color {
        switch status.account {
        case .signedIn: .green
        case .restricted, .temporarilyUnavailable: .orange
        case .signedOut, .unknown: .secondary
        }
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
                    statusCard
                    actionButtons
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
            .task {
                await refreshStatus()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(800))
                    await refreshStatus()
                }
            }
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
                        .fill(isSignedIn ? Color.accentColor : Color.secondary)
                )
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("vault.sync.section.account")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(accountDotColor)
                        .frame(width: 8, height: 8)
                    Text(accountStatusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSignedIn ? Color.primary : Color.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text(
                        "vault.sync.icloud.status.combined \(String(localized: "vault.sync.icloud.status")) \(accountStatusText)"
                    )
                )
                Text("vault.sync.icloud.followsSystem")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(syncHeadline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(syncHeadlineColor)
                Text(syncDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let syncFeedback {
                    Text(syncFeedback)
                        .font(.caption)
                        .foregroundStyle(syncFeedbackIsError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(syncFeedback))
                }
            }
            Spacer(minLength: 8)
            InlineHelpButton(
                title: "vault.sync.title",
                message: "vault.sync.status.help",
                showsTitle: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
        .accessibilityElement(children: .combine)
    }

    private var isActivelySyncing: Bool {
        if isSyncing { return true }
        switch status.activity {
        case .exporting, .importing, .settingUp: return true
        case .idle: return false
        }
    }

    private var syncHeadline: String {
        if isActivelySyncing {
            return String(localized: "vault.sync.headline.syncing")
        }
        if let failure = status.lastFailureMessage, !failure.isEmpty {
            return String(localized: "vault.sync.headline.failed")
        }
        if !status.mirroringEnabled {
            return String(localized: "vault.sync.headline.offline")
        }
        if status.lastSuccessAt != nil {
            return String(localized: "vault.sync.headline.synced")
        }
        return String(localized: "vault.sync.headline.pending")
    }

    private var syncHeadlineColor: Color {
        if let failure = status.lastFailureMessage, !failure.isEmpty, !isActivelySyncing {
            return .red
        }
        if !status.mirroringEnabled { return .secondary }
        return .primary
    }

    private var syncDetail: String {
        if isActivelySyncing {
            switch status.activity {
            case .exporting: return String(localized: "vault.sync.detail.exporting")
            case .importing: return String(localized: "vault.sync.detail.importing")
            case .settingUp: return String(localized: "vault.sync.detail.setup")
            case .idle: return String(localized: "vault.sync.headline.syncing")
            }
        }
        if let failure = status.lastFailureMessage, !failure.isEmpty {
            return failure
        }
        if !status.mirroringEnabled {
            return String(localized: "vault.sync.detail.offline")
        }
        if let date = status.lastSuccessAt {
            return String(localized: "vault.sync.lastSuccess.at \(Self.formatSyncDate(date))")
        }
        return String(localized: "vault.sync.lastSuccess.none")
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
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
            .disabled(isSyncing || !isSignedIn)

            HStack(alignment: .center, spacing: 8) {
                Button {
                    openSystemSettingsForAppleAccount()
                } label: {
                    Label("vault.sync.openSystemSettings", systemImage: AppSymbols.Sync.openSystemSettings)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                InlineHelpButton(
                    title: "vault.sync.openSystemSettings",
                    message: "vault.sync.openSystemSettings.footnote",
                    showsTitle: false
                )
            }
        }
    }

    private func refreshStatus() async {
        status = await environment.cloudSync.snapshot()
    }

    private func performSyncNow() async {
        syncFeedback = nil
        isSyncing = true
        defer { isSyncing = false }
        let outcome = await onSyncNow()
        await refreshStatus()
        switch outcome {
        case .uploaded, .refreshed, .nothingToUpload, .localOnly:
            syncFeedback = nil
        case .timedOut:
            syncFeedbackIsError = true
            syncFeedback = String(localized: "vault.sync.now.timedOut")
        case .unavailable:
            syncFeedbackIsError = true
            syncFeedback = String(localized: "vault.sync.now.unavailable")
        case .failed(let message):
            syncFeedbackIsError = true
            syncFeedback = message
        }
    }

    private static func formatSyncDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
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
            actionError = error.localizedDescription
        }
    }
}

private func trashBatchSelection(from items: Set<TrashSelection>) -> TrashBatchSelection {
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
private struct RecentlyDeletedBatchDetailView: View {
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
            actionError = error.localizedDescription
        }
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
                            Task { await runAction(model.permanent) }
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

private struct VaultPossibleDuplicateAlert: ViewModifier {
    @Binding var existingName: String?
    var onConfirm: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "vault.key.duplicate.title",
                isPresented: Binding(
                    get: { existingName != nil },
                    set: { if !$0 { existingName = nil } }
                )
            ) {
                Button("vault.key.duplicate.confirm") {
                    Task { await onConfirm() }
                }
                Button("gate.cancel", role: .cancel) {
                    existingName = nil
                }
            } message: {
                Text("vault.key.duplicate.body \(existingName ?? "")")
            }
    }
}

extension View {
    func vaultPossibleDuplicateAlert(
        existingName: Binding<String?>,
        onConfirm: @escaping () async -> Void
    ) -> some View {
        modifier(VaultPossibleDuplicateAlert(existingName: existingName, onConfirm: onConfirm))
    }
}

#if DEBUG
#Preview("Vault Home") {
    let environment = AppEnvironment.makePreview()
    VaultHomeView(viewModel: VaultHomeViewModel(environment: environment))
        .environmentObject(environment)
}
#endif
