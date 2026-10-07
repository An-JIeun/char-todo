import SwiftUI

/// 태그별로 할일을 모아 보는 화면
struct TagsView: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    enum Selection: Hashable { case all, untagged, tag(String) }
    enum StatusFilter: String, CaseIterable { case open, all, done
        var label: String {
            switch self {
            case .open: "미완료"
            case .all: "전체"
            case .done: "완료"
            }
        }
    }

    @State private var selection: Selection = .all
    @State private var status: StatusFilter = .open
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            tagList.frame(width: 250)
            detail
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .onAppear {
            if let t = AppEnvironment.shared.pendingTag {
                selection = .tag(t)
                AppEnvironment.shared.pendingTag = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tagSelectRequest)) { note in
            if let t = note.object as? String { selection = .tag(t) }
            AppEnvironment.shared.pendingTag = nil
        }
        .alert("태그 이름 바꾸기", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("새 이름", text: $renameText)
            Button("취소", role: .cancel) { renaming = nil }
            Button("바꾸기") {
                if let old = renaming {
                    let new = Tag.normalize(renameText)
                    store.renameTag(old, to: new)
                    if let color = settings.settings.tagColors[old], !new.isEmpty {
                        settings.settings.tagColors[new] = settings.settings.tagColors[new] ?? color
                        settings.settings.tagColors[old] = nil
                    }
                    if selection == .tag(old), !new.isEmpty { selection = .tag(new) }
                }
                renaming = nil
            }
        } message: {
            Text("이미 있는 태그 이름을 입력하면 두 태그가 합쳐져요.")
        }
    }

    // MARK: 왼쪽 목록

    private var tagList: some View {
        let stats = store.tagStats
        return RetroWindow("TAGS", symbol: "tag.fill") {
            Text("\(stats.count)").font(theme.font(11, .heavy))
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    row(.all, title: "전체", color: theme.textMuted, symbol: "tray.full.fill",
                        open: store.todos.filter { !$0.isDone }.count, total: store.todos.count)
                    row(.untagged, title: "태그 없음", color: theme.textMuted, symbol: "tag.slash",
                        open: store.todos(tag: nil).filter { !$0.isDone }.count, total: store.todos(tag: nil).count)
                    Rectangle().fill(theme.border.opacity(0.3)).frame(height: 1).padding(.vertical, 4)
                    if stats.isEmpty {
                        Text("아직 태그가 없어요.\n할일에 #업무 처럼 붙여 보세요.")
                            .font(theme.font(11.5)).foregroundStyle(theme.textMuted)
                            .padding(8)
                    }
                    ForEach(stats) { stat in
                        row(.tag(stat.name), title: "#\(stat.name)", color: AppEnvironment.shared.tagColor(stat.name),
                            symbol: nil, open: stat.open, total: stat.total)
                            .contextMenu {
                                Button("이름 바꾸기…") { renameText = stat.name; renaming = stat.name }
                                Button("색 초기화") { settings.settings.tagColors[stat.name] = nil }
                                Divider()
                                Button("태그 삭제 (할일은 유지)", role: .destructive) {
                                    store.deleteTag(stat.name)
                                    settings.settings.tagColors[stat.name] = nil
                                    if selection == .tag(stat.name) { selection = .all }
                                }
                            }
                    }
                }
                .padding(8)
            }
        }
    }

    private func row(_ sel: Selection, title: String, color: Color, symbol: String?, open: Int, total: Int) -> some View {
        let selected = selection == sel
        return Button {
            selection = sel
        } label: {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(color).frame(width: 14)
                } else {
                    Circle().fill(color).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(theme.border.opacity(0.6), lineWidth: 1))
                        .frame(width: 14)
                }
                Text(title).font(theme.font(12.5, .bold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(open == total ? "\(total)" : "\(open)/\(total)")
                    .font(theme.font(10.5, .heavy))
                    .foregroundStyle(theme.textMuted)
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: max(3, theme.cornerRadius - 6)).fill(selected ? color.opacity(0.22) : .clear))
            .overlay(RoundedRectangle(cornerRadius: max(3, theme.cornerRadius - 6)).strokeBorder(selected ? theme.border : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .todoDropTarget { id in
            if case let .tag(name) = sel, store.todo(id: id)?.tags.contains(name) == false { store.toggleTag(id, name) }
        }
    }

    // MARK: 오른쪽 상세

    private var items: [TodoItem] {
        let base: [TodoItem] = switch selection {
        case .all: store.todos
        case .untagged: store.todos(tag: nil)
        case let .tag(name): store.todos(tag: name)
        }
        switch status {
        case .open: return base.filter { !$0.isDone }
        case .done: return base.filter(\.isDone)
        case .all: return base
        }
    }

    private var selectedTag: String? {
        if case let .tag(name) = selection { return name }
        return nil
    }

    private var detail: some View {
        let list = items
        let today = Date().startOfDay
        let open = list.filter { !$0.isDone }
        let overdue = open.filter { $0.isOverdue() }.sorted { $0.date < $1.date }
        let todayItems = list.filter { $0.scope == .day && $0.date.isSameDay(as: today) && !$0.isOverdue() }.sortedForDisplay()
        let upcoming = list.filter { $0.scope == .day && $0.date > today && !$0.isDone }.sorted { $0.date < $1.date }
        let goals = list.filter { $0.scope != .day && !$0.isOverdue() && !$0.isDone }.sorted { $0.date < $1.date }
        let done = list.filter { $0.isDone && !($0.scope == .day && $0.date.isSameDay(as: today)) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let all = store.todos(tag: selectedTag)
        let doneCount = selection == .all ? store.todos.filter(\.isDone).count : all.filter(\.isDone).count
        let totalCount = selection == .all ? store.todos.count : all.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(theme.titleFont(28)).foregroundStyle(theme.text)
                        if let tag = selectedTag {
                            ColorPicker("", selection: Binding(
                                get: { AppEnvironment.shared.tagColor(tag) },
                                set: { settings.settings.tagColors[tag] = $0.hexString }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            .help("태그 색 바꾸기")
                            Button { renameText = tag; renaming = tag } label: { Image(systemName: "pencil") }
                                .buttonStyle(.retro(.ghost, compact: true))
                                .help("이름 바꾸기")
                        }
                    }
                    HStack(spacing: 8) {
                        SegmentedProgress(value: totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount), segments: 14,
                                          tint: selectedTag.map { AppEnvironment.shared.tagColor($0) }, height: 12)
                            .frame(width: 180)
                        Text("\(doneCount)/\(totalCount) 완료").font(theme.font(12, .heavy)).foregroundStyle(theme.textMuted)
                    }
                }
                Spacer()
                RetroSegmented(options: StatusFilter.allCases, selection: $status) { $0.label }
                    .frame(width: 210)
            }

            QuickAddBar(placeholder: selectedTag.map { "#\($0) 할일 추가 (오늘)" } ?? "할일 추가 (#태그 로 분류)",
                        defaultDate: Date(), defaultTags: selectedTag.map { [$0] } ?? [])

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if list.isEmpty {
                        EmptyHint(text: status == .done ? "완료한 할일이 없어요" : "해당하는 할일이 없어요", symbol: "tag")
                            .padding(.top, 30)
                    }
                    group("밀린 할일", symbol: "exclamationmark.triangle.fill", items: overdue, tint: theme.quadrantColors[0])
                    group("오늘", symbol: "sun.max.fill", items: todayItems, tint: theme.accent)
                    group("예정", symbol: "calendar", items: upcoming, tint: theme.accent2)
                    group("주간 · 월간 목표", symbol: "flag.fill", items: goals, tint: theme.highlight)
                    group("완료", symbol: "checkmark.seal.fill", items: done, tint: theme.textMuted)
                }
                .padding(.bottom, 10)
            }
        }
    }

    private var title: String {
        switch selection {
        case .all: "전체 할일"
        case .untagged: "태그 없음"
        case let .tag(name): "#\(name)"
        }
    }

    @ViewBuilder
    private func group(_ title: String, symbol: String, items: [TodoItem], tint: Color) -> some View {
        if !items.isEmpty {
            RetroWindow("\(title) \(items.count)", symbol: symbol, tint: tint) {
                EmptyView()
            } content: {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { t in TodoRowView(todo: t, showDate: true) }
                }
                .padding(10)
            }
        }
    }
}
