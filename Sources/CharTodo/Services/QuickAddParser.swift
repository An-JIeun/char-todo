import Foundation

/// 빠른 입력 문법
///  - `!1` ~ `!4`         : 아이젠하워 사분면
///  - `@오늘 @내일 @모레`  : 날짜 (그 외 `@월` ~ `@일` 은 다가오는 요일, `@10/12` 는 해당 날짜)
///  - `#주간` `#월간`      : 범위
///  - `#업무` `#공부` …    : 태그 (위 두 예약어 제외)
///  - `~14:30` 또는 `~2시`  : 시각
///  - `제목 > 세부1, 세부2` : 세부 테스크
struct QuickAddParser {
    struct Result: Equatable {
        var title: String
        var date: Date?
        var scope: TodoScope?
        var quadrant: Quadrant?
        var time: Date?
        var subtasks: [String] = []
        var tags: [String] = []
    }

    var now: Date = Date()

    func parse(_ raw: String) -> Result {
        var text = raw.trimmed
        var subtasks: [String] = []
        if let range = text.range(of: ">") {
            let tail = String(text[range.upperBound...])
            subtasks = tail.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "/" })
                .map { String($0).trimmed }.filter { !$0.isEmpty }
            text = String(text[..<range.lowerBound])
        }

        var result = Result(title: "", subtasks: subtasks)
        var words: [String] = []
        for token in text.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            if token.count == 2, token.hasPrefix("!"), let n = Int(token.dropFirst()), let q = Quadrant(rawValue: n) {
                result.quadrant = q
            } else if token.hasPrefix("@"), let d = parseDate(String(token.dropFirst())) {
                result.date = d
            } else if token == "#주간" || token.lowercased() == "#week" {
                result.scope = .week
            } else if token == "#월간" || token.lowercased() == "#month" {
                result.scope = .month
            } else if token.hasPrefix("~"), let t = parseTime(String(token.dropFirst())) {
                result.time = t
            } else if token.hasPrefix("#"), token.count > 1, !Tag.reserved.contains(Tag.normalize(token).lowercased()) {
                result.tags.append(Tag.normalize(token))
            } else {
                words.append(token)
            }
        }
        result.title = words.joined(separator: " ")
        result.tags = Tag.normalizeList(result.tags)
        return result
    }

    func parseDate(_ s: String) -> Date? {
        let today = now.startOfDay
        switch s {
        case "오늘", "today": return today
        case "내일", "tomorrow": return today.adding(days: 1)
        case "모레": return today.adding(days: 2)
        case "글피": return today.adding(days: 3)
        case "다음주", "다음주월": return today.startOfWeek.adding(weeks: 1)
        default: break
        }
        let weekdays = ["일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7]
        let key = s.replacingOccurrences(of: "요일", with: "")
        if let target = weekdays[key] {
            let current = today.weekdayIndex
            var diff = (target - current + 7) % 7
            if diff == 0 { diff = 7 }
            return today.adding(days: diff)
        }
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == "." || $0 == "-" }).compactMap { Int($0) }
        if parts.count == 2 {
            let cal = AppCalendar.current
            var comps = cal.dateComponents([.year], from: today)
            comps.month = parts[0]
            comps.day = parts[1]
            guard let d = cal.date(from: comps) else { return nil }
            // 이미 지난 날짜면 내년으로
            return d < today.adding(days: -30) ? d.adding(months: 12) : d
        }
        return nil
    }

    func parseTime(_ s: String) -> Date? {
        var hour: Int?
        var minute = 0
        if s.contains(":") {
            let p = s.split(separator: ":").compactMap { Int($0) }
            if p.count == 2 { hour = p[0]; minute = p[1] }
        } else if s.hasSuffix("시") {
            var body = String(s.dropLast())
            var pm = false
            if body.hasPrefix("오후") { pm = true; body = String(body.dropFirst(2)) }
            if body.hasPrefix("오전") { body = String(body.dropFirst(2)) }
            if let h = Int(body) { hour = pm && h < 12 ? h + 12 : h }
        } else if let h = Int(s) {
            hour = h
        }
        guard let hour, (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return AppCalendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now.startOfDay)
    }

    /// 파싱 결과 + 화면 맥락(기본 날짜/범위)으로 TodoItem 생성
    func makeTodo(from raw: String, defaultDate: Date, defaultScope: TodoScope) -> TodoItem? {
        let r = parse(raw)
        guard !r.title.isEmpty else { return nil }
        let scope = r.scope ?? defaultScope
        var item = TodoItem(title: r.title, scope: scope, date: r.date ?? defaultDate,
                            time: scope == .day ? r.time : nil, quadrant: r.quadrant,
                            subtasks: r.subtasks.map { SubTask(title: $0) }, tags: r.tags)
        if r.time != nil, scope != .day { item.time = nil }
        return item
    }
}
