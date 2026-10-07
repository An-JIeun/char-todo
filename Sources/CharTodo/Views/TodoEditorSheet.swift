import SwiftUI

/// 할일 상세 편집 시트 (새로 만들기 겸용)
struct TodoEditorSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(TodoStore.self) private var store
    @Environment(CalendarService.self) private var calendar

    let isNew: Bool
    @State private var draft: TodoItem
    @State private var hasTime: Bool
    @State private var newSubtask = ""
    @State private var linkCalendar: Bool
    @State private var splitting = false
    @State private var aiError: String?

    init(original: TodoItem, isNew: Bool = false) {
        self.isNew = isNew
        _draft = State(initialValue: original)
        _hasTime = State(initialValue: original.time != nil)
        _linkCalendar = State(initialValue: original.calendarEventID != nil)
    }

    var body: some View {
        RetroWindow(isNew ? "NEW_TODO.TXT" : "EDIT_TODO.TXT", symbol: "square.and.pencil") {
            Button { dismiss() } label: { Image(systemName: "xmark.square.fill") }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("제목") {
                        TextField("무엇을 할까요?", text: $draft.title).retroField()
                    }

                    HStack(alignment: .top, spacing: 16) {
                        field("범위") {
                            RetroSegmented(options: TodoScope.allCases, selection: $draft.scope) { $0.label }
                                .frame(width: 190)
                        }
                        field(draft.scope == .day ? "날짜" : draft.scope == .week ? "주 (아무 날짜)" : "월 (아무 날짜)") {
                            DatePicker("", selection: $draft.date, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                        }
                    }

                    if draft.scope == .day {
                        field("시간") {
                            HStack(spacing: 10) {
                                Toggle("시간 지정", isOn: $hasTime).toggleStyle(.switch).controlSize(.small)
                                if hasTime {
                                    DatePicker("", selection: Binding(
                                        get: { draft.time ?? defaultTime },
                                        set: { draft.time = $0 }
                                    ), displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    Stepper("\(draft.durationMinutes)분", value: $draft.durationMinutes, in: 15...480, step: 15)
                                        .font(theme.font(12))
                                }
                            }
                        }
                    }

                    field("아이젠하워 매트릭스") { quadrantPicker }

                    field("태그") {
                        TagEditor(tags: $draft.tags, placeholder: "태그 입력 후 Enter (예: 업무, 공부, 운동)",
                                  normalize: Tag.normalize, suggestions: store.allTags,
                                  chipColor: { AppEnvironment.shared.tagColor($0) })
                    }

                    field("세부 테스크") { subtasks }

                    field("메모") {
                        RetroTextEditor(text: $draft.notes, placeholder: "자세한 내용, 링크, 참고사항…", minHeight: 70)
                    }

                    if calendar.enabled && calendar.canWrite {
                        Toggle(isOn: $linkCalendar) {
                            Label("macOS 캘린더에 일정으로 추가", systemImage: "calendar.badge.plus")
                                .font(theme.font(12.5, .bold))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
                .padding(18)
            }
            footer
        }
        .frame(width: 540, height: 700)
        .padding(10)
        .background(theme.background)
        .onChange(of: hasTime) { _, on in draft.time = on ? (draft.time ?? defaultTime) : nil }
    }

    private var defaultTime: Date {
        AppCalendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(theme.font(11.5, .heavy)).foregroundStyle(theme.textMuted)
            content()
        }
    }

    private var quadrantPicker: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                HStack(spacing: 6) { quadrantCell(.doFirst); quadrantCell(.schedule) }
                HStack(spacing: 6) { quadrantCell(.delegate); quadrantCell(.eliminate) }
            }
            Button {
                draft.quadrant = nil
            } label: {
                Text("미분류").frame(height: 30)
            }
            .buttonStyle(.retro(draft.quadrant == nil ? .primary : .secondary, compact: true))
        }
    }

    private func quadrantCell(_ q: Quadrant) -> some View {
        let selected = draft.quadrant == q
        let color = theme.quadrantColor(q)
        return Button {
            draft.quadrant = q
        } label: {
            HStack(spacing: 6) {
                Image(systemName: q.symbol)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(q.shortLabel) \(q.title)").font(theme.font(11.5, .heavy))
                    Text(q.subtitle).font(theme.font(9.5))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: 160)
            .background(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3)).fill(selected ? color : color.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3)).strokeBorder(selected ? theme.border : color.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var subtasks: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($draft.subtasks) { $sub in
                HStack(spacing: 8) {
                    RetroCheckbox(isOn: sub.isDone, tint: theme.accent2, size: 15) { sub.isDone.toggle() }
                    TextField("", text: $sub.title).textFieldStyle(.plain).font(theme.font(12.5))
                    IconButton(symbol: "arrow.up", help: "위로", size: 9) { moveSub(sub.id, by: -1) }
                    IconButton(symbol: "trash", help: "삭제", size: 9) { draft.subtasks.removeAll { $0.id == sub.id } }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(theme.surfaceAlt))
            }
            HStack(spacing: 8) {
                TextField("세부 테스크 입력 후 Enter", text: $newSubtask)
                    .retroField()
                    .onSubmit(addSub)
                Button("추가", action: addSub).buttonStyle(.retro(.secondary, compact: true))
                Button {
                    splitWithAI()
                } label: {
                    if splitting { ProgressView().controlSize(.small) } else { Label("AI로 쪼개기", systemImage: "wand.and.stars") }
                }
                .buttonStyle(.retro(.accent2, compact: true))
                .disabled(splitting || draft.title.trimmed.isEmpty)
            }
            if let aiError {
                Text(aiError).font(theme.font(11)).foregroundStyle(Color.red)
            }
        }
    }

    private func addSub() {
        let t = newSubtask.trimmed
        guard !t.isEmpty else { return }
        draft.subtasks.append(SubTask(title: t))
        newSubtask = ""
    }

    private func moveSub(_ id: UUID, by delta: Int) {
        guard let i = draft.subtasks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard draft.subtasks.indices.contains(j) else { return }
        draft.subtasks.swapAt(i, j)
    }

    private func splitWithAI() {
        splitting = true
        aiError = nil
        let snapshot = draft
        Task {
            defer { splitting = false }
            do {
                let text = try await AppEnvironment.shared.chat.oneShot(PromptBuilder.subtaskPrompt(for: snapshot))
                let items = PromptBuilder.parseList(text)
                if items.isEmpty { aiError = "결과를 해석하지 못했어요: \(text.prefix(80))" }
                draft.subtasks.append(contentsOf: items.prefix(8).map { SubTask(title: $0) })
            } catch {
                aiError = error.localizedDescription
            }
        }
    }

    private var footer: some View {
        HStack {
            if !isNew {
                Button("삭제", role: .destructive) {
                    store.delete(draft.id)
                    dismiss()
                }
                .buttonStyle(.retro(.danger))
            }
            Spacer()
            Button("취소") { dismiss() }
                .buttonStyle(.retro(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "추가" : "저장", action: save)
                .buttonStyle(.retro(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmed.isEmpty)
        }
        .padding(12)
        .background(theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(theme.border.opacity(0.4)).frame(height: 1) }
    }

    private func save() {
        var item = draft
        item.title = item.title.trimmed
        item.subtasks = item.subtasks.filter { !$0.title.trimmed.isEmpty }
        item.tags = Tag.normalizeList(item.tags)
        if item.scope != .day { item.time = nil }
        if isNew { store.add(item) } else { store.update(item) }

        let env = AppEnvironment.shared
        if linkCalendar && item.calendarEventID == nil {
            env.linkToCalendar(item.id)
        } else if !linkCalendar && item.calendarEventID != nil {
            env.unlinkFromCalendar(item.id)
        }
        dismiss()
    }
}
