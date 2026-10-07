import Foundation

struct TILNote: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String = ""
    var body: String = ""
    var tags: [String] = []
}

/// 하루 단위 업무일지 + TIL.
struct JournalEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    /// 오늘 한 일 (업무 내용)
    var work: String = ""
    /// 이슈 · 회고 · 메모
    var issues: String = ""
    /// 내일 할 일
    var plan: String = ""
    var tils: [TILNote] = []
    /// 1(😵) ~ 5(🤩)
    var mood: Int?
    var updatedAt = Date()

    init(date: Date) {
        self.date = date.startOfDay
    }

    var isEmpty: Bool {
        work.trimmed.isEmpty && issues.trimmed.isEmpty && plan.trimmed.isEmpty
            && tils.allSatisfy { $0.title.trimmed.isEmpty && $0.body.trimmed.isEmpty }
    }

    static let moods: [(Int, String, String)] = [
        (1, "😵", "번아웃"), (2, "😮‍💨", "지침"), (3, "🙂", "보통"), (4, "😄", "좋음"), (5, "🤩", "최고"),
    ]

    enum CodingKeys: String, CodingKey { case id, date, work, issues, plan, tils, mood, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date().startOfDay
        work = try c.decodeIfPresent(String.self, forKey: .work) ?? ""
        issues = try c.decodeIfPresent(String.self, forKey: .issues) ?? ""
        plan = try c.decodeIfPresent(String.self, forKey: .plan) ?? ""
        tils = try c.decodeIfPresent([TILNote].self, forKey: .tils) ?? []
        mood = try c.decodeIfPresent(Int.self, forKey: .mood)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// 마크다운으로 내보내기
    func markdown(completedTodos: [TodoItem] = []) -> String {
        var out = "# 업무일지 · \(DateFormatters.fullDate.string(from: date))\n\n"
        if let mood, let m = JournalEntry.moods.first(where: { $0.0 == mood }) {
            out += "컨디션: \(m.1) \(m.2)\n\n"
        }
        out += "## 오늘 한 일\n\(work.trimmed.isEmpty ? "-" : work.trimmed)\n\n"
        if !completedTodos.isEmpty {
            out += "### 완료한 할일\n"
            for t in completedTodos { out += "- [x] \(t.title)\n" }
            out += "\n"
        }
        out += "## 이슈 · 회고\n\(issues.trimmed.isEmpty ? "-" : issues.trimmed)\n\n"
        out += "## 내일 할 일\n\(plan.trimmed.isEmpty ? "-" : plan.trimmed)\n\n"
        let notes = tils.filter { !$0.title.trimmed.isEmpty || !$0.body.trimmed.isEmpty }
        if !notes.isEmpty {
            out += "## TIL (Today I Learned)\n"
            for n in notes {
                out += "### \(n.title.trimmed.isEmpty ? "메모" : n.title.trimmed)\n"
                if !n.tags.isEmpty { out += n.tags.map { "#\($0)" }.joined(separator: " ") + "\n\n" }
                out += "\(n.body.trimmed)\n\n"
            }
        }
        return out
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
