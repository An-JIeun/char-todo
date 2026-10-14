import SwiftUI
import UniformTypeIdentifiers

/// 할일 한 줄: 체크박스, 제목, 메타, 세부 테스크 펼치기
struct TodoRowView: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    @Environment(CalendarService.self) private var calendar
    let todo: TodoItem
    var compact = false
    var showDate = false
    var showQuadrant = true

    @State private var expanded = false
    @State private var newSubtask = ""
    @State private var editing = false
    @State private var hovering = false
    @State private var splitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                RetroCheckbox(isOn: todo.isDone, tint: theme.quadrantColor(todo.quadrant), size: compact ? 15 : 18) {
                    store.toggle(todo.id)
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(todo.title)
                        .font(theme.font(compact ? 12 : 13.5, .semibold))
                        .strikethrough(todo.isDone, color: theme.textMuted)
                        .foregroundStyle(todo.isDone ? theme.textMuted : theme.text)
                        .lineLimit(compact ? 2 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !compact || !todo.subtasks.isEmpty || !todo.tags.isEmpty { metaRow }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editing = true }

                Spacer(minLength: 2)

                if !compact && (hovering || expanded) {
                    IconButton(symbol: "pencil", help: "편집") { editing = true }
                }
                if !compact || !todo.subtasks.isEmpty {
                    IconButton(symbol: expanded ? "chevron.up" : "chevron.down", help: "세부 테스크", size: 10) {
                        withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                    }
                }
            }

            if expanded { subtaskList.padding(.leading, compact ? 20 : 26) }
        }
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 5 : 8)
        .background(
            RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3))
                .fill(hovering ? theme.surfaceAlt : theme.surface)
        )
        .overlay(alignment: .leading) {
            if let q = todo.quadrant, showQuadrant {
                RoundedRectangle(cornerRadius: 2).fill(theme.quadrantColor(q)).frame(width: 3.5).padding(.vertical, 5)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3))
                .strokeBorder(theme.border.opacity(hovering ? 0.8 : 0.35), lineWidth: 1.2)
        )
        .onHover { hovering = $0 }
        .draggable(todo.id.uuidString) {
            Text(todo.title)
                .font(theme.font(12, .bold))
                .padding(6)
                .background(theme.highlight)
        }
        .contextMenu { TodoContextMenu(todo: todo, onEdit: { editing = true }) }
        .sheet(isPresented: $editing) {
            TodoEditorSheet(original: todo)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 4) {
            if showDate {
                Chip(text: dateLabel, symbol: "calendar")
            }
            if let start = todo.scheduledStart {
                Chip(text: DateFormatters.time.string(from: start), symbol: "clock.fill", color: theme.accent2)
            }
            if let q = todo.quadrant, showQuadrant, !compact {
                Chip(text: "\(q.shortLabel) \(q.title)", color: theme.quadrantColor(q))
            }
            let p = todo.subtaskProgress
            if p.total > 0 {
                HStack(spacing: 4) {
                    SegmentedProgress(value: Double(p.done) / Double(p.total), segments: min(8, max(3, p.total)), tint: theme.accent2, height: 8)
                        .frame(width: CGFloat(min(8, max(3, p.total))) * 7)
                    Text("\(p.done)/\(p.total)").font(theme.font(10, .bold)).foregroundStyle(theme.textMuted)
                }
            }
            if todo.calendarEventID != nil {
                Image(systemName: "calendar.badge.checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.accent2)
            }
            if !todo.notes.trimmed.isEmpty {
                Image(systemName: "note.text").font(.system(size: 10)).foregroundStyle(theme.textMuted)
            }
            if let link = todo.link, let url = URL(string: link) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Chip(text: todo.isCareerJob ? "공고" : "링크", symbol: "link", color: theme.accent2)
                }
                .buttonStyle(.plain)
                .help(link)
            }
            ForEach(todo.tags, id: \.self) { tag in
                Button {
                    AppEnvironment.shared.openTag(tag)
                } label: {
                    Chip(text: "#\(tag)", color: AppEnvironment.shared.tagColor(tag))
                }
                .buttonStyle(.plain)
                .help("#\(tag) 할일 모아보기")
            }
        }
    }

    private var dateLabel: String {
        switch todo.scope {
        case .day: DateFormatters.monthDay.string(from: todo.date)
        case .week: "\(DateFormatters.monthDay.string(from: todo.date)) 주"
        case .month: DateFormatters.yearMonth.string(from: todo.date)
        }
    }

    private var subtaskList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(todo.subtasks) { sub in
                HStack(spacing: 7) {
                    RetroCheckbox(isOn: sub.isDone, tint: theme.accent2, size: 14) {
                        store.toggleSubtask(todo.id, sub.id)
                    }
                    Text(sub.title)
                        .font(theme.font(12))
                        .strikethrough(sub.isDone)
                        .foregroundStyle(sub.isDone ? theme.textMuted : theme.text)
                    Spacer()
                    IconButton(symbol: "xmark", help: "삭제", size: 8) { store.removeSubtask(todo.id, sub.id) }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.textMuted)
                TextField("세부 테스크 추가", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .font(theme.font(12))
                    .onSubmit {
                        store.addSubtask(todo.id, title: newSubtask)
                        newSubtask = ""
                    }
                if !compact {
                    Button {
                        splitWithAI()
                    } label: {
                        if splitting { ProgressView().controlSize(.mini) } else { Label("AI로 쪼개기", systemImage: "wand.and.stars") }
                    }
                    .buttonStyle(.retro(.ghost, compact: true))
                    .disabled(splitting)
                }
            }
        }
    }

    private func splitWithAI() {
        splitting = true
        Task {
            defer { splitting = false }
            do {
                let text = try await AppEnvironment.shared.chat.oneShot(PromptBuilder.subtaskPrompt(for: todo))
                let items = PromptBuilder.parseList(text)
                store.addSubtasks(todo.id, titles: Array(items.prefix(8)))
                if items.isEmpty { AppEnvironment.shared.companion.say("쪼개기에 실패했어요 😢") }
            } catch {
                AppEnvironment.shared.companion.say(error.localizedDescription, duration: 6)
            }
        }
    }
}

struct TodoContextMenu: View {
    @Environment(TodoStore.self) private var store
    @Environment(CalendarService.self) private var calendar
    let todo: TodoItem
    var onEdit: () -> Void

    var body: some View {
        Button("편집…", action: onEdit)
        Button(todo.isDone ? "미완료로 표시" : "완료로 표시") { store.toggle(todo.id) }
        Divider()
        Menu("사분면") {
            ForEach(Quadrant.allCases) { q in
                Button("\(q.shortLabel) \(q.title) (\(q.subtitle))") { store.setQuadrant(todo.id, q) }
            }
            Button("미분류") { store.setQuadrant(todo.id, nil) }
        }
        Menu("태그") {
            ForEach(store.allTags, id: \.self) { tag in
                Button {
                    store.toggleTag(todo.id, tag)
                } label: {
                    if todo.tags.contains(tag) { Label("#\(tag)", systemImage: "checkmark") } else { Text("#\(tag)") }
                }
            }
            if !store.allTags.isEmpty { Divider() }
            Button("새 태그는 편집 창이나 빠른 입력 #태그로 추가", action: onEdit)
        }
        Menu("옮기기") {
            Button("오늘") { store.move(todo.id, to: Date(), scope: .day) }
            Button("내일") { store.move(todo.id, to: Date().adding(days: 1), scope: .day) }
            Button("다음 주 월요일") { store.move(todo.id, to: Date().startOfWeek.adding(weeks: 1), scope: .day) }
            Divider()
            Button("이번 주 목표로") { store.move(todo.id, to: Date(), scope: .week) }
            Button("이번 달 목표로") { store.move(todo.id, to: Date(), scope: .month) }
        }
        if todo.link != nil || todo.isCareerJob {
            Divider()
            if let link = todo.link, let url = URL(string: link) {
                Button(todo.isCareerJob ? "공고 페이지 열기" : "링크 열기") { NSWorkspace.shared.open(url) }
            }
            if todo.isCareerJob {
                Button("career-support에서 보기") { AppEnvironment.shared.career.open(.jobs) }
            }
        }
        if calendar.enabled && calendar.canWrite {
            Divider()
            if todo.calendarEventID == nil {
                Button("캘린더에 추가") { AppEnvironment.shared.linkToCalendar(todo.id) }
            } else {
                Button("캘린더에서 제거") { AppEnvironment.shared.unlinkFromCalendar(todo.id) }
            }
        }
        Divider()
        Button("삭제", role: .destructive) { store.delete(todo.id) }
    }
}

/// 빠른 입력 바: 문법 힌트 포함
struct QuickAddBar: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    var placeholder = "할일 추가…  (!1~!4 사분면 · @내일 · ~14:00 · #태그 · 제목 > 세부1, 세부2)"
    var defaultDate: Date
    var defaultScope: TodoScope = .day
    var defaultQuadrant: Quadrant?
    var defaultTags: [String] = []
    var compact = false

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.square.fill")
                .font(.system(size: compact ? 13 : 16, weight: .bold))
                .foregroundStyle(theme.accent)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(theme.font(compact ? 12 : 13.5))
                .focused($focused)
                .onSubmit(submit)
            if !text.isEmpty && !compact {
                preview
            }
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 6 : 10)
        .background(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 2)).fill(theme.isDark ? theme.background : Color.white.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 2))
            .strokeBorder(focused ? theme.accent : theme.border, lineWidth: theme.borderWidth))
    }

    private var preview: some View {
        let r = QuickAddParser().parse(text)
        return HStack(spacing: 4) {
            if let q = r.quadrant { Chip(text: q.shortLabel, color: theme.quadrantColor(q), filled: true) }
            if let d = r.date { Chip(text: DateFormatters.monthDay.string(from: d), symbol: "calendar") }
            if let t = r.time { Chip(text: DateFormatters.time.string(from: t), symbol: "clock") }
            if let s = r.scope { Chip(text: s.label) }
            if !r.subtasks.isEmpty { Chip(text: "세부 \(r.subtasks.count)", symbol: "list.bullet") }
            ForEach(r.tags, id: \.self) { t in Chip(text: "#\(t)", color: AppEnvironment.shared.tagColor(t)) }
        }
    }

    private func submit() {
        guard var item = QuickAddParser().makeTodo(from: text, defaultDate: defaultDate, defaultScope: defaultScope) else { return }
        if item.quadrant == nil { item.quadrant = defaultQuadrant }
        item.tags = Tag.normalizeList(defaultTags + item.tags)
        store.add(item)
        text = ""
        focused = true
    }
}

/// 드롭으로 할일을 옮길 때 쓰는 헬퍼
extension View {
    func todoDropTarget(isTargeted: Binding<Bool>? = nil, perform: @escaping (UUID) -> Void) -> some View {
        dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(UUID.init(uuidString:))
            ids.forEach(perform)
            return !ids.isEmpty
        } isTargeted: { isTargeted?.wrappedValue = $0 }
    }
}
