import Testing
import Foundation
@testable import CharTodo

private func day(_ s: String) -> Date { DateFormatters.dayKey.date(from: s)! }

/// 테스트용 회의록: 결제 개편 회의 + 주간 회의 (둘 다 '결제 API'가 나온다)
private func sampleMeetings() -> [MeetingNote] {
    var a = MeetingNote(title: "결제 개편 킥오프", date: day("2026-09-21"), rawText: "결제 API 교체 일정 논의\n예산은 3천만 원으로 확정")
    a.status = .analyzed
    a.participants = ["김민지", "박준호"]
    a.topics = [MeetingTopic(title: "결제 API 교체", points: ["PG사 비교", "일정 10월 말"])]
    a.decisions = ["예산 3천만 원 확정"]
    a.actions = [MeetingAction(title: "PG사 견적 요청", owner: "박준호", due: day("2026-09-25")),
                 MeetingAction(title: "회의록 공유", owner: "전원")]
    a.entities = [MeetingEntity(name: "결제 API", kind: .system), MeetingEntity(name: "토스페이먼츠", kind: .org)]
    a.relations = [MeetingRelation(from: "결제 API", relation: "교체 후보", to: "토스페이먼츠")]

    var b = MeetingNote(title: "주간 회의", date: day("2026-10-05"), rawText: "디자인 시스템 진행 공유\n결제api 테스트 지연")
    b.status = .analyzed
    b.participants = ["김민지"]
    b.topics = [MeetingTopic(title: "디자인 시스템", points: ["컴포넌트 70% 완료"])]
    b.entities = [MeetingEntity(name: "결제api", kind: .concept), MeetingEntity(name: "디자인 시스템", kind: .project)]
    return [a, b]
}

@Suite struct MeetingParserTests {
    @Test func extractsJSONFromFencesAndChatter() {
        let text = "정리했어요!\n```json\n{\"title\":\"주간 회의\",\"decisions\":[\"배포는 금요일\"]}\n```\n끝"
        let obj = MeetingParser.jsonObject(from: text)
        #expect(obj?["title"] as? String == "주간 회의")
    }

    @Test func recoversTruncatedJSON() {
        // 토큰 한도로 할일 중간에서 끊긴 응답
        let text = #"{"title":"킥오프","decisions":["예산 확정"],"actions":[{"title":"견적 요청","owner":"박준호"},{"title":"일정 공"#
        let obj = MeetingParser.jsonObject(from: text)
        #expect(obj?["title"] as? String == "킥오프")
        #expect((obj?["decisions"] as? [String]) == ["예산 확정"])
        #expect(((obj?["actions"] as? [[String: Any]])?.first?["owner"] as? String) == "박준호")
    }

    @Test func returnsNilWithoutJSON() {
        #expect(MeetingParser.jsonObject(from: "죄송해요, 분석할 수 없어요") == nil)
    }

    @Test func appliesFieldsAndKeepsRegisteredTodosOnReanalysis() {
        var note = MeetingNote(title: "회의록", date: day("2026-10-01"), rawText: "…")
        let todoID = UUID()
        note.actions = [MeetingAction(title: "견적 요청", todoID: todoID)]
        let obj = MeetingParser.jsonObject(from: """
        {"title":"결제 회의","date":"2026-09-30","summary":"요약","participants":["김민지","김민지 "],
         "topics":[{"title":"PG 비교","points":["수수료"]}, "일정"],
         "decisions":[],
         "actions":[{"title":"견적  요청","owner":"박준호","due":"2026-10-03"}, "공유하기"],
         "entities":[{"name":"결제 API","type":"service"},{"name":"QA팀","type":"team"}],
         "relations":[{"from":"결제 API","rel":"담당","to":"QA팀"},{"from":"","rel":"x","to":"y"}]}
        """)!
        MeetingParser.apply(obj, to: &note)
        #expect(note.title == "결제 회의")
        #expect(note.date == day("2026-09-30"))
        #expect(note.participants == ["김민지"])
        #expect(note.topics.map(\.title) == ["PG 비교", "일정"])
        #expect(note.decisions.isEmpty)
        #expect(note.actions.count == 2)
        #expect(note.actions[0].todoID == todoID)   // 공백만 다른 같은 할일 → 연결 유지
        #expect(note.actions[0].due == day("2026-10-03"))
        #expect(note.actions[1].todoID == nil)
        #expect(note.entities.map(\.kind) == [.system, .org])
        #expect(note.relations.count == 1)
    }

    @Test func readsDateFromFileName() {
        #expect(MeetingParser.date(fromFileName: "2026-10-02 주간회의") == day("2026-10-02"))
        #expect(MeetingParser.date(fromFileName: "회의록_20261002") == day("2026-10-02"))
        #expect(MeetingParser.date(fromFileName: "2026년 9월 7일 킥오프") == day("2026-09-07"))
        #expect(MeetingParser.date(fromFileName: "2026-13-40 이상한 날짜") == nil)
        #expect(MeetingParser.date(fromFileName: "주간회의") == nil)
    }

    @Test func readsUTF8AndEUCKRFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chartodo-meeting-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        let utf8 = dir.appendingPathComponent("a.txt"), euckr = dir.appendingPathComponent("b.txt")
        try "회의록 내용".write(to: utf8, atomically: true, encoding: .utf8)
        try "한글 회의록".data(using: cp949)!.write(to: euckr)
        #expect(try MeetingParser.readText(at: utf8) == "회의록 내용")
        #expect(try MeetingParser.readText(at: euckr) == "한글 회의록")
    }

    @Test func actionBecomesTaggedTodo() {
        let m = sampleMeetings()[0]
        let todo = m.actions[0].makeTodo(meeting: m)
        #expect(todo.title == "PG사 견적 요청")
        #expect(todo.tags == ["회의"])
        #expect(todo.date == day("2026-09-25"))
        #expect(todo.notes.contains("결제 개편 킥오프"))
        #expect(todo.notes.contains("박준호"))
    }
}

@Suite struct KnowledgeGraphTests {
    @Test func mergesEntitiesAcrossMeetingsByName() {
        let ms = sampleMeetings()
        let g = KnowledgeGraph.build(from: ms)
        // "결제 API"(system)와 "결제api"(concept)는 같은 노드, 더 구체적인 종류가 남는다
        let api = g.node(KnowledgeGraph.entityID("결제 API"))
        #expect(api?.kind == .system)
        #expect(api?.meetingIDs == Set(ms.map(\.id)))
        // 두 회의 모두 참석한 사람
        #expect(g.node(KnowledgeGraph.entityID("김민지"))?.meetingIDs.count == 2)
    }

    @Test func linksOwnersMentionsAndRelations() {
        let ms = sampleMeetings()
        let g = KnowledgeGraph.build(from: ms)
        let action = "a:\(ms[0].actions[0].id)"
        #expect(g.neighbors(of: action).contains { $0.edge.relation == "담당" && $0.node.label == "박준호" })
        // "전원"은 사람 노드가 되지 않는다
        #expect(g.node(KnowledgeGraph.entityID("전원")) == nil)
        // 안건 제목에 개체 이름이 있으면 '언급'
        let topic = "t:\(ms[0].topics[0].id)"
        #expect(g.neighbors(of: topic).contains { $0.edge.relation == "언급" && $0.node.id == KnowledgeGraph.entityID("결제 API") })
        // LLM이 준 관계
        #expect(g.edges.contains { $0.relation == "교체 후보" && $0.target == KnowledgeGraph.entityID("토스페이먼츠") })
        #expect(g.hubs(limit: 2).map(\.id).contains(KnowledgeGraph.entityID("결제 API")))
    }

    @Test func skipsDateEndpointsInRelations() {
        var m = MeetingNote(title: "정산", date: day("2026-10-01"), rawText: "")
        m.entities = [MeetingEntity(name: "Kafka", kind: .system)]
        m.relations = [MeetingRelation(from: "Kafka", relation: "일정", to: "2026년 10월"),
                       MeetingRelation(from: "Kafka", relation: "기한", to: "2026-10-12"),
                       MeetingRelation(from: "Kafka", relation: "사용", to: "Superset")]
        let g = KnowledgeGraph.build(from: [m])
        #expect(g.node(KnowledgeGraph.entityID("2026년 10월")) == nil)
        #expect(g.node(KnowledgeGraph.entityID("2026-10-12")) == nil)
        #expect(g.node(KnowledgeGraph.entityID("Superset")) != nil)
        #expect(KnowledgeGraph.looksLikeDate("다음 주 금요일"))
        #expect(KnowledgeGraph.looksLikeDate("10/2"))
        #expect(!KnowledgeGraph.looksLikeDate("Q4 로드맵"))
    }

    @Test func keywordsDropParticlesAndQuestionWords() {
        // 지난(불용어) · 회의에서→회의(불용어) · 예산은→예산 · 얼마로→얼마(불용어) · 결정했지→결정(불용어)
        #expect(KnowledgeGraph.keywords(from: "지난 결제 API 회의에서 예산은 얼마로 결정했지?") == ["결제", "api", "예산"])
        #expect(KnowledgeGraph.keywords(from: "디자인시스템이 언제 끝나?").contains("디자인시스템"))
        #expect(KnowledgeGraph.keywords(from: "회의 내용 정리해줘").isEmpty)
    }

    @Test func ranksMeetingsByGraphAndRawText() {
        let ms = sampleMeetings()
        let g = KnowledgeGraph.build(from: ms)
        let (matches, nodes) = g.rank(ms, for: "토스페이먼츠 얘기 나온 회의 뭐였지?")
        #expect(matches.first?.meetingID == ms[0].id)
        #expect(nodes.first?.label == "토스페이먼츠")
        let design = g.rank(ms, for: "디자인 시스템 진행 상황").matches
        #expect(design.first?.meetingID == ms[1].id)
        #expect(g.rank(ms, for: "점심 메뉴").matches.isEmpty)
    }

    @Test func layoutIsDeterministicAndNormalized() {
        let ids = ["a", "b", "c", "d"]
        let links = [("a", "b"), ("b", "c"), ("c", "a")]
        let p1 = GraphLayout.compute(ids: ids, links: links, iterations: 60)
        let p2 = GraphLayout.compute(ids: ids, links: links, iterations: 60)
        #expect(p1 == p2)
        #expect(p1.values.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }
}

@Suite struct MeetingContextTests {
    @Test func includesRelevantMeetingGraphAndExcerpts() {
        let ms = sampleMeetings()
        let g = KnowledgeGraph.build(from: ms)
        let ctx = MeetingContextBuilder.build(question: "결제 API 예산 얼마였지?", meetings: ms, graph: g) { _ in nil }!
        #expect(ctx.contains("## 질문과 관련된 회의록"))
        #expect(ctx.contains("### 2026-09-21 · 결제 개편 킥오프"))
        #expect(ctx.contains("예산 3천만 원 확정"))
        #expect(ctx.contains("> 예산은 3천만 원으로 확정"))   // 원문 발췌
        #expect(ctx.contains("결제 API [시스템] — 회의 2건"))   // 여러 회의에 걸친 연결
    }

    @Test func fallsBackToRecentMeetingsAndListsOpenTasks() {
        let ms = sampleMeetings()
        let g = KnowledgeGraph.build(from: ms)
        let done = UUID()
        var withTodo = ms
        withTodo[0].actions[1].todoID = done
        let ctx = MeetingContextBuilder.build(question: "내가 해야 할 일 뭐 남았어?", meetings: withTodo, graph: g) { id in
            id == done ? true : nil
        }!
        #expect(ctx.contains("최근 회의록"))
        #expect(ctx.contains("## 회의에서 나온 할일 중 아직 안 끝난 것"))
        #expect(ctx.contains("PG사 견적 요청 (담당 박준호, 기한 2026-09-25)"))
        #expect(!ctx.contains("- 회의록 공유 (담당 전원, 앱 할일 완료) ←"))   // 끝난 할일은 남은 목록에서 빠진다
    }

    @Test func nilWithoutMeetings() {
        #expect(MeetingContextBuilder.build(question: "아무거나", meetings: [], graph: KnowledgeGraph()) { _ in nil } == nil)
    }

    @Test func systemPromptCarriesKnowledgeOnlyWhenGiven() {
        let ctx = AssistantContext(now: day("2026-10-08"), today: [], overdue: [], weekGoals: [], monthGoals: [], upcoming: [],
                                   events: [], upcomingEvents: [], completedToday: [], yesterdayPlan: nil, todayJournal: nil)
        let plain = PromptBuilder.systemPrompt(name: "비서", tone: .friend, context: ctx)
        #expect(!plain.contains("회의록 지식"))
        let with = PromptBuilder.systemPrompt(name: "비서", tone: .friend, context: ctx, knowledge: "## 회의록 목록\n- 2026-10-05 주간 회의")
        #expect(with.contains("[회의록 질문 규칙]"))
        #expect(with.hasSuffix("- 2026-10-05 주간 회의"))
    }

    @Test func meetingPromptTruncatesLongNotes() {
        let p = PromptBuilder.meetingPrompt(text: String(repeating: "가", count: 50), baseDate: day("2026-10-08"), limit: 10)
        #expect(p.contains("…(이하 생략)"))
        #expect(p.contains("2026-10-08"))
    }
}

@MainActor @Suite struct MeetingStoreTests {
    @Test func analyzeAppliesResultAndRebuildsGraph() async {
        let store = MeetingStore(persists: false)
        store.analyzer = { prompt in
            #expect(prompt.contains("배포 일정"))
            return #"{"title":"배포 회의","participants":["이서연"],"actions":[{"title":"릴리스 노트 작성","owner":"이서연"}],"entities":[{"name":"CharTodo","type":"project"}]}"#
        }
        var analyzed: MeetingNote?
        store.onAnalyzed = { analyzed = $0 }
        let id = store.add(text: "배포 일정 논의", title: "메모", date: day("2026-10-01"))
        await store.analyze(id)
        let m = store.meeting(id: id)
        #expect(m?.status == .analyzed)
        #expect(m?.title == "배포 회의")
        #expect(analyzed?.id == id)
        #expect(store.graph.node(KnowledgeGraph.entityID("chartodo"))?.kind == .project)
        store.delete(id)
        #expect(store.graph.isEmpty)
    }

    @Test func analysisFailureIsRecorded() async {
        let store = MeetingStore(persists: false)
        store.analyzer = { _ in "JSON이 아닌 답변" }
        let id = store.add(text: "내용", title: "회의", date: Date())
        await store.analyze(id)
        #expect(store.meeting(id: id)?.status == .failed)
        #expect(store.meeting(id: id)?.errorMessage?.contains("JSON") == true)
    }

    @Test func newestMeetingFirstAndTodoLinking() {
        let store = MeetingStore(persists: false)
        let old = store.add(text: "a", title: "옛날", date: day("2026-09-01"))
        let new = store.add(text: "b", title: "최근", date: day("2026-10-01"))
        #expect(store.meetings.map(\.id) == [new, old])
        store.mutate(old) { $0.actions = [MeetingAction(title: "할일")] }
        let actionID = store.meeting(id: old)!.actions[0].id
        let todoID = UUID()
        store.setTodoID(todoID, meeting: old, action: actionID)
        #expect(store.meeting(id: old)?.actions[0].todoID == todoID)
    }
}
