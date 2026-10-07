import Foundation
import Observation

enum TodoMutation {
    case added(TodoItem)
    case updated(old: TodoItem, new: TodoItem)
    case deleted(TodoItem)
}

/// 매트릭스 화면에서 보여줄 범위
enum MatrixRange: String, CaseIterable, Identifiable {
    case today, week, month, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: "오늘"
        case .week: "이번 주"
        case .month: "이번 달"
        case .all: "전체"
        }
    }
}

private struct StoreFile: Codable {
    var version = 1
    var todos: [TodoItem]
    var journals: [JournalEntry]
}

@MainActor
@Observable
final class TodoStore {
    private(set) var todos: [TodoItem] = []
    private(set) var journals: [JournalEntry] = []
    /// 할일을 완료할 때마다 증가 (캐릭터 축하 모션 트리거)
    private(set) var completionTick = 0

    @ObservationIgnored var onMutation: ((TodoMutation) -> Void)?
    @ObservationIgnored private let saver = Debouncer(delay: 0.4)
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let fileName = "data.json"

    init(persists: Bool = true) {
        self.persists = persists
        if persists, let file = Persistence.load(StoreFile.self, from: fileName) {
            todos = file.todos
            journals = file.journals
        } else if persists {
            seedSample()
        }
    }

    // MARK: - 조회

    func todo(id: UUID) -> TodoItem? { todos.first { $0.id == id } }

    func todos(on day: Date) -> [TodoItem] {
        todos.filter { $0.scope == .day && $0.date.isSameDay(as: day) }.sortedForDisplay()
    }

    func weekGoals(for date: Date) -> [TodoItem] {
        let start = date.startOfWeek
        return todos.filter { $0.scope == .week && $0.date == start }.sortedForDisplay()
    }

    func monthGoals(for date: Date) -> [TodoItem] {
        let start = date.startOfMonth
        return todos.filter { $0.scope == .month && $0.date == start }.sortedForDisplay()
    }

    /// 지난 날짜의 미완료 하루 할일
    func overdue(now: Date = Date()) -> [TodoItem] {
        todos.filter { $0.scope == .day && $0.isOverdue(relativeTo: now) }
            .sorted { $0.date < $1.date }
    }

    func completed(on day: Date) -> [TodoItem] {
        todos.filter { t in
            guard t.isDone, let c = t.completedAt else { return false }
            return c.isSameDay(as: day)
        }.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    /// 매트릭스 대상: 선택 범위에 해당하는 할일 (미완료 + 오늘 완료한 것)
    func matrixItems(range: MatrixRange, now: Date = Date()) -> [TodoItem] {
        let base = todos.filter { !$0.isDone || ($0.completedAt?.isSameDay(as: now) ?? false) }
        switch range {
        case .today:
            return base.filter { t in
                (t.scope == .day && (t.date.isSameDay(as: now) || t.isOverdue(relativeTo: now)))
                    || (t.scope == .week && t.date == now.startOfWeek)
            }
        case .week:
            return base.filter { t in
                switch t.scope {
                case .day: t.date.isSameWeek(as: now) || t.isOverdue(relativeTo: now)
                case .week: t.date == now.startOfWeek
                case .month: t.date == now.startOfMonth
                }
            }
        case .month:
            return base.filter { t in t.date.isSameMonth(as: now) || t.isOverdue(relativeTo: now) }
        case .all:
            return base
        }
    }

    // MARK: - 변경

    func add(_ item: TodoItem) {
        var item = item
        item.date = item.scope.normalize(item.date)
        todos.append(item)
        onMutation?(.added(item))
        persist()
    }

    func update(_ item: TodoItem) {
        guard let i = todos.firstIndex(where: { $0.id == item.id }) else { return }
        let old = todos[i]
        var new = item
        new.date = new.scope.normalize(new.date)
        if new.isDone && !old.isDone {
            new.completedAt = Date()
            completionTick += 1
        } else if !new.isDone {
            new.completedAt = nil
        }
        guard new != old else { return }
        todos[i] = new
        onMutation?(.updated(old: old, new: new))
        persist()
    }

    func mutate(_ id: UUID, _ change: (inout TodoItem) -> Void) {
        guard var item = todo(id: id) else { return }
        change(&item)
        update(item)
    }

    func delete(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        let removed = todos.remove(at: i)
        onMutation?(.deleted(removed))
        persist()
    }

    func toggle(_ id: UUID) {
        mutate(id) { t in
            t.isDone.toggle()
            if t.isDone {
                for i in t.subtasks.indices { t.subtasks[i].isDone = true }
            }
        }
    }

    func toggleSubtask(_ todoID: UUID, _ subID: UUID) {
        mutate(todoID) { t in
            guard let i = t.subtasks.firstIndex(where: { $0.id == subID }) else { return }
            t.subtasks[i].isDone.toggle()
            let allDone = t.subtasks.allSatisfy(\.isDone)
            if allDone && !t.isDone { t.isDone = true }
            if !allDone && t.isDone { t.isDone = false }
        }
    }

    func addSubtask(_ todoID: UUID, title: String) {
        let title = title.trimmed
        guard !title.isEmpty else { return }
        mutate(todoID) { t in
            t.subtasks.append(SubTask(title: title))
            t.isDone = false
        }
    }

    func addSubtasks(_ todoID: UUID, titles: [String]) {
        let clean = titles.map(\.trimmed).filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        mutate(todoID) { t in
            t.subtasks.append(contentsOf: clean.map { SubTask(title: $0) })
            t.isDone = false
        }
    }

    func removeSubtask(_ todoID: UUID, _ subID: UUID) {
        mutate(todoID) { t in t.subtasks.removeAll { $0.id == subID } }
    }

    func setQuadrant(_ id: UUID, _ q: Quadrant?) {
        mutate(id) { $0.quadrant = q }
    }

    /// 다른 날짜/범위로 옮긴다.
    func move(_ id: UUID, to date: Date, scope: TodoScope? = nil) {
        mutate(id) { t in
            if let scope { t.scope = scope }
            t.date = t.scope.normalize(date)
        }
    }

    func moveOverdueToToday() {
        for t in overdue() { move(t.id, to: Date()) }
    }

    // MARK: - 태그

    struct TagStat: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let open: Int
        let total: Int
    }

    /// 모든 태그와 개수 (미완료 많은 순 → 이름순)
    var tagStats: [TagStat] {
        var open: [String: Int] = [:], total: [String: Int] = [:]
        for t in todos {
            for tag in t.tags {
                total[tag, default: 0] += 1
                if !t.isDone { open[tag, default: 0] += 1 }
            }
        }
        return total.keys.map { TagStat(name: $0, open: open[$0] ?? 0, total: total[$0] ?? 0) }
            .sorted { ($0.open, $1.name) > ($1.open, $0.name) }
    }

    var allTags: [String] { tagStats.map(\.name).sorted() }

    /// tag가 nil이면 태그 없는 할일
    func todos(tag: String?) -> [TodoItem] {
        guard let tag else { return todos.filter { $0.tags.isEmpty } }
        return todos.filter { $0.tags.contains(tag) }
    }

    func toggleTag(_ id: UUID, _ tag: String) {
        let tag = Tag.normalize(tag)
        guard !tag.isEmpty else { return }
        mutate(id) { t in
            if let i = t.tags.firstIndex(of: tag) { t.tags.remove(at: i) } else { t.tags.append(tag) }
        }
    }

    /// 태그 이름 바꾸기. 이미 있는 이름이면 합친다.
    func renameTag(_ old: String, to new: String) {
        let new = Tag.normalize(new)
        guard !new.isEmpty, new != old else { return }
        for t in todos where t.tags.contains(old) {
            mutate(t.id) { item in
                item.tags = Tag.normalizeList(item.tags.map { $0 == old ? new : $0 })
            }
        }
    }

    func deleteTag(_ tag: String) {
        for t in todos where t.tags.contains(tag) {
            mutate(t.id) { $0.tags.removeAll { $0 == tag } }
        }
    }

    // MARK: - 업무일지

    func journal(for day: Date) -> JournalEntry {
        journals.first { $0.date.isSameDay(as: day) } ?? JournalEntry(date: day)
    }

    func hasJournal(on day: Date) -> Bool {
        journals.contains { $0.date.isSameDay(as: day) && !$0.isEmpty }
    }

    func saveJournal(_ entry: JournalEntry) {
        var entry = entry
        entry.updatedAt = Date()
        if let i = journals.firstIndex(where: { $0.id == entry.id || $0.date.isSameDay(as: entry.date) }) {
            entry.id = journals[i].id
            guard journals[i] != entry else { return }
            journals[i] = entry
        } else {
            guard !entry.isEmpty else { return }
            journals.append(entry)
        }
        journals.sort { $0.date > $1.date }
        persist()
    }

    func deleteJournal(_ id: UUID) {
        journals.removeAll { $0.id == id }
        persist()
    }

    // MARK: - 저장

    private func persist() {
        guard persists else { return }
        saver.schedule { [weak self] in self?.writeNow() }
    }

    func writeNow() {
        guard persists else { return }
        Persistence.save(StoreFile(todos: todos, journals: journals), to: fileName)
    }

    func replaceAll(todos: [TodoItem], journals: [JournalEntry]) {
        self.todos = todos
        self.journals = journals
        persist()
    }

    private func seedSample() {
        let today = Date()
        var report = TodoItem(title: "주간 보고서 작성", date: today, quadrant: .doFirst)
        report.subtasks = [SubTask(title: "지표 정리"), SubTask(title: "초안 쓰기"), SubTask(title: "팀장님 리뷰 요청")]
        todos = [
            report,
            TodoItem(title: "CharTodo 둘러보기 👀", date: today, quadrant: .schedule),
            TodoItem(title: "메일함 정리", date: today, quadrant: .delegate),
            TodoItem(title: "이번 주 운동 3회", scope: .week, date: today, quadrant: .schedule),
            TodoItem(title: "이번 달 책 한 권 읽기", scope: .month, date: today, quadrant: .schedule),
        ]
        writeNow()
    }
}
