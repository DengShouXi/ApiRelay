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

    var uiTestIdentifier: String {
        switch self {
        case .byPlatform: "vault.tab.byPlatform"
        case .byConsumer: "vault.tab.byConsumer"
        case .trash: "vault.tab.trash"
        case .settings: "vault.tab.settings"
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
    @State private var revealedSecret: SecretRevealResult?
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
    @State private var pendingDeleteKeyId: UUID?
    /// 分区「⋯」→ 编辑上游账号（平台 / 显示名）。
    @State private var editAccountId: UUID?
    /// 分区「⋯」→ 重命名使用方。
    @State private var editToolId: UUID?
    /// Mac 三栏：中间列表选中的密钥，右侧展示详情。
    @State private var selectedKeyId: UUID?
    /// Mac 三栏：回收站中栏选中项，右侧展示恢复 / 永久删除。
    @State private var selectedTrashItem: TrashSelection?
    /// 回收站选择模式（三端同一套；不改平时的单选 List）。
    @State private var trashPresentation = VaultTrashPresentationState()
    /// Mac 右栏占位：`false` 表示回收站为空（不要显示「选择一项」）。
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
    @Environment(\.scenePhase) private var scenePhase
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
        trashPresentation.actionSelection
    }

    private func resetTrashSelectMode() {
        trashPresentation.resetSelection()
    }

    private var trashIsSelecting: Bool { trashPresentation.isSelecting }
    private var trashHasItems: Bool? {
        get { trashPresentation.hasItems }
        nonmutating set { trashPresentation.hasItems = newValue }
    }
    private var trashIsSelectingBinding: Binding<Bool> {
        Binding(get: { trashPresentation.isSelecting }, set: { trashPresentation.isSelecting = $0 })
    }
    private var trashCheckedItemsBinding: Binding<Set<TrashSelection>> {
        Binding(get: { trashPresentation.checkedItems }, set: { trashPresentation.checkedItems = $0 })
    }
    private var trashVisibleItemsBinding: Binding<Set<TrashSelection>> {
        Binding(get: { trashPresentation.visibleItems }, set: { trashPresentation.visibleItems = $0 })
    }
    private var trashHasItemsBinding: Binding<Bool?> {
        Binding(get: { trashPresentation.hasItems }, set: { trashPresentation.hasItems = $0 })
    }

    private func abandonPasswordPromptForSceneExit() {
        viewModel.abandonCombinationPending()
        masterPasswordInput = ""
        pendingRevealKeyId = nil
        pendingCopyKeyId = nil
        showMasterPrompt = false
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
            viewModel.abandonCombinationPending()
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel.invalidateRevealReuseLeaveForeground()
                revealedSecret = nil
            }
            if phase == .inactive && viewModel.environment.gate.isAuthenticationInProgress() {
                return
            }
            if phase != .active {
                abandonPasswordPromptForSceneExit()
            }
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
        .onChange(of: viewModel.presentMasterPasswordPrompt) { _, present in
            if present {
                showMasterPrompt = true
                viewModel.presentMasterPasswordPrompt = false
            }
        }
        .onReceive(viewModel.environment.appPrivacy.$session) { session in
            if session.isSessionLocked {
                viewModel.handleSessionLocked()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .securityPreferencesDidPersist)) { _ in
            viewModel.invalidateRevealReuseForSecuritySettingsChange()
        }
        .modifier(VaultHomeAlertsModifier(
            viewModel: viewModel,
            showPaywall: $showPaywall,
            pendingDeleteAccountId: $pendingDeleteAccountId,
            pendingDeleteToolId: $pendingDeleteToolId,
            pendingDeleteKeyId: $pendingDeleteKeyId
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
                isSelecting: trashIsSelectingBinding,
                checkedItems: trashCheckedItemsBinding,
                visibleItems: trashVisibleItemsBinding
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
                .accessibilityIdentifier(tab.uiTestIdentifier)
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
        .onChange(of: selectedKeyId) { old, new in
            revealedSecret = nil
            keyDetailIsEditing = false
            keyDetailChromeCommand = .none
            if old != nil, new == nil {
                viewModel.invalidateRevealReuseCloseDetail()
            } else if let old, let new, old != new {
                viewModel.invalidateRevealReuseSwitchKey()
            }
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
        .accessibilityIdentifier(tab.uiTestIdentifier)
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
                reportsHasItems: trashHasItemsBinding,
                isSelecting: trashIsSelectingBinding,
                checkedItems: trashCheckedItemsBinding,
                visibleItems: trashVisibleItemsBinding
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
                    pendingDeleteKeyId = id
                },
                onRequestMasterPassword: { id in Task { await beginReveal(id) } },
                revealedSecret: $revealedSecret,
                chromeCommand: $keyDetailChromeCommand,
                onEditingChanged: { keyDetailIsEditing = $0 }
            )
            .id(selectedKeyId)
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
                if !isSearching {
                    switch viewModel.quotaState {
                    case .free(let quota):
                        quotaBanner(quota)
                            .background(vaultGroupedBackground)
                    case .unavailable:
                        Text("vault.quota.unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(vaultGroupedBackground)
                    case .checking, .unlimited:
                        EmptyView()
                    }
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
                                pendingDeleteKeyId = id
                            },
                            onRequestMasterPassword: { id in Task { await beginReveal(id) } },
                            revealedSecret: $revealedSecret,
                            chromeCommand: $keyDetailChromeCommand,
                            onEditingChanged: { keyDetailIsEditing = $0 }
                        )
                        .id(key.id)
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
                    pendingDeleteKeyId = key.id
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
                    pendingDeleteKeyId = key.id
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
        if viewModel.quotaState == .free(remaining: 0) {
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
        if let result = await viewModel.revealReturning(keyId: id, masterPassword: nil) {
            revealedSecret = result
        } else if viewModel.needsMasterPassword {
            pendingRevealKeyId = id
            showMasterPrompt = true
        } else if viewModel.offerCombinationAppPassword || viewModel.hasPendingSensitiveRetry {
            pendingRevealKeyId = id
        }
    }

    private func beginCopy(_ id: UUID) async {
        let ok = await viewModel.copyReturning(keyId: id, masterPassword: nil)
        if !ok && viewModel.needsMasterPassword {
            pendingCopyKeyId = id
            showMasterPrompt = true
        } else if !ok && (viewModel.offerCombinationAppPassword || viewModel.hasPendingSensitiveRetry) {
            pendingCopyKeyId = id
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
struct VaultSearchableModifier: ViewModifier {
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
struct MacPaneChrome<Leading: View, Trailing: View>: View {
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
    @Binding var pendingDeleteKeyId: UUID?

    func body(content: Content) -> some View {
        content
            .alert("vault.error.title", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.errorMessage = nil
                        viewModel.clearOrdinaryAppPasswordRecoveryOffer()
                    }
                }
            )) {
                if viewModel.ordinaryAppPasswordNeedsIndependentRecovery {
                    Button("settings.appPassword.recover") {
                        Task { await viewModel.recoverIndependentAppPasswordFromOrdinaryEntry() }
                    }
                }
                Button("gate.cancel", role: .cancel) {
                    viewModel.errorMessage = nil
                    viewModel.clearOrdinaryAppPasswordRecoveryOffer()
                }
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
            .overlay(alignment: .bottom) {
                if CombinationExplicitAuth.shouldShowExplicitEntry(
                    hasBoundOperation: viewModel.hasPendingSensitiveRetry,
                    policy: viewModel.environment.appPrivacy.session.preferences.revealPolicy
                ) {
                    Button("appLock.useAppPassword") {
                        Task { await viewModel.beginCombinationAppPasswordEntry() }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 8)
                    .accessibilityLabel(Text("appLock.useAppPassword"))
                    .accessibilityHint(Text("appLock.combination.hint"))
                }
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
            .confirmationDialog(
                "vault.delete",
                isPresented: Binding(
                    get: { pendingDeleteKeyId != nil },
                    set: { if !$0 { pendingDeleteKeyId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("vault.delete", role: .destructive) {
                    if let id = pendingDeleteKeyId {
                        pendingDeleteKeyId = nil
                        Task { await viewModel.deleteKey(id) }
                    }
                }
                Button("gate.cancel", role: .cancel) { pendingDeleteKeyId = nil }
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
    @Binding var revealedSecret: SecretRevealResult?

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
            .sheet(isPresented: $showMasterPrompt, onDismiss: {
                viewModel.cancelMasterPasswordPrompt()
                masterPasswordInput = ""
                pendingRevealKeyId = nil
                pendingCopyKeyId = nil
            }) {
                MasterPasswordPrompt(
                    password: $masterPasswordInput,
                    title: viewModel.usesCombinationPolicy ? "appLock.useAppPassword" : "vault.masterPassword.title",
                    hint: viewModel.usesCombinationPolicy ? "appLock.combination.hint" : "vault.masterPassword.disclosure"
                ) {
                    let pwd = masterPasswordInput
                    masterPasswordInput = ""
                    if viewModel.hasPendingSensitiveRetry {
                        await viewModel.submitMasterPassword(pwd)
                    } else if let id = pendingRevealKeyId {
                        pendingRevealKeyId = nil
                        if let result = await viewModel.revealReturning(keyId: id, masterPassword: pwd) {
                            revealedSecret = result
                        }
                    } else if let id = pendingCopyKeyId {
                        pendingCopyKeyId = nil
                        await viewModel.copy(keyId: id, masterPassword: pwd)
                    } else {
                        await viewModel.submitMasterPassword(pwd)
                    }
                    showMasterPrompt = false
                }
            }
    }
}

private struct MasterPasswordPrompt: View {
    @Binding var password: String
    var title: LocalizedStringKey = "vault.masterPassword.title"
    var hint: LocalizedStringKey = "vault.masterPassword.disclosure"
    let onConfirm: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SecureField("vault.masterPassword", text: $password)
                    .sensitivePasswordInput()
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle(title)
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
#if DEBUG
#Preview("Vault Home") {
    let environment = AppEnvironment.makePreview()
    VaultHomeView(viewModel: VaultHomeViewModel(environment: environment))
        .environmentObject(environment)
}
#endif
