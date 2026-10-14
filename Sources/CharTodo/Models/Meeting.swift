import Foundation

/// 지식그래프 노드 종류. 회의 안에서만 의미 있는 것(안건·결정·할일)과
/// 여러 회의에 걸쳐 이름으로 합쳐지는 개체(사람·프로젝트 등)로 나뉜다.
enum KGNodeKind: String, Codable, CaseIterable, Identifiable {
    case meeting, topic, decision, action
    case person, project, system, org, concept

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meeting: "회의"
        case .topic: "안건"
        case .decision: "결정"
        case .action: "할일"
        case .person: "사람"
        case .project: "프로젝트"
        case .system: "시스템"
        case .org: "조직"
        case .concept: "개념"
        }
    }

    var symbol: String {
        switch self {
        case .meeting: "person.3.fill"
        case .topic: "text.bubble.fill"
        case .decision: "checkmark.seal.fill"
        case .action: "checklist"
        case .person: "person.fill"
        case .project: "folder.fill"
        case .system: "cpu.fill"
        case .org: "building.2.fill"
        case .concept: "lightbulb.fill"
        }
    }

    var hex: String {
        switch self {
        case .meeting: "#EE9A6C"
        case .topic: "#6FA8C9"
        case .decision: "#8BB174"
        case .action: "#EDAA45"
        case .person: "#E58A9C"
        case .project: "#A98BC9"
        case .system: "#5FB3A1"
        case .org: "#C99A6B"
        case .concept: "#7C93D6"
        }
    }

    /// 여러 회의에 걸쳐 이름으로 합쳐지는 개체인지
    var isEntity: Bool {
        switch self {
        case .person, .project, .system, .org, .concept: true
        default: false
        }
    }

    /// LLM이 준 type 문자열 → 개체 종류 (모르는 값은 개념)
    static func entity(from raw: String) -> KGNodeKind {
        switch raw.lowercased().trimmed {
        case "person", "people", "사람", "인물": .person
        case "project", "프로젝트": .project
        case "system", "service", "tool", "product", "시스템", "서비스", "도구": .system
        case "org", "organization", "team", "조직", "팀", "부서": .org
        default: .concept
        }
    }
}

/// 회의에서 논의한 안건
struct MeetingTopic: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var points: [String] = []
}

/// 회의에서 나온 할일
struct MeetingAction: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var owner: String = ""
    var due: Date?
    /// 앱 할일로 등록했으면 그 할일 id
    var todoID: UUID?

    /// 앱 할일로 변환. 기한이 없으면 오늘 할일로 넣는다.
    func makeTodo(meeting: MeetingNote, now: Date = Date()) -> TodoItem {
        var notes = "회의록: \(meeting.title) (\(meeting.date.dayKey))"
        if !owner.trimmed.isEmpty { notes += "\n담당: \(owner.trimmed)" }
        return TodoItem(title: title, scope: .day, date: due ?? now, notes: notes, tags: ["회의"])
    }
}

struct MeetingEntity: Codable, Hashable {
    var name: String
    var kind: KGNodeKind
}

/// LLM이 뽑은 개체/안건 사이의 관계 (from —relation→ to)
struct MeetingRelation: Codable, Hashable {
    var from: String
    var relation: String
    var to: String
}

/// 회의록 한 건: 원문 + AI가 정리한 구조
struct MeetingNote: Identifiable, Codable, Hashable {
    enum Status: String, Codable { case pending, analyzed, failed }

    var id = UUID()
    var title: String
    var date: Date
    /// 가져온 파일 이름 (붙여넣기면 빈 문자열)
    var sourceName: String = ""
    var rawText: String
    var status: Status = .pending
    var errorMessage: String?

    var summary = ""
    var participants: [String] = []
    var topics: [MeetingTopic] = []
    var decisions: [String] = []
    var actions: [MeetingAction] = []
    var entities: [MeetingEntity] = []
    var relations: [MeetingRelation] = []

    var createdAt = Date()
    var analyzedAt: Date?

    init(title: String, date: Date, sourceName: String = "", rawText: String) {
        self.title = title
        self.date = date.startOfDay
        self.sourceName = sourceName
        self.rawText = rawText
    }

    enum CodingKeys: String, CodingKey {
        case id, title, date, sourceName, rawText, status, errorMessage, summary, participants, topics, decisions,
             actions, entities, relations, createdAt, analyzedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "회의록"
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date().startOfDay
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        rawText = try c.decodeIfPresent(String.self, forKey: .rawText) ?? ""
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .pending
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        participants = try c.decodeIfPresent([String].self, forKey: .participants) ?? []
        topics = try c.decodeIfPresent([MeetingTopic].self, forKey: .topics) ?? []
        decisions = try c.decodeIfPresent([String].self, forKey: .decisions) ?? []
        actions = try c.decodeIfPresent([MeetingAction].self, forKey: .actions) ?? []
        entities = try c.decodeIfPresent([MeetingEntity].self, forKey: .entities) ?? []
        relations = try c.decodeIfPresent([MeetingRelation].self, forKey: .relations) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        analyzedAt = try c.decodeIfPresent(Date.self, forKey: .analyzedAt)
    }

    /// 목록용 한 줄 요약: "안건 3 · 결정 2 · 할일 4"
    var countsLabel: String {
        var parts: [String] = []
        if !topics.isEmpty { parts.append("안건 \(topics.count)") }
        if !decisions.isEmpty { parts.append("결정 \(decisions.count)") }
        if !actions.isEmpty { parts.append("할일 \(actions.count)") }
        return parts.joined(separator: " · ")
    }

    func markdown() -> String {
        var out = "# \(title)\n\n"
        out += "- 날짜: \(DateFormatters.fullDate.string(from: date))\n"
        if !participants.isEmpty { out += "- 참석: \(participants.joined(separator: ", "))\n" }
        if !sourceName.isEmpty { out += "- 원본: \(sourceName)\n" }
        if !summary.trimmed.isEmpty { out += "\n## 요약\n\(summary.trimmed)\n" }
        if !topics.isEmpty {
            out += "\n## 안건\n"
            for t in topics {
                out += "### \(t.title)\n"
                for p in t.points { out += "- \(p)\n" }
            }
        }
        if !decisions.isEmpty {
            out += "\n## 결정사항\n" + decisions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if !actions.isEmpty {
            out += "\n## 할일\n"
            for a in actions {
                var line = "- [ ] \(a.title)"
                var meta: [String] = []
                if !a.owner.trimmed.isEmpty { meta.append("담당: \(a.owner)") }
                if let due = a.due { meta.append("기한: \(due.dayKey)") }
                if !meta.isEmpty { line += " (" + meta.joined(separator: ", ") + ")" }
                out += line + "\n"
            }
        }
        return out
    }
}
