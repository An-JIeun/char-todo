import Foundation
import CoreGraphics

struct KGNode: Identifiable, Hashable {
    let id: String
    var kind: KGNodeKind
    var label: String
    /// 이 노드가 등장한 회의들
    var meetingIDs: Set<UUID> = []
}

struct KGEdge: Hashable {
    var source: String
    var target: String
    var relation: String
    var meetingID: UUID

    func other(than id: String) -> String { source == id ? target : source }
}

/// 회의록들로 만든 지식그래프. 회의록이 바뀔 때마다 처음부터 다시 만든다(저장하지 않음).
///
/// 노드 id 규칙
/// - 회의 `m:<uuid>` · 안건 `t:<uuid>` · 결정 `d:<회의uuid>:<순번>` · 할일 `a:<uuid>`
/// - 개체(사람·프로젝트·시스템·조직·개념) `e:<정규화 이름>` → 여러 회의에서 같은 이름이면 한 노드로 합쳐진다.
struct KnowledgeGraph {
    private(set) var nodes: [String: KGNode] = [:]
    private(set) var edges: [KGEdge] = []
    private var adjacency: [String: [Int]] = [:]
    private var edgeKeys: Set<String> = []

    var isEmpty: Bool { nodes.isEmpty }

    /// 소문자 + 글자·숫자만 남긴다. "Char Todo" == "chartodo"
    static func normalize(_ s: String) -> String {
        String(String.UnicodeScalarView(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    static func entityID(_ name: String) -> String { "e:" + normalize(name) }
    static func meetingID(_ id: UUID) -> String { "m:\(id)" }

    /// "전원", "모두" 같은 담당자는 사람 노드로 만들지 않는다.
    private static let groupOwners: Set<String> = ["전원", "모두", "all", "전체", "다같이", "미정", "tbd"]

    static func build(from meetings: [MeetingNote]) -> KnowledgeGraph {
        var g = KnowledgeGraph()
        for m in meetings { g.add(m) }
        return g
    }

    private mutating func add(_ m: MeetingNote) {
        let mid = Self.meetingID(m.id)
        addNode(mid, .meeting, m.title, meeting: m.id)

        // 정규화 이름 → 노드 id (관계·언급 연결용)
        var local: [String: String] = [:]
        var linkedToMeeting = Set<String>()

        func entity(_ name: String, _ kind: KGNodeKind, meetingRelation: String = "다룸") -> String? {
            let key = Self.normalize(name)
            guard !key.isEmpty, !Self.groupOwners.contains(key) else { return nil }
            let id = "e:" + key
            addNode(id, kind, name.trimmed, meeting: m.id)
            local[key] = id
            if linkedToMeeting.insert(id).inserted { link(mid, id, meetingRelation, m.id) }
            return id
        }

        for p in m.participants { _ = entity(p, .person, meetingRelation: "참석") }
        for e in m.entities { _ = entity(e.name, e.kind) }

        var texts: [(String, String)] = []  // (노드 id, 본문) — 개체 언급 찾기용
        for t in m.topics {
            let id = "t:\(t.id)"
            addNode(id, .topic, t.title, meeting: m.id)
            link(mid, id, "안건", m.id)
            local[Self.normalize(t.title)] = id
            texts.append((id, ([t.title] + t.points).joined(separator: " ")))
        }
        for (i, d) in m.decisions.enumerated() {
            let id = "d:\(m.id):\(i)"
            addNode(id, .decision, d, meeting: m.id)
            link(mid, id, "결정", m.id)
            local[Self.normalize(d)] = id
            texts.append((id, d))
        }
        for a in m.actions {
            let id = "a:\(a.id)"
            addNode(id, .action, a.title, meeting: m.id)
            link(mid, id, "할일", m.id)
            local[Self.normalize(a.title)] = id
            texts.append((id, a.title))
            for owner in Self.splitOwners(a.owner) {
                if let p = entity(owner, .person) { link(id, p, "담당", m.id) }
            }
        }

        // 안건·결정·할일 본문에 개체 이름이 나오면 '언급'으로 잇는다
        let entityKeys = local.filter { $0.value.hasPrefix("e:") && $0.key.count >= 2 }
        for (nodeID, text) in texts {
            let norm = Self.normalize(text)
            for (key, eid) in entityKeys where norm.contains(key) {
                link(nodeID, eid, "언급", m.id)
            }
        }

        for r in m.relations {
            // "Kafka —일정→ 2026년 10월" 같은 날짜 끝점은 노드로 만들지 않는다 (기한은 할일에 이미 있음)
            guard !Self.looksLikeDate(r.from), !Self.looksLikeDate(r.to),
                  let from = local[Self.normalize(r.from)] ?? entity(r.from, .concept),
                  let to = local[Self.normalize(r.to)] ?? entity(r.to, .concept) else { continue }
            link(from, to, r.relation.trimmed.isEmpty ? "관련" : r.relation.trimmed, m.id)
        }
    }

    /// "2026-10-12", "10/2", "2026년 10월", "다음 주 금요일" 처럼 날짜만 있는 이름
    static func looksLikeDate(_ s: String) -> Bool {
        let t = s.trimmed
        if t.range(of: #"^[\d\s./\-년월일()~]+$"#, options: .regularExpression) != nil && t.contains(where: \.isNumber) { return true }
        return t.range(of: #"^(이번|다음|지난)\s*(주|달)"#, options: .regularExpression) != nil
    }

    static func splitOwners(_ raw: String) -> [String] {
        raw.split(whereSeparator: { ",/·&、".contains($0) }).map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    private mutating func addNode(_ id: String, _ kind: KGNodeKind, _ label: String, meeting: UUID) {
        if var n = nodes[id] {
            n.meetingIDs.insert(meeting)
            // 처음엔 '개념'으로 들어왔다가 나중에 사람·프로젝트로 밝혀지면 더 구체적인 쪽으로
            if n.kind == .concept && kind.isEntity && kind != .concept { n.kind = kind }
            nodes[id] = n
        } else {
            nodes[id] = KGNode(id: id, kind: kind, label: label, meetingIDs: [meeting])
        }
    }

    private mutating func link(_ a: String, _ b: String, _ relation: String, _ meeting: UUID) {
        guard a != b else { return }
        let key = "\(a)|\(b)|\(relation)|\(meeting)"
        guard edgeKeys.insert(key).inserted else { return }
        edges.append(KGEdge(source: a, target: b, relation: relation, meetingID: meeting))
        adjacency[a, default: []].append(edges.count - 1)
        adjacency[b, default: []].append(edges.count - 1)
    }

    // MARK: 조회

    func node(_ id: String) -> KGNode? { nodes[id] }

    func edges(of id: String) -> [KGEdge] { (adjacency[id] ?? []).map { edges[$0] } }

    func degree(_ id: String) -> Int { adjacency[id]?.count ?? 0 }

    func neighbors(of id: String) -> [(edge: KGEdge, node: KGNode)] {
        edges(of: id).compactMap { e in nodes[e.other(than: id)].map { (e, $0) } }
    }

    /// 여러 회의에 걸쳐 자주 나오는 개체 (허브)
    func hubs(limit: Int = 8) -> [KGNode] {
        nodes.values.filter { $0.kind.isEntity }
            .sorted { ($0.meetingIDs.count, degree($0.id), $1.label) > ($1.meetingIDs.count, degree($1.id), $0.label) }
            .prefix(limit).map { $0 }
    }

    // MARK: 질문 → 관련 회의 찾기

    /// 한국어 조사·어미 (긴 것부터 떼어 본다)
    private static let suffixes: [String] = [
        "했었는지", "했었지", "했는지", "하기로", "에서는", "에서도", "으로는", "에게서", "한테서",
        "했지", "했어", "했나", "였지", "이었", "에서", "에게", "한테", "으로", "이랑", "까지", "부터",
        "처럼", "보다", "하고", "에는", "에도", "은", "는", "이", "가", "을", "를", "에", "의", "와", "과",
        "로", "도", "만", "랑", "요",
    ].sorted { $0.count > $1.count }

    /// 질문에 흔하지만 검색에는 도움이 안 되는 말
    private static let stopwords: Set<String> = [
        "회의", "회의록", "미팅", "지난", "지난번", "최근", "저번", "이번", "마지막", "뭐", "뭐야", "뭐였지", "무엇", "무슨",
        "어떤", "어떻게", "언제", "누가", "누구", "알려줘", "알려", "정리", "정리해줘", "내용", "관련", "대해", "대한",
        "대해서", "있어", "있나", "있었지", "있었어", "그", "저", "것", "거", "좀", "해줘", "말해줘", "나", "내", "내가",
        "우리", "결정", "결정사항", "할일", "액션", "담당", "안건", "논의", "요약", "해야", "하는", "한", "됐어", "됐지",
        "어디", "얼마", "몇", "뭘", "뭘로", "얘기",
    ]

    static func keywords(from question: String) -> [String] {
        let tokens = question.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return tokens.compactMap { raw -> String? in
            var t = raw
            if !stopwords.contains(t), let s = suffixes.first(where: { t.hasSuffix($0) && t.count - $0.count >= 2 }) {
                t = String(t.dropLast(s.count))
            }
            guard t.count >= 2, !stopwords.contains(t), seen.insert(t).inserted else { return nil }
            return t
        }
    }

    struct Match {
        var meetingID: UUID
        var score: Double
    }

    /// 질문 키워드가 노드 이름·원문에 얼마나 걸리는지로 회의 점수를 매긴다.
    /// 여러 회의에 두루 나오는 개체일수록 변별력이 낮으므로 가중치를 줄인다.
    func rank(_ meetings: [MeetingNote], for question: String) -> (matches: [Match], nodes: [KGNode]) {
        let keys = Self.keywords(from: question)
        guard !keys.isEmpty else { return ([], []) }
        var scores: [UUID: Double] = [:]
        var hitNodes: [(KGNode, Double)] = []
        for n in nodes.values {
            let label = Self.normalize(n.label)
            guard !label.isEmpty else { continue }
            let hits = keys.filter { label.contains($0) || (label.count >= 2 && $0.contains(label)) }.count
            guard hits > 0 else { continue }
            let weight: Double = (n.kind.isEntity || n.kind == .meeting) ? 3 : 2
            let s = Double(hits) * weight / Double(max(1, n.meetingIDs.count)).squareRoot()
            for mid in n.meetingIDs { scores[mid, default: 0] += s }
            hitNodes.append((n, s))
        }
        for m in meetings {
            let text = m.rawText.lowercased()
            let found = keys.filter { text.contains($0) }.count
            if found > 0 { scores[m.id, default: 0] += 0.5 * Double(found) }
        }
        let dates = Dictionary(uniqueKeysWithValues: meetings.map { ($0.id, $0.date) })
        let matches = scores.filter { dates[$0.key] != nil }
            .map { Match(meetingID: $0.key, score: $0.value) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : (dates[$0.meetingID]! > dates[$1.meetingID]!) }
        return (matches, hitNodes.sorted { $0.1 > $1.1 }.map(\.0))
    }
}

// MARK: - 배치 (그래프 그리기용)

enum GraphLayout {
    /// 실행마다 바뀌지 않는 0..<1 난수
    static func stableUnit(_ s: String, salt: UInt32 = 0) -> Double {
        var h: UInt32 = 5381 &+ salt
        for u in s.unicodeScalars { h = (h &* 33) &+ u.value }
        return Double(h % 10_000) / 10_000
    }

    /// Fruchterman–Reingold 힘 배치. 0~1로 정규화한 좌표를 돌려준다. 같은 입력이면 같은 결과.
    static func compute(ids: [String], links: [(String, String)], iterations: Int = 220) -> [String: CGPoint] {
        let n = ids.count
        guard n > 0 else { return [:] }
        if n == 1 { return [ids[0]: CGPoint(x: 0.5, y: 0.5)] }
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        var px = ids.map { 0.5 + 0.4 * cos(2 * .pi * stableUnit($0)) * (0.3 + 0.7 * stableUnit($0, salt: 7)) }
        var py = ids.map { 0.5 + 0.4 * sin(2 * .pi * stableUnit($0)) * (0.3 + 0.7 * stableUnit($0, salt: 7)) }
        let pairs = links.compactMap { l -> (Int, Int)? in
            guard let a = index[l.0], let b = index[l.1], a != b else { return nil }
            return (a, b)
        }
        let k = (1.0 / Double(n)).squareRoot() * 0.9
        var temperature = 0.12
        let cooling = temperature / Double(iterations + 1)
        var dx = [Double](repeating: 0, count: n), dy = dx
        for _ in 0..<iterations {
            for i in 0..<n { dx[i] = 0; dy[i] = 0 }
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let vx = px[i] - px[j], vy = py[i] - py[j]
                    let d = max((vx * vx + vy * vy).squareRoot(), 0.001)
                    let f = k * k / d
                    dx[i] += vx / d * f; dy[i] += vy / d * f
                    dx[j] -= vx / d * f; dy[j] -= vy / d * f
                }
            }
            for (a, b) in pairs {
                let vx = px[a] - px[b], vy = py[a] - py[b]
                let d = max((vx * vx + vy * vy).squareRoot(), 0.001)
                let f = d * d / k
                dx[a] -= vx / d * f; dy[a] -= vy / d * f
                dx[b] += vx / d * f; dy[b] += vy / d * f
            }
            for i in 0..<n {
                // 떨어진 덩어리가 멀리 날아가지 않도록 가운데로 살짝 당긴다
                dx[i] -= (px[i] - 0.5) * k * 2
                dy[i] -= (py[i] - 0.5) * k * 2
                let d = max((dx[i] * dx[i] + dy[i] * dy[i]).squareRoot(), 0.0001)
                let step = min(d, temperature)
                px[i] += dx[i] / d * step
                py[i] += dy[i] / d * step
            }
            temperature -= cooling
        }
        let minX = px.min()!, maxX = px.max()!, minY = py.min()!, maxY = py.max()!
        let w = max(maxX - minX, 0.0001), h = max(maxY - minY, 0.0001)
        var out: [String: CGPoint] = [:]
        for (i, id) in ids.enumerated() {
            out[id] = CGPoint(x: (px[i] - minX) / w, y: (py[i] - minY) / h)
        }
        return out
    }
}
