import SwiftUI

/// 自动锁定 / 剪贴板自动清除子页：开关 + 最多 5 条时长（均可删）+ 时分秒编辑。
struct DurationFeatureSettingsView: View {
    enum Kind {
        case autoLock
        case clipboardClear
    }

    let kind: Kind
    @Binding var prefs: PreferencesDTO
    let persist: (PreferencesPatch) -> Void

    @State private var isEditorPresented = false
    @State private var activeEditor = EditorSession(mode: .add)
    @State private var showCapacityAlert = false

    var body: some View {
        SettingsSubpage(title: title) {
            SettingsCard {
                enabledToggle
            }

            SettingsCard {
                if options.isEmpty {
                    Text("settings.duration.empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(options.enumerated()), id: \.element) { index, seconds in
                        if index > 0 { SettingsCardDivider() }
                        durationRow(seconds)
                    }
                }
                SettingsCardDivider()
                addRow
            }
        }
        // 与「验证方式 → 设主密码」同一套路：导航推入，不用 sheet。
        // 设置栈里的返回 / Mac 顶栏返回即取消；底部「完成」才写入。
        // 本仓库里 sheet 在 Mac 上取消时灵时不灵，已在购买页外尽量避开。
        .navigationDestination(isPresented: $isEditorPresented) {
            DurationEditorPage(
                session: activeEditor,
                onConfirm: { hours, minutes, seconds in
                    applyEditor(activeEditor, hours: hours, minutes: minutes, seconds: seconds)
                }
            )
            .id(activeEditor.id)
        }
        .alert(
            String(localized: "settings.duration.atCapacity.title"),
            isPresented: $showCapacityAlert
        ) {
            Button("settings.done", role: .cancel) {}
        } message: {
            Text("settings.duration.atCapacity.message")
        }
    }

    private func openEditor(_ session: EditorSession) {
        activeEditor = session
        isEditorPresented = true
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .autoLock: return "settings.autoLock.label"
        case .clipboardClear: return "settings.clipboardClear.label"
        }
    }

    private var isEnabled: Bool {
        switch kind {
        case .autoLock: return prefs.appLockEnabled
        case .clipboardClear: return prefs.clipboardClearEnabled
        }
    }

    private var selectedSeconds: Int {
        switch kind {
        case .autoLock: return prefs.autoLockSeconds
        case .clipboardClear: return prefs.clipboardClearSeconds
        }
    }

    private var options: [Int] {
        switch kind {
        case .autoLock: return prefs.autoLockDurationOptions
        case .clipboardClear: return prefs.clipboardClearDurationOptions
        }
    }

    /// 本页开关行：`标题　ⓘ　　开关`。ⓘ 紧贴标题（宪法 v2.8.0）。
    private var enabledToggle: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(enabledTitle)
                .font(.body)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(minWidth: 0, alignment: .leading)
            InlineHelpButton(title: enabledTitle, message: enabledDetail, showsTitle: false)
            Spacer(minLength: 8)
            Toggle(enabledTitle, isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var enabledTitle: LocalizedStringKey {
        switch kind {
        case .autoLock: return "settings.autoLock.label"
        case .clipboardClear: return "settings.clipboardClear.enabled"
        }
    }

    private var enabledDetail: LocalizedStringResource {
        switch kind {
        case .autoLock: return "settings.autoLock.rowDetail"
        case .clipboardClear: return "settings.clipboardClear.enabled.rowDetail"
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                if newValue, options.isEmpty {
                    openEditor(EditorSession(mode: .add))
                    return
                }
                applyEnabled(newValue)
            }
        )
    }

    private func durationRow(_ seconds: Int) -> some View {
        let selected = isEnabled && selectedSeconds == seconds
        return HStack(alignment: .center, spacing: 8) {
            Button {
                applySelection(seconds)
            } label: {
                Text(DurationOptionList.displayName(seconds))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Button {
                openEditor(EditorSession(mode: .edit(seconds)))
            } label: {
                Image(systemName: AppSymbols.Action.edit)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("settings.duration.edit"))

            Button(role: .destructive) {
                applyRemoval(seconds)
            } label: {
                Image(systemName: AppSymbols.Tab.trash)
                    .font(.body)
                    .foregroundStyle(.red)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("settings.duration.delete"))

            Image(systemName: AppSymbols.Settings.checkmark)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(selected ? 1 : 0)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, SettingsChrome.isMacDesktop ? 10 : 12)
        .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private var addRow: some View {
        Button {
            if options.count >= DurationOptionList.maxCount {
                showCapacityAlert = true
            } else {
                openEditor(EditorSession(mode: .add))
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: AppSymbols.Action.add)
                Text("settings.duration.add")
                Spacer()
            }
            .font(.body)
            .foregroundStyle(Color.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityHint(Text("settings.duration.add.hint"))
    }

    private func applyEnabled(_ enabled: Bool) {
        switch kind {
        case .autoLock:
            persist(PreferencesPatch(appLockEnabled: enabled))
        case .clipboardClear:
            persist(PreferencesPatch(clipboardClearEnabled: enabled))
        }
    }

    private func applySelection(_ seconds: Int) {
        switch kind {
        case .autoLock:
            persist(PreferencesPatch(appLockEnabled: true, autoLockSeconds: seconds))
        case .clipboardClear:
            persist(PreferencesPatch(clipboardClearEnabled: true, clipboardClearSeconds: seconds))
        }
    }

    private func applyRemoval(_ seconds: Int) {
        let result = DurationOptionList.removing(seconds, from: options, selected: selectedSeconds)
        switch kind {
        case .autoLock:
            persist(PreferencesPatch(
                appLockEnabled: result.selected == nil ? false : prefs.appLockEnabled,
                autoLockSeconds: result.selected ?? prefs.autoLockSeconds,
                autoLockDurationOptions: result.options
            ))
        case .clipboardClear:
            persist(PreferencesPatch(
                clipboardClearEnabled: result.selected == nil ? false : prefs.clipboardClearEnabled,
                clipboardClearSeconds: result.selected ?? prefs.clipboardClearSeconds,
                clipboardClearDurationOptions: result.options
            ))
        }
    }

    private func applyEditor(_ session: EditorSession, hours: Int, minutes: Int, seconds: Int) {
        let total = DurationOptionList.total(hours: hours, minutes: minutes, seconds: seconds)
        let outcome: DurationOptionList.AddResult
        switch session.mode {
        case .add:
            outcome = DurationOptionList.adding(total, to: options)
        case .edit(let old):
            outcome = DurationOptionList.replacing(old, with: total, in: options)
        }
        switch outcome {
        case .atCapacity:
            showCapacityAlert = true
        case .added(let next, let selected), .selectedExisting(let next, let selected):
            switch kind {
            case .autoLock:
                persist(PreferencesPatch(
                    appLockEnabled: prefs.appLockEnabled || options.isEmpty,
                    autoLockSeconds: selected,
                    autoLockDurationOptions: next
                ))
            case .clipboardClear:
                persist(PreferencesPatch(
                    clipboardClearEnabled: prefs.clipboardClearEnabled || options.isEmpty,
                    clipboardClearSeconds: selected,
                    clipboardClearDurationOptions: next
                ))
            }
        }
    }
}

private struct EditorSession: Identifiable {
    enum Mode: Equatable {
        case add
        case edit(Int)
    }

    let id = UUID()
    let mode: Mode

    var initialTotal: Int {
        switch mode {
        case .add: return 60
        case .edit(let seconds): return seconds
        }
    }
}

private enum DurationColumn: Hashable {
    case hours, minutes, seconds
}

/// 时长编辑页。关闭路径对齐「设主密码」：`navigationDestination` 推入；
/// 返回 = 取消（不写偏好）；底部「完成」= 写入后 `dismiss()`。
private struct DurationEditorPage: View {
    let session: EditorSession
    let onConfirm: (Int, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    /// 正在就地编辑的那一列；`nil` = 全是轮盘 / 步进器。
    @State private var editingColumn: DurationColumn?
    @State private var draftText = ""
    @FocusState private var fieldFocused: Bool

    init(
        session: EditorSession,
        onConfirm: @escaping (Int, Int, Int) -> Void
    ) {
        self.session = session
        self.onConfirm = onConfirm
        let parts = DurationOptionList.components(session.initialTotal)
        _hours = State(initialValue: parts.hours)
        _minutes = State(initialValue: parts.minutes)
        _seconds = State(initialValue: parts.seconds)
    }

    var body: some View {
        SettingsSubpage(title: editorTitle) {
            // 底层铺满可点区域：点卡片/按钮以外的灰色处 → 回到轮盘。
            ZStack(alignment: .top) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 640)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        endInlineEditing()
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 22) {
                    SettingsCard {
                        HStack(spacing: 0) {
                            durationColumn(
                                .hours,
                                value: $hours,
                                range: 0...DurationOptionList.maxHours,
                                label: "settings.duration.unit.hour"
                            )
                            durationColumn(
                                .minutes,
                                value: $minutes,
                                range: 0...DurationOptionList.maxMinutes,
                                label: "settings.duration.unit.minute"
                            )
                            durationColumn(
                                .seconds,
                                value: $seconds,
                                range: 0...DurationOptionList.maxSecondsComponent,
                                label: "settings.duration.unit.second"
                            )
                        }
                        .frame(minHeight: 200)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                    }

                    SettingsPrimaryButton(title: "settings.done") {
                        endInlineEditing()
                        onConfirm(hours, minutes, seconds)
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("settings.done") {
                    endInlineEditing()
                }
            }
        }
        #endif
        .onChange(of: editingColumn) { _, column in
            if column != nil {
                DispatchQueue.main.async { fieldFocused = true }
            } else {
                fieldFocused = false
            }
        }
        .onChange(of: fieldFocused) { _, focused in
            // 失焦（点别处、滚走键盘）落盘并回到轮盘；点返回不会走到 onConfirm。
            guard !focused, editingColumn != nil else { return }
            commitEditingColumn()
        }
    }

    private var editorTitle: LocalizedStringKey {
        switch session.mode {
        case .add: return "settings.duration.add"
        case .edit: return "settings.duration.edit"
        }
    }

    /// 结束就地数字编辑，回到轮盘 / 步进器。回车、点空白、键盘「完成」共用。
    private func endInlineEditing() {
        guard editingColumn != nil else { return }
        commitEditingColumn()
        fieldFocused = false
    }

    private func durationColumn(
        _ column: DurationColumn,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        label: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 4) {
            ZStack {
                if editingColumn == column {
                    inlineField(column: column, value: value, range: range)
                } else {
                    #if os(iOS)
                    Picker(label, selection: value) {
                        ForEach(Array(range), id: \.self) { item in
                            Text("\(item)").tag(item)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            beginEditing(column, value: value.wrappedValue)
                        }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                            beginEditing(column, value: value.wrappedValue)
                        }
                    )
                    // 正在编辑另一列时，点这列轮盘也先收起编辑。
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if editingColumn != nil, editingColumn != column {
                                endInlineEditing()
                            }
                        }
                    )
                    #else
                    VStack(spacing: 8) {
                        Text("\(value.wrappedValue)")
                            .font(.title2.monospacedDigit().weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(SettingsChrome.fieldFill(colorScheme))
                            )
                            .onTapGesture(count: 2) {
                                beginEditing(column, value: value.wrappedValue)
                            }
                            .onLongPressGesture(minimumDuration: 0.4) {
                                beginEditing(column, value: value.wrappedValue)
                            }
                            .onTapGesture {
                                if editingColumn != nil, editingColumn != column {
                                    endInlineEditing()
                                }
                            }
                        Stepper(label, value: value, in: range)
                            .labelsHidden()
                    }
                    #endif
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture {
                    endInlineEditing()
                }
        }
    }

    private func inlineField(
        column: DurationColumn,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        TextField("", text: $draftText)
            .font(.title2.monospacedDigit().weight(.semibold))
            .multilineTextAlignment(.center)
            .focused($fieldFocused)
            #if os(iOS)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsChrome.fieldFill(colorScheme))
            )
            .onChange(of: draftText) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                if digits != newValue {
                    draftText = digits
                    return
                }
                guard let parsed = Int(digits) else { return }
                value.wrappedValue = min(max(parsed, range.lowerBound), range.upperBound)
            }
            .onSubmit {
                endInlineEditing()
            }
            .accessibilityLabel(Text(accessibilityLabel(for: column)))
    }

    private func accessibilityLabel(for column: DurationColumn) -> LocalizedStringKey {
        switch column {
        case .hours: return "settings.duration.unit.hour"
        case .minutes: return "settings.duration.unit.minute"
        case .seconds: return "settings.duration.unit.second"
        }
    }

    private func beginEditing(_ column: DurationColumn, value: Int) {
        if editingColumn != nil, editingColumn != column {
            commitEditingColumn()
        }
        draftText = "\(value)"
        editingColumn = column
    }

    private func commitEditingColumn() {
        guard let column = editingColumn else { return }
        let range: ClosedRange<Int>
        switch column {
        case .hours: range = 0...DurationOptionList.maxHours
        case .minutes: range = 0...DurationOptionList.maxMinutes
        case .seconds: range = 0...DurationOptionList.maxSecondsComponent
        }
        let parsed = Int(draftText.filter(\.isNumber)) ?? range.lowerBound
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        switch column {
        case .hours: hours = clamped
        case .minutes: minutes = clamped
        case .seconds: seconds = clamped
        }
        editingColumn = nil
        draftText = ""
    }
}