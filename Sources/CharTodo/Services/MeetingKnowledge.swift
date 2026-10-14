import Foundation

enum MeetingImportError: LocalizedError {
    case unreadable(String)
    case empty(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case let .unreadable(name): "\(name) 파일을 읽지 못했어요. UTF-8 또는 EUC-KR 텍스트(.txt, .md)인지 확인해 주세요."
        case let .empty(name): "\(name) 에 내용이 없어요."
        case let .badResponse(text): "AI 응답에서 정리 결과(JSON)를 찾지 못했어요. 다시 분석해 보세요.\n응답 앞부분: \(text.prefix(160))"
        }
    }
}

/// 회의록 파일 읽기 · AI 응답(JSON) 해석
enum MeetingParser {
    static let supportedExtensions: Set<String> = ["txt", "md", "markdown", "text"]

    static func readText(at url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw MeetingImportError.unreadable(url.lastPathComponent) }
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: cp949)
            ?? String(data: data, encoding: .utf16) else {
            throw MeetingImportError.unreadable(url.lastPathComponent)
        }
        guard !text.trimmed.isEmpty else { throw MeetingImportError.empty(url.lastPathComponent) }
        return text
    }

    /// 파일 이름 속 날짜: "2026-10-02 주간회의", "20261002_회의록", "2026년 10월 2일"
    static func date(fromFileName name: String) -> Date? {
        let pattern = #"(20\d{2})\s*[-._/년]?\s*(\d{1,2})\s*[-._/월]?\s*(\d{1,2})"#
        guard let r = name.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = name[r].components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        let parts: [Int]
        if digits.count == 1, digits[0].count == 8 {  // 20261002
            let s = digits[0]
            parts = [Int(s.prefix(4))!, Int(s.dropFirst(4).prefix(2))!, Int(s.suffix(2))!]
        } else if digits.count == 3 {
            parts = digits.compactMap { Int($0) }
        } else {
            return nil
        }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        guard (1...12).contains(parts[1]), (1...31).contains(parts[2]),
              let d = AppCalendar.current.date(from: c), d.dayNumber == parts[2] else { return nil }
        return d
    }

    // MARK: JSON

    /// 응답에서 JSON 객체를 꺼낸다. 코드블록·앞뒤 설명을 무시하고, 토큰 한도로 잘린 JSON도 최대한 살린다.
    static func jsonObject(from text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        let body = text[start...]
        if let end = body.lastIndex(of: "}"), let obj = parse(String(body[...end])) { return obj }
        // 잘린 JSON: 뒤에서부터 쉼표/닫는 괄호 위치에서 끊어 괄호를 닫아 본다
        if let closed = close(body), let obj = parse(closed) { return obj }
        var tries = 0
        var i = body.endIndex
        while i > body.startIndex, tries < 400 {
            i = body.index(before: i)
            let ch = body[i]
            guard ch == "," || ch == "}" || ch == "]" else { continue }
            tries += 1
            let prefix = ch == "," ? body[..<i] : body[...i]
            if let closed = close(prefix), let obj = parse(closed) { return obj }
        }
        return nil
    }

    private static func parse(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 열린 문자열·괄호를 닫는다. 괄호 짝이 안 맞으면 nil
    static func close(_ s: Substring) -> String? {
        var stack: [Character] = []
        var inString = false, escaped = false
        for ch in s {
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}", "]":
                guard stack.last == ch else { return nil }
                stack.removeLast()
            default: break
            }
        }
        var out = String(s)
        if inString { out += escaped ? "\\\"" : "\"" }
        out = out.trimmed
        while out.hasSuffix(",") { out = String(out.dropLast()).trimmed }
        if out.hasSuffix(":") { return nil }
        return out + String(stack.reversed())
    }

    private static func string(_ v: Any?) -> String { (v as? String)?.trimmed ?? "" }

    private static func strings(_ v: Any?) -> [String] {
        if let arr = v as? [Any] { return arr.compactMap { ($0 as? String)?.trimmed }.filter { !$0.isEmpty } }
        if let s = v as? String, !s.trimmed.isEmpty { return [s.trimmed] }
        return []
    }

    private static func day(_ v: Any?) -> Date? {
        let s = string(v)
        guard s.count >= 8 else { return nil }
        return DateFormatters.dayKey.date(from: String(s.prefix(10)))
    }

    /// AI 정리 결과를 회의록에 반영한다. 다시 분석해도 이미 앱 할일로 등록한 항목은 연결을 유지한다.
    static func apply(_ obj: [String: Any], to note: inout MeetingNote) {
        let title = string(obj["title"])
        if !title.isEmpty { note.title = title }
        if let d = day(obj["date"]) { note.date = d.startOfDay }
        note.summary = string(obj["summary"])
        note.participants = dedupe(strings(obj["participants"]))

        note.topics = (obj["topics"] as? [Any] ?? []).compactMap { raw in
            if let s = raw as? String, !s.trimmed.isEmpty { return MeetingTopic(title: s.trimmed) }
            guard let d = raw as? [String: Any] else { return nil }
            let t = string(d["title"])
            return t.isEmpty ? nil : MeetingTopic(title: t, points: strings(d["points"]))
        }
        note.decisions = strings(obj["decisions"])

        let previous = Dictionary(note.actions.compactMap { a in a.todoID.map { (KnowledgeGraph.normalize(a.title), $0) } },
                                  uniquingKeysWith: { a, _ in a })
        note.actions = (obj["actions"] as? [Any] ?? []).compactMap { raw in
            var a: MeetingAction
            if let s = raw as? String, !s.trimmed.isEmpty {
                a = MeetingAction(title: s.trimmed)
            } else if let d = raw as? [String: Any], !string(d["title"]).isEmpty {
                a = MeetingAction(title: string(d["title"]), owner: string(d["owner"]), due: day(d["due"]))
            } else {
                return nil
            }
            a.todoID = previous[KnowledgeGraph.normalize(a.title)]
            return a
        }

        note.entities = (obj["entities"] as? [Any] ?? []).compactMap { raw in
            if let s = raw as? String, !s.trimmed.isEmpty { return MeetingEntity(name: s.trimmed, kind: .concept) }
            guard let d = raw as? [String: Any], !string(d["name"]).isEmpty else { return nil }
            return MeetingEntity(name: string(d["name"]), kind: KGNodeKind.entity(from: string(d["type"])))
        }
        note.relations = (obj["relations"] as? [Any] ?? []).compactMap { raw in
            guard let d = raw as? [String: Any] else { return nil }
            let from = string(d["from"]), to = string(d["to"])
            guard !from.isEmpty, !to.isEmpty else { return nil }
            return MeetingRelation(from: from, relation: string(d["rel"] ?? d["relation"]), to: to)
        }
    }

    private static func dedupe(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert(KnowledgeGraph.normalize($0)).inserted }
    }
}

/// 질문봇에 넘길 회의록 지식 (질문과 관련된 회의 + 지식그래프 연결 + 원문 발췌)
enum MeetingContextBuilder {
    /// todoStatus: 앱 할일 id → 완료 여부 (지워졌으면 nil)
    static func build(question: String, meetings: [MeetingNote], graph: KnowledgeGraph,
                      todoStatus: (UUID) -> Bool?, budget: Int = 9000) -> String? {
        guard !meetings.isEmpty else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: meetings.map { ($0.id, $0) })
        let recent = meetings.sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }

        var out = "## 회의록 목록 (최근순, 총 \(meetings.count)건)\n"
        for m in recent.prefix(25) {
            let counts = m.countsLabel
            out += "- \(m.date.dayKey) \(m.title)" + (counts.isEmpty ? "" : " — \(counts)") + (m.status == .analyzed ? "" : " (정리 전)") + "\n"
        }

        let (matches, hitNodes) = graph.rank(meetings, for: question)
        let keys = KnowledgeGraph.keywords(from: question)
        let detailed: [MeetingNote]
        if matches.isEmpty {
            detailed = Array(recent.prefix(2))
            out += "\n## 최근 회의록 (질문과 딱 맞는 회의를 찾지 못해 최근 것을 보여 줌)\n"
        } else {
            detailed = matches.prefix(3).compactMap { byID[$0.meetingID] }
            out += "\n## 질문과 관련된 회의록\n"
        }
        for m in detailed {
            out += block(m, todoStatus: todoStatus, excerptKeys: matches.isEmpty ? [] : keys)
        }

        let entities = hitNodes.filter(\.kind.isEntity).prefix(5)
        if !entities.isEmpty {
            out += "\n## 지식그래프 연결 (질문 속 개체가 여러 회의에서 어떻게 이어지는지)\n"
            for n in entities {
                let ms = n.meetingIDs.compactMap { byID[$0] }.sorted { $0.date > $1.date }
                out += "- \(n.label) [\(n.kind.label)] — 회의 \(ms.count)건: "
                    + ms.prefix(6).map { "\($0.date.dayKey) \($0.title)" }.joined(separator: ", ") + "\n"
                for (e, other) in graph.neighbors(of: n.id).filter({ $0.node.kind != .meeting }).prefix(8) {
                    let arrow = e.source == n.id ? "\(n.label) —\(e.relation)→ \(other.label)" : "\(other.label) —\(e.relation)→ \(n.label)"
                    out += "    · \(arrow) (\(byID[e.meetingID]?.date.dayKey ?? ""))\n"
                }
            }
        }

        if asksAboutTasks(question) {
            let open = recent.flatMap { m in m.actions.map { (m, $0) } }.filter { _, a in
                a.todoID.flatMap(todoStatus) != true
            }
            if !open.isEmpty {
                out += "\n## 회의에서 나온 할일 중 아직 안 끝난 것\n"
                for (m, a) in open.prefix(30) { out += "- " + actionLine(a, todoStatus: todoStatus) + " ← \(m.date.dayKey) \(m.title)\n" }
            }
        }

        if out.count > budget { out = String(out.prefix(budget)) + "\n…(길어서 생략)" }
        return out
    }

    static func asksAboutTasks(_ question: String) -> Bool {
        ["할일", "할 일", "액션", "담당", "해야", "todo", "챙길", "남은"].contains { question.lowercased().contains($0) }
    }

    static func actionLine(_ a: MeetingAction, todoStatus: (UUID) -> Bool?) -> String {
        var meta: [String] = []
        if !a.owner.trimmed.isEmpty { meta.append("담당 \(a.owner)") }
        if let due = a.due { meta.append("기한 \(due.dayKey)") }
        switch a.todoID.flatMap(todoStatus) {
        case true?: meta.append("앱 할일 완료")
        case false?: meta.append("앱 할일 진행 중")
        case nil: break
        }
        return a.title + (meta.isEmpty ? "" : " (" + meta.joined(separator: ", ") + ")")
    }

    static func block(_ m: MeetingNote, todoStatus: (UUID) -> Bool?, excerptKeys: [String]) -> String {
        var s = "\n### \(m.date.dayKey) · \(m.title)\n"
        if !m.participants.isEmpty { s += "참석: \(m.participants.joined(separator: ", "))\n" }
        if !m.summary.trimmed.isEmpty { s += "요약: \(m.summary.trimmed)\n" }
        if !m.topics.isEmpty {
            s += "안건:\n"
            for t in m.topics {
                s += "- \(t.title)" + (t.points.isEmpty ? "" : ": " + t.points.prefix(5).joined(separator: " / ")) + "\n"
            }
        }
        if !m.decisions.isEmpty { s += "결정:\n" + m.decisions.map { "- \($0)" }.joined(separator: "\n") + "\n" }
        if !m.actions.isEmpty {
            s += "할일:\n" + m.actions.map { "- " + actionLine($0, todoStatus: todoStatus) }.joined(separator: "\n") + "\n"
        }
        let lines = excerpts(m.rawText, keys: excerptKeys)
        if m.status != .analyzed && lines.isEmpty {
            // 아직 정리 전이면 원문 앞부분이라도 준다
            s += "원문 앞부분:\n" + String(m.rawText.trimmed.prefix(1200)) + "\n"
        } else if !lines.isEmpty {
            s += "원문 발췌:\n" + lines.map { "> \($0)" }.joined(separator: "\n") + "\n"
        }
        return s
    }

    /// 키워드가 들어간 원문 줄 (최대 6줄)
    static func excerpts(_ text: String, keys: [String], limit: Int = 6) -> [String] {
        guard !keys.isEmpty else { return [] }
        var out: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmed
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            guard keys.contains(where: { lower.contains($0) }) else { continue }
            out.append(line.count > 180 ? String(line.prefix(180)) + "…" : line)
            if out.count >= limit { break }
        }
        return out
    }
}
