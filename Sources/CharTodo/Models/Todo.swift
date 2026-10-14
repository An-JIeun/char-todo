import Foundation

/// 할일이 속하는 기간 단위.
enum TodoScope: String, Codable, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "하루"
        case .week: "주간"
        case .month: "월간"
        }
    }

    /// 범위에 맞게 기준 날짜를 정규화한다.
    func normalize(_ date: Date) -> Date {
        switch self {
        case .day: date.startOfDay
        case .week: date.startOfWeek
        case .month: date.startOfMonth
        }
    }
}

/// 아이젠하워 매트릭스 사분면.
enum Quadrant: Int, Codable, CaseIterable, Identifiable {
    case doFirst = 1   // 긴급 + 중요
    case schedule = 2  // 중요, 긴급하지 않음
    case delegate = 3  // 긴급, 중요하지 않음
    case eliminate = 4 // 둘 다 아님

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .doFirst: "지금 하기"
        case .schedule: "계획하기"
        case .delegate: "위임하기"
        case .eliminate: "버리기"
        }
    }

    var subtitle: String {
        switch self {
        case .doFirst: "긴급 · 중요"
        case .schedule: "중요 · 덜 긴급"
        case .delegate: "긴급 · 덜 중요"
        case .eliminate: "덜 긴급 · 덜 중요"
        }
    }

    var shortLabel: String { "Q\(rawValue)" }

    var symbol: String {
        switch self {
        case .doFirst: "flame.fill"
        case .schedule: "calendar.badge.clock"
        case .delegate: "person.2.fill"
        case .eliminate: "trash.fill"
        }
    }

    var isUrgent: Bool { self == .doFirst || self == .delegate }
    var isImportant: Bool { self == .doFirst || self == .schedule }

    static func from(urgent: Bool, important: Bool) -> Quadrant {
        switch (urgent, important) {
        case (true, true): .doFirst
        case (false, true): .schedule
        case (true, false): .delegate
        case (false, false): .eliminate
        }
    }
}

struct SubTask: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var isDone = false
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var scope: TodoScope = .day
    /// 범위에 맞게 정규화된 기준 날짜 (하루: 그 날 0시, 주간: 주 시작일, 월간: 1일)
    var date: Date
    /// 선택적 시각 (하루 할일에서 캘린더 연동 시 사용)
    var time: Date?
    var durationMinutes: Int = 60
    var quadrant: Quadrant?
    var subtasks: [SubTask] = []
    var isDone = false
    var completedAt: Date?
    var createdAt = Date()
    /// 연동된 macOS 캘린더 이벤트 식별자
    var calendarEventID: String?
    /// 분류용 태그 (# 없이 저장)
    var tags: [String] = []
    /// 관련 웹 링크 (예: 채용 공고)
    var link: String?
    /// 외부에서 가져온 할일의 출처 키 (예: "career:<공고 링크>") — 동기화 때 같은 항목을 찾는 데 쓴다
    var sourceKey: String?

    init(title: String, scope: TodoScope = .day, date: Date = Date(), time: Date? = nil,
         quadrant: Quadrant? = nil, subtasks: [SubTask] = [], notes: String = "", tags: [String] = []) {
        self.title = title
        self.scope = scope
        self.date = scope.normalize(date)
        self.time = time
        self.quadrant = quadrant
        self.subtasks = subtasks
        self.notes = notes
        self.tags = Tag.normalizeList(tags)
    }

    /// career-support 공고에서 가져온 할일
    var isCareerJob: Bool { sourceKey?.hasPrefix("career:") == true }

    var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }

    var progress: Double {
        if isDone { return 1 }
        let p = subtaskProgress
        guard p.total > 0 else { return 0 }
        return Double(p.done) / Double(p.total)
    }

    /// 시각이 있으면 날짜+시각, 없으면 nil
    var scheduledStart: Date? {
        guard scope == .day, let time else { return nil }
        return date.combining(time: time)
    }

    func isOverdue(relativeTo now: Date = Date()) -> Bool {
        guard !isDone else { return false }
        switch scope {
        case .day: return date < now.startOfDay
        case .week: return date < now.startOfWeek
        case .month: return date < now.startOfMonth
        }
    }

    // 이후 버전에서 필드가 추가돼도 기존 데이터가 깨지지 않도록 관대한 디코딩.
    enum CodingKeys: String, CodingKey {
        case id, title, notes, scope, date, time, durationMinutes, quadrant, subtasks, isDone, completedAt, createdAt, calendarEventID, tags
        case link, sourceKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        scope = try c.decodeIfPresent(TodoScope.self, forKey: .scope) ?? .day
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date().startOfDay
        time = try c.decodeIfPresent(Date.self, forKey: .time)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 60
        quadrant = try c.decodeIfPresent(Quadrant.self, forKey: .quadrant)
        subtasks = try c.decodeIfPresent([SubTask].self, forKey: .subtasks) ?? []
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        calendarEventID = try c.decodeIfPresent(String.self, forKey: .calendarEventID)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        link = try c.decodeIfPresent(String.self, forKey: .link)
        sourceKey = try c.decodeIfPresent(String.self, forKey: .sourceKey)
    }
}

/// 태그 이름 규칙: 앞의 # 제거, 공백 정리, 중복 제거(대소문자 무시)
enum Tag {
    static func normalize(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("#") { t.removeFirst() }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }

    static func normalizeList(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map(normalize).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// 범위 지정용 예약어 (#주간, #월간)
    static let reserved: Set<String> = ["주간", "월간", "week", "month"]
}

extension Array where Element == TodoItem {
    /// 미완료 → 사분면 → 시각 → 생성순
    func sortedForDisplay() -> [TodoItem] {
        sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            let qa = a.quadrant?.rawValue ?? 5, qb = b.quadrant?.rawValue ?? 5
            if qa != qb { return qa < qb }
            switch (a.scheduledStart, b.scheduledStart) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }
}
