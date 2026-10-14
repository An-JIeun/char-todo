import Foundation

/// 어시스턴트에게 넘길 오늘의 상황 스냅샷
struct AssistantContext {
    var now: Date
    var today: [TodoItem]
    var overdue: [TodoItem]
    var weekGoals: [TodoItem]
    var monthGoals: [TodoItem]
    var upcoming: [(Date, [TodoItem])]
    var events: [CalendarEvent]
    var upcomingEvents: [CalendarEvent]
    var completedToday: [TodoItem]
    var yesterdayPlan: String?
    var todayJournal: JournalEntry?
    var knownTags: [String] = []
}

/// 어시스턴트가 응답에 넣는 할일. ADD = 사용자가 요청해 바로 등록, SUGGEST = 제안(버튼)
struct TodoSuggestion: Identifiable, Equatable {
    enum Kind: Equatable { case add, suggest }

    var id = UUID()
    var kind: Kind = .suggest
    var title: String
    var date: Date?
    var scope: TodoScope = .day
    var quadrant: Quadrant?
    var hour: Int?
    var minute: Int?
    var duration: Int?
    var tags: [String] = []
    var subtasks: [String] = []
    var notes = ""
    var addToCalendar = false

    static func == (a: TodoSuggestion, b: TodoSuggestion) -> Bool {
        a.kind == b.kind && a.title == b.title && a.date == b.date && a.scope == b.scope && a.quadrant == b.quadrant
            && a.hour == b.hour && a.minute == b.minute && a.duration == b.duration && a.tags == b.tags
            && a.subtasks == b.subtasks && a.notes == b.notes && a.addToCalendar == b.addToCalendar
    }

    /// 모든 필드를 채운 TodoItem으로 변환
    func makeTodo(now: Date = Date()) -> TodoItem {
        let day = (date ?? now).startOfDay
        var time: Date?
        if scope == .day, let hour {
            time = AppCalendar.current.date(bySettingHour: hour, minute: minute ?? 0, second: 0, of: day)
        }
        var item = TodoItem(title: title, scope: scope, date: day, time: time, quadrant: quadrant,
                            subtasks: subtasks.map { SubTask(title: $0) }, notes: notes, tags: tags)
        if let duration, duration > 0 { item.durationMinutes = duration }
        return item
    }

    /// 칩에 보여줄 요약: "10/8 15:00 · Q1 · #업무"
    var detailLabel: String {
        var parts: [String] = []
        switch scope {
        case .day:
            var d = date.map { DateFormatters.monthDay.string(from: $0) } ?? "오늘"
            if let hour { d += String(format: " %02d:%02d", hour, minute ?? 0) }
            parts.append(d)
        case .week: parts.append("주간" + (date.map { " " + DateFormatters.monthDay.string(from: $0) } ?? ""))
        case .month: parts.append("월간")
        }
        if let q = quadrant { parts.append(q.shortLabel) }
        if !subtasks.isEmpty { parts.append("세부 \(subtasks.count)") }
        if !tags.isEmpty { parts.append(tags.map { "#\($0)" }.joined(separator: " ")) }
        if addToCalendar { parts.append("📅") }
        return parts.joined(separator: " · ")
    }
}

enum BriefingKind: String, CaseIterable, Identifiable {
    case today, priorities, week, wrapUp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "오늘 브리핑"
        case .priorities: "뭐부터 할까?"
        case .week: "이번 주 점검"
        case .wrapUp: "하루 마무리"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .priorities: "list.number"
        case .week: "calendar"
        case .wrapUp: "moon.stars.fill"
        }
    }

    var prompt: String {
        switch self {
        case .today:
            "오늘 할일을 브리핑해 줘. 시간이 정해진 일정, 밀린 일, 가장 중요한 일(Q1) 순서로 짚고, 오늘 하루 추천 흐름을 3~5단계로 알려 줘. 마지막에 짧은 응원 한마디."
        case .priorities:
            "아이젠하워 매트릭스 관점에서 지금 당장 무엇부터 해야 할지 상위 3개를 골라 이유와 함께 알려 줘. 사분면이 비어 있는 할일이 있으면 어디에 둘지도 제안해 줘."
        case .week:
            "이번 주 목표와 남은 할일을 점검해 줘. 진행률, 위험한 일, 남은 요일별 추천 배치를 알려 줘."
        case .wrapUp:
            "오늘 하루를 마무리하자. 완료한 일을 칭찬해 주고, 못 끝낸 일은 언제로 옮기면 좋을지 제안하고, 업무일지에 쓸 한 줄 회고를 추천해 줘."
        }
    }
}

enum PromptBuilder {
    static func line(_ t: TodoItem) -> String {
        var s = "- [\(t.isDone ? "x" : " ")] \(t.title)"
        var meta: [String] = []
        if let q = t.quadrant { meta.append("\(q.shortLabel) \(q.title)") }
        if let start = t.scheduledStart { meta.append(DateFormatters.time.string(from: start)) }
        let p = t.subtaskProgress
        if p.total > 0 { meta.append("세부 \(p.done)/\(p.total)") }
        if !t.tags.isEmpty { meta.append(t.tags.map { "#\($0)" }.joined(separator: " ")) }
        if !meta.isEmpty { s += " (" + meta.joined(separator: ", ") + ")" }
        let openSubs = t.subtasks.filter { !$0.isDone }.prefix(5)
        for sub in openSubs { s += "\n    · \(sub.title)" }
        return s
    }

    /// 오늘부터 14일: "10/7(수) 오늘 = 2026-10-07" 형식
    static func dateTable(from now: Date, days: Int = 14) -> String {
        let start = now.startOfDay
        return (0..<days).map { i -> String in
            let d = start.adding(days: i)
            let tag = i == 0 ? " 오늘" : i == 1 ? " 내일" : i == 2 ? " 모레" : ""
            let week = d.startOfWeek == start.startOfWeek ? "이번 주" : d.startOfWeek == start.startOfWeek.adding(weeks: 1) ? "다음 주" : ""
            return "\(DateFormatters.monthDay.string(from: d))(\(DateFormatters.weekdayShort.string(from: d)))\(tag)\(week.isEmpty ? "" : " [\(week)]") = \(d.dayKey)"
        }.joined(separator: ", ")
    }

    static func contextBlock(_ c: AssistantContext) -> String {
        var out = "현재 시각: \(DateFormatters.fullDate.string(from: c.now)) \(DateFormatters.time.string(from: c.now))\n"
        out += "\n## 날짜표 (상대 날짜 변환용)\n" + dateTable(from: c.now) + "\n"
        if !c.knownTags.isEmpty {
            out += "\n## 기존 태그\n" + c.knownTags.map { "#\($0)" }.joined(separator: " ") + "\n"
        }

        func section(_ title: String, _ items: [TodoItem], empty: String = "(없음)") {
            out += "\n## \(title)\n"
            out += items.isEmpty ? empty + "\n" : items.map(line).joined(separator: "\n") + "\n"
        }

        out += "\n## 오늘 캘린더 일정\n"
        out += c.events.isEmpty ? "(없음)\n" : c.events.map { "- \($0.timeLabel) \($0.title)" }.joined(separator: "\n") + "\n"
        section("오늘 할일", c.today)
        if !c.overdue.isEmpty {
            out += "\n## 밀린 할일 (지난 날짜, 미완료)\n"
            out += c.overdue.map { line($0) + " — 원래 \(DateFormatters.monthDay.string(from: $0.date))" }.joined(separator: "\n") + "\n"
        }
        section("이번 주 목표", c.weekGoals)
        section("이번 달 목표", c.monthGoals)
        if !c.upcoming.isEmpty {
            out += "\n## 다가오는 할일\n"
            for (day, items) in c.upcoming where !items.isEmpty {
                out += "\(DateFormatters.monthDayWeekday.string(from: day)):\n" + items.map(line).joined(separator: "\n") + "\n"
            }
        }
        if !c.upcomingEvents.isEmpty {
            out += "\n## 다가오는 일정 (3일)\n"
            out += c.upcomingEvents.prefix(12).map { "- \(DateFormatters.monthDayWeekday.string(from: $0.start)) \($0.timeLabel) \($0.title)" }
                .joined(separator: "\n") + "\n"
        }
        if !c.completedToday.isEmpty {
            out += "\n## 오늘 완료한 일\n" + c.completedToday.map { "- \($0.title)" }.joined(separator: "\n") + "\n"
        }
        if let plan = c.yesterdayPlan, !plan.trimmed.isEmpty {
            out += "\n## 어제 업무일지에 적은 '내일 할 일'\n\(plan.trimmed)\n"
        }
        return out
    }

    /// 말투 설정을 프롬프트 지시문으로 바꾼다.
    static func personaBlock(tone: AssistantTone, persona: PersonaConfig) -> String {
        var lines = ["- 기본 성격: \(tone.instruction)"]
        let style = persona.styleDescription.trimmed
        if !style.isEmpty { lines.append("- 캐릭터 설정·말투: \(style)") }
        let ending = persona.sentenceEnding.trimmed
        if !ending.isEmpty {
            lines.append("- 문장 끝 어미: '\(ending)' 형태로 문장을 끝내. 어색하지 않게 대부분의 문장에 적용해. (기본 성격의 존댓말/반말보다 이 어미가 우선)")
        }
        let phrases = persona.catchphrases.map(\.trimmed).filter { !$0.isEmpty }
        if !phrases.isEmpty {
            lines.append("- 말버릇: " + phrases.map { "\"\($0)\"" }.joined(separator: ", ")
                         + " — \(persona.catchphraseFrequency.instruction) 자연스럽게 섞어.")
        }
        let situations = PersonaSituation.allCases.compactMap { s -> String? in
            let pool = persona.lines(for: s)
            guard !pool.isEmpty else { return nil }
            return "  · \(s.promptLabel): " + pool.map { "\"\($0)\"" }.joined(separator: " / ")
        }
        if !situations.isEmpty {
            lines.append("- 상황별 표현 (그 상황이 오면 아래 표현을 그대로 또는 살짝 바꿔서 써. {n}은 개수, {이름}은 네 이름):")
            lines.append(contentsOf: situations)
        }
        let avoid = persona.avoid.trimmed
        if !avoid.isEmpty { lines.append("- 피할 표현: \(avoid)") }
        return lines.joined(separator: "\n")
    }

    static func systemPrompt(name: String, tone: AssistantTone, persona: PersonaConfig = PersonaConfig(),
                             context: AssistantContext, knowledge: String? = nil) -> String {
        let today = DateFormatters.dayKey.string(from: context.now)
        var meetingRules = "", meetingBlock = ""
        if let knowledge, !knowledge.trimmed.isEmpty {
            meetingRules = """

            [회의록 질문 규칙]
            - 업무·회의에 대한 질문은 맨 아래 '회의록 지식'을 근거로 답하고, 어느 회의(날짜·제목)에서 나온 내용인지 함께 밝혀.
            - 회의록에 없는 내용은 추측하지 말고 "회의록에서 찾지 못했어"라고 말해.
            - 여러 회의에 걸친 질문이면 지식그래프 연결을 보고 날짜순으로 흐름을 정리해.
            - 회의 할일을 앱에 넣어 달라고 하면 위 [[ADD]] 규칙대로 등록해.

            """
            meetingBlock = "\n\n===== 회의록 지식 (회의록에서 정리한 업무 지식그래프) =====\n" + knowledge
        }
        return """
        너는 macOS 할일 앱 'CharTodo' 화면 위에 떠 있는 뉴트로 캐릭터 비서 '\(name)'야.

        [말투 설정 — 반드시 지켜]
        \(personaBlock(tone: tone, persona: persona))

        항상 한국어로 답해. 사용자의 할일·일정 데이터(아래)를 근거로 구체적으로 말하고, 없는 사실은 지어내지 마.
        답변은 짧은 문단과 간단한 목록 위주로, 길어도 화면 한두 개 분량을 넘기지 마. 이모지는 한두 개만.

        [할일 추가 규칙]
        - 사용자가 할일 추가·등록·일정 잡기를 요청하면, 할일마다 답변 끝에 한 줄씩 [[ADD {JSON}]] 을 붙여. 앱이 바로 등록한다.
        - 사용자가 요청하지 않았는데 네가 먼저 권하는 할일은 [[SUGGEST {JSON}]] 으로 붙여. 사용자가 버튼을 눌러야 등록된다.
        - JSON 필드 (title 외에는 해당될 때만):
          title(필수, 짧은 제목) · date("YYYY-MM-DD") · time("HH:mm", 24시간) · duration(분, 숫자)
          · scope("day"|"week"|"month", 기본 day) · quadrant(1 긴급·중요 / 2 중요 / 3 긴급 / 4 둘 다 아님)
          · tags(["태그"], # 없이) · subtasks(["세부 테스크"]) · notes("메모") · calendar(true면 macOS 캘린더에도 등록)
        - 사용자가 말한 날짜·시간·태그·세부 내용은 하나도 빠뜨리지 마. "#업무"처럼 말하면 tags에 넣어.
        - 태그를 말하지 않았으면 아래 '기존 태그' 중 어울리는 것을 골라 1~2개 넣어(없으면 생략).
        - "내일", "다음 주 금요일", "오후 3시" 같은 표현은 아래 날짜표로 정확히 변환해. 시간을 말하지 않았으면 time은 빼.
        - 본문에서는 무엇을 추가했는지 한두 줄로만 말하고, JSON을 설명하지 마. 이미 있는 할일과 같은 건 만들지 마.
        예: [[ADD {"title":"팀 회의 준비","date":"\(today)","time":"15:00","duration":60,"quadrant":1,"tags":["업무","회의"],"subtasks":["안건 정리","자료 출력"]}]]
        \(meetingRules)
        ===== 사용자 데이터 =====
        \(contextBlock(context))\(meetingBlock)
        """
    }

    // MARK: 할일 태그 파싱

    /// 새 형식: [[ADD {...}]] / [[SUGGEST {...}]]
    private static let jsonTagRegex = try! NSRegularExpression(pattern: #"\[\[(ADD|SUGGEST)\s*(\{[\s\S]*?\})\s*\]\]"#)
    /// 이전 형식: [[ADD|제목|날짜|범위|사분면]]
    private static let pipeTagRegex = try! NSRegularExpression(pattern: #"\[\[ADD\|([^|\]]+)(?:\|([^|\]]*))?(?:\|([^|\]]*))?(?:\|([^|\]]*))?\]\]"#)
    /// 화면에서 숨길 모든 태그
    private static let anyTagRegex = try! NSRegularExpression(pattern: #"\[\[(?:ADD|SUGGEST)[\s\S]*?\]\]"#)

    static func parseSuggestions(_ text: String) -> [TodoSuggestion] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var out: [(Int, TodoSuggestion)] = []
        for m in jsonTagRegex.matches(in: text, range: full) {
            let kind: TodoSuggestion.Kind = ns.substring(with: m.range(at: 1)) == "ADD" ? .add : .suggest
            if let s = suggestion(fromJSON: ns.substring(with: m.range(at: 2)), kind: kind) {
                out.append((m.range.location, s))
            }
        }
        for m in pipeTagRegex.matches(in: text, range: full) {
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                guard r.location != NSNotFound else { return nil }
                let s = ns.substring(with: r).trimmed
                return s.isEmpty ? nil : s
            }
            guard let title = group(1) else { continue }
            var s = TodoSuggestion(title: title)
            if let d = group(2) { s.date = DateFormatters.dayKey.date(from: d) }
            if let sc = group(3), let scope = TodoScope(rawValue: sc.lowercased()) { s.scope = scope }
            if let q = group(4) { s.quadrant = parseQuadrant(q) }
            out.append((m.range.location, s))
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func suggestion(fromJSON json: String, kind: TodoSuggestion.Kind) -> TodoSuggestion? {
        guard let obj = HTTP.parseJSONObject(json), let title = (obj["title"] as? String)?.trimmed, !title.isEmpty else { return nil }
        var s = TodoSuggestion(kind: kind, title: title)
        if let d = obj["date"] as? String { s.date = DateFormatters.dayKey.date(from: d.trimmed) }
        if let sc = obj["scope"] as? String, let scope = TodoScope(rawValue: sc.lowercased().trimmed) { s.scope = scope }
        if let t = obj["time"] as? String {
            let p = t.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if let h = p.first, (0..<24).contains(h) {
                s.hour = h
                s.minute = p.count > 1 && (0..<60).contains(p[1]) ? p[1] : 0
            }
        }
        if let d = obj["duration"] as? Int { s.duration = d } else if let d = obj["duration"] as? String { s.duration = Int(d) }
        if let q = obj["quadrant"] { s.quadrant = parseQuadrant("\(q)") }
        s.tags = Tag.normalizeList(stringList(obj["tags"]))
        s.subtasks = stringList(obj["subtasks"]).map(\.trimmed).filter { !$0.isEmpty }
        s.notes = (obj["notes"] as? String)?.trimmed ?? ""
        s.addToCalendar = (obj["calendar"] as? Bool) ?? false
        return s
    }

    private static func parseQuadrant(_ raw: String) -> Quadrant? {
        Int(raw.uppercased().replacingOccurrences(of: "Q", with: "").trimmed).flatMap(Quadrant.init(rawValue:))
    }

    /// ["a","b"] 또는 "a, b" 모두 허용
    private static func stringList(_ value: Any?) -> [String] {
        if let arr = value as? [Any] { return arr.compactMap { $0 as? String } }
        if let str = value as? String { return str.split(whereSeparator: { $0 == "," || $0 == ";" }).map { String($0).trimmed } }
        return []
    }

    /// 화면 표시용: 완성된 태그와 스트리밍 중 덜 완성된 태그 꼬리를 숨긴다.
    static func displayText(_ text: String) -> String {
        let ns = text as NSString
        var out = anyTagRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        if let r = out.range(of: "[[", options: .backwards), !out[r.lowerBound...].contains("]]") {
            out = String(out[..<r.lowerBound])
        }
        while out.contains("\n\n\n") { out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return out.trimmed
    }

    // MARK: 단발 작업 프롬프트

    static let utilitySystem = "너는 간결한 업무 도우미야. 요청한 형식만 정확히 출력하고 다른 말은 덧붙이지 마. 한국어로 답해."

    static func subtaskPrompt(for todo: TodoItem) -> String {
        var s = "다음 할일을 실행 가능한 세부 테스크 3~7개로 쪼개 줘. 각 줄에 '- ' 로 시작하는 짧은 동사형 문장 하나씩만 출력해.\n\n할일: \(todo.title)"
        if !todo.notes.trimmed.isEmpty { s += "\n메모: \(todo.notes.trimmed)" }
        if !todo.subtasks.isEmpty { s += "\n이미 있는 세부 테스크(중복 금지): " + todo.subtasks.map(\.title).joined(separator: ", ") }
        return s
    }

    static func journalPrompt(entry: JournalEntry, completed: [TodoItem], remaining: [TodoItem]) -> String {
        var s = """
        아래 정보를 바탕으로 업무일지의 '오늘 한 일' 섹션 초안을 작성해 줘.
        - 완료한 일 위주로 성과 중심의 간결한 불릿 (- 로 시작) 3~8줄
        - 마지막에 빈 줄 하나 후 '배운 점:' 으로 시작하는 한 줄 회고
        다른 설명 없이 본문만 출력해.

        [완료한 할일]
        """
        s += completed.isEmpty ? "\n(없음)" : "\n" + completed.map { t in
            var l = "- \(t.title)"
            let subs = t.subtasks.filter(\.isDone).map(\.title)
            if !subs.isEmpty { l += " (" + subs.joined(separator: ", ") + ")" }
            return l
        }.joined(separator: "\n")
        if !remaining.isEmpty {
            s += "\n\n[남은 할일]\n" + remaining.map { "- \($0.title)" }.joined(separator: "\n")
        }
        if !entry.work.trimmed.isEmpty { s += "\n\n[사용자가 이미 적은 메모]\n\(entry.work.trimmed)" }
        if !entry.issues.trimmed.isEmpty { s += "\n\n[이슈]\n\(entry.issues.trimmed)" }
        return s
    }

    /// 회의록 → 안건·결정·할일·개체·관계 JSON
    static func meetingPrompt(text: String, baseDate: Date, limit: Int = 30000) -> String {
        var body = text.trimmed
        if body.count > limit { body = String(body.prefix(limit)) + "\n…(이하 생략)" }
        return """
        아래 회의록을 분석해서 JSON 객체 하나만 출력해. 코드블록(```)이나 설명은 붙이지 마.

        {
          "title": "회의 제목 (20자 안팎)",
          "date": "YYYY-MM-DD (회의 날짜, 회의록에 없으면 null)",
          "summary": "핵심 요약 2~3문장",
          "participants": ["참석자 이름"],
          "topics": [{"title": "안건", "points": ["논의된 요점 (최대 4개, 짧게)"]}],
          "decisions": ["결정된 사항"],
          "actions": [{"title": "할일 (동사로 끝나는 짧은 문장)", "owner": "담당자 (없으면 \\"\\")", "due": "YYYY-MM-DD 또는 null"}],
          "entities": [{"name": "이름", "type": "project|system|org|person|concept"}],
          "relations": [{"from": "개체나 안건 이름", "rel": "관계 (예: 담당, 사용, 의존, 일정, 소속, 영향)", "to": "개체나 안건 이름"}]
        }

        규칙:
        - 회의록에 적힌 내용만 써. 없는 사실을 지어내지 마.
        - 결정이나 할일이 회의록에 없으면 decisions, actions는 빈 배열 [] 로 둬.
        - entities: 프로젝트·시스템/서비스·조직/팀·사람·핵심 개념. 회의록 표기 그대로 쓰고, 같은 대상은 한 가지 표기로 통일해. (여러 회의가 이 이름으로 연결된다)
        - relations: 개체/안건 사이에 회의록에서 드러나는 관계만, 최대 15개.
        - "다음 주 금요일" 같은 상대 날짜는 회의 날짜 기준으로 YYYY-MM-DD로 바꿔. 회의 날짜를 모르면 \(baseDate.dayKey)(\(DateFormatters.weekdayShort.string(from: baseDate))) 기준.
        - 모든 값은 한국어로 (고유명사는 원문 표기 유지).

        [회의록]
        \(body)
        """
    }

    /// "- 항목" / "1. 항목" 목록을 문자열 배열로
    static func parseList(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            var s = String(raw).trimmed
            guard !s.isEmpty else { return nil }
            if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("• ") { s = String(s.dropFirst(2)) }
            else if let r = s.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) { s.removeSubrange(r) }
            else { return nil }
            s = s.replacingOccurrences(of: "**", with: "").trimmed
            if s.hasPrefix("[ ] ") { s = String(s.dropFirst(4)) }
            return s.isEmpty ? nil : s
        }
    }
}
