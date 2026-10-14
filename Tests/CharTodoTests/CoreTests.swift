import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import CharTodo

@Suite struct QuickAddParserTests {
    let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 7; c.hour = 10
        return AppCalendar.current.date(from: c)!
    }()

    @Test func parsesQuadrantDateTimeAndSubtasks() {
        let r = QuickAddParser(now: now).parse("보고서 작성 !1 @내일 ~14:30 > 자료조사, 초안, 검토")
        #expect(r.title == "보고서 작성")
        #expect(r.quadrant == .doFirst)
        #expect(r.date == now.startOfDay.adding(days: 1))
        #expect(AppCalendar.current.component(.hour, from: r.time!) == 14)
        #expect(AppCalendar.current.component(.minute, from: r.time!) == 30)
        #expect(r.subtasks == ["자료조사", "초안", "검토"])
    }

    @Test func parsesScopeAndKoreanTime() {
        let r = QuickAddParser(now: now).parse("운동 3회 #주간 ~오후3시")
        #expect(r.scope == .week)
        #expect(r.title == "운동 3회")
        #expect(AppCalendar.current.component(.hour, from: r.time!) == 15)
    }

    @Test func weekdayTokenPointsToNextOccurrence() {
        // 2026-10-07 은 수요일 → @금 은 10/9, @수 는 다음 주 10/14
        let p = QuickAddParser(now: now)
        #expect(p.parseDate("금")?.dayNumber == 9)
        #expect(p.parseDate("수")?.dayNumber == 14)
        #expect(p.parseDate("10/12")?.dayNumber == 12)
    }

    @Test func makeTodoDropsTimeForNonDayScope() {
        let item = QuickAddParser(now: now).makeTodo(from: "책 읽기 #월간 ~9시", defaultDate: now, defaultScope: .day)
        #expect(item?.scope == .month)
        #expect(item?.time == nil)
        #expect(item?.date == now.startOfMonth)
    }

    @Test func emptyTitleReturnsNil() {
        #expect(QuickAddParser(now: now).makeTodo(from: "!1 @내일", defaultDate: now, defaultScope: .day) == nil)
    }
}

@Suite struct PromptBuilderTests {
    @Test func parsesAddSuggestionsAndHidesTags() {
        let text = "좋아요!\n[[ADD|기획서 초안|2026-10-08|day|Q1]]\n[[ADD|운동|2026-10-05|week|]]"
        let s = PromptBuilder.parseSuggestions(text)
        #expect(s.count == 2)
        #expect(s[0].title == "기획서 초안")
        #expect(s[0].quadrant == .doFirst)
        #expect(s[1].scope == .week)
        #expect(s[1].quadrant == nil)
        #expect(PromptBuilder.displayText(text) == "좋아요!")
    }

    @Test func hidesPartialTagWhileStreaming() {
        #expect(PromptBuilder.displayText("오늘 할 일은\n[[ADD|기획") == "오늘 할 일은")
    }

    @Test func parsesBulletAndNumberedLists() {
        let items = PromptBuilder.parseList("다음과 같아요\n- 자료 조사\n2. **초안** 작성\n* [ ] 검토 요청\n잡담")
        #expect(items == ["자료 조사", "초안 작성", "검토 요청"])
    }

    @Test func personaBlockIncludesEndingCatchphrasesAndSituations() {
        var p = PersonaConfig()
        p.sentenceEnding = "~다냥"
        p.catchphrases = ["하암~"]
        p.situationLines = ["taskDone": ["읏차! 하나 끝!"]]
        p.avoid = "반말"
        let block = PromptBuilder.personaBlock(tone: .friend, persona: p)
        #expect(block.contains("~다냥"))
        #expect(block.contains("\"하암~\""))
        #expect(block.contains("읏차! 하나 끝!"))
        #expect(block.contains("피할 표현: 반말"))
    }

    @Test func personaPickSubstitutesPlaceholders() {
        var p = PersonaConfig()
        p.situationLines = ["overdue": ["{이름}: 밀린 일 {n}개!"]]
        #expect(p.pick(.overdue, name: "시사", count: 3) == "시사: 밀린 일 3개!")
        // 비어 있으면 기본 문구
        #expect(!PersonaConfig().pick(.taskDone, name: "x").isEmpty)
    }
}

@Suite struct ClaudeStreamParserTests {
    @Test func streamsPartialTextDeltas() {
        var parser = ClaudeStreamParser()
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"안녕"}}}"#
        #expect(parser.consume(delta) == [.text("안녕")])
        // 부분 메시지를 받았으면 완성 메시지와 result는 중복 출력하지 않는다
        let full = #"{"type":"assistant","message":{"model":"claude","content":[{"type":"text","text":"안녕"}]}}"#
        #expect(parser.consume(full).isEmpty)
        #expect(parser.consume(#"{"type":"result","is_error":false,"result":"안녕"}"#).isEmpty)
    }

    @Test func reportsAuthErrorFromResult() {
        var parser = ClaudeStreamParser()
        let synthetic = #"{"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"Failed to authenticate"}]}}"#
        #expect(parser.consume(synthetic).isEmpty)
        let result = #"{"type":"result","subtype":"success","is_error":true,"result":"Failed to authenticate"}"#
        #expect(parser.consume(result) == [.error("Failed to authenticate")])
    }

    @Test func fallsBackToResultText() {
        var parser = ClaudeStreamParser()
        #expect(parser.consume(#"{"type":"result","is_error":false,"result":"끝"}"#) == [.text("끝")])
    }

    @Test func flattensConversationForCLI() {
        let s = ClaudeCodeClient.flatten([LLMMessage(role: .user, content: "a"), LLMMessage(role: .assistant, content: "b"),
                                         LLMMessage(role: .user, content: "c")])
        #expect(s.contains("사용자: a"))
        #expect(s.contains("어시스턴트: b"))
        #expect(s.hasSuffix("[현재 메시지]\nc"))
    }
}

@Suite struct SettingsMergingTests {
    @Test func missingKeysFallBackToDefaults() {
        let json = #"{"themeID":"crt","llm":{"provider":"anthropic"},"character":{"size":150}}"#
        let s = DefaultsMerging.decode(Data(json.utf8), defaults: AppSettings())
        #expect(s.themeID == "crt")
        #expect(s.llm.provider == .anthropic)
        #expect(s.llm.ollamaBaseURL == LLMConfig().ollamaBaseURL)
        #expect(s.character.size == 150)
        #expect(s.character.face.style == .draw)
        #expect(s.persona == PersonaConfig())
    }

    @Test func anthropicBodyUsesEffortAndFallbacksOnlyWhereSupported() {
        let opus = AnthropicClient(apiKey: "k", model: "claude-opus-5-5", effort: "low")
            .requestBody(system: "s", messages: [LLMMessage(role: .user, content: "hi")])
        #expect((opus["output_config"] as? [String: String])?["effort"] == "low")
        #expect(opus["fallbacks"] as? String == "default")
        let haiku = AnthropicClient(apiKey: "k", model: "claude-haiku-4-5", effort: "low")
            .requestBody(system: "s", messages: [])
        #expect(haiku["output_config"] == nil)
        #expect(haiku["fallbacks"] == nil)
    }
}

@Suite struct CharacterPoseTests {
    @Test func happyRaisesArmsAndTalkingOpensMouth() {
        let rig = CharacterRig()
        let happy = CharacterPose.compute(rig: rig, mood: .happy, time: 0.3)
        #expect(happy.leftArm < -100 && happy.rightArm > 100)
        let talking = (0..<20).map { CharacterPose.compute(rig: rig, mood: .talking, time: Double($0) * 0.05).mouthOpen }
        #expect(talking.max()! > 0.6)
        #expect(CharacterPose.compute(rig: rig, mood: .idle, time: 1).mouthOpen == 0)
    }

    @Test func layoutLeavesRoomForLimbs() {
        let layout = CharacterLayout(rig: CharacterRig(), aspect: 1)
        #expect(layout.canvasSize.width > layout.bodySize.width)
        #expect(layout.bodyOrigin.y > 0)
        #expect(layout.canvasSize.height > layout.bodyOrigin.y + layout.bodySize.height)
    }
}

@MainActor @Suite struct TodoStoreTests {
    @Test func subtasksDriveParentCompletion() {
        let store = TodoStore(persists: false)
        var item = TodoItem(title: "보고서")
        item.subtasks = [SubTask(title: "a"), SubTask(title: "b")]
        store.add(item)
        store.toggleSubtask(item.id, item.subtasks[0].id)
        #expect(store.todo(id: item.id)?.isDone == false)
        store.toggleSubtask(item.id, item.subtasks[1].id)
        #expect(store.todo(id: item.id)?.isDone == true)
        #expect(store.todo(id: item.id)?.completedAt != nil)
        store.toggleSubtask(item.id, item.subtasks[1].id)
        #expect(store.todo(id: item.id)?.isDone == false)
    }

    @Test func overdueAndMoveToToday() {
        let store = TodoStore(persists: false)
        let old = TodoItem(title: "어제 일", date: Date().adding(days: -2))
        store.add(old)
        #expect(store.overdue().map(\.id) == [old.id])
        store.moveOverdueToToday()
        #expect(store.overdue().isEmpty)
        #expect(store.todos(on: Date()).map(\.id) == [old.id])
    }

    @Test func scopesNormalizeDates() {
        let store = TodoStore(persists: false)
        store.add(TodoItem(title: "주간", scope: .week, date: Date()))
        store.add(TodoItem(title: "월간", scope: .month, date: Date()))
        #expect(store.weekGoals(for: Date()).count == 1)
        #expect(store.monthGoals(for: Date().adding(days: 1).startOfMonth).count == (Date().adding(days: 1).isSameMonth(as: Date()) ? 1 : 0))
    }

    @Test func journalSavesOnlyNonEmptyEntries() {
        let store = TodoStore(persists: false)
        store.saveJournal(JournalEntry(date: Date()))
        #expect(store.journals.isEmpty)
        var entry = store.journal(for: Date())
        entry.work = "- 배포"
        store.saveJournal(entry)
        #expect(store.journals.count == 1)
        #expect(store.journal(for: Date()).work == "- 배포")
    }
}

@Suite struct TagTests {
    @Test func quickAddParsesTagsButKeepsScopeKeywords() {
        let r = QuickAddParser().parse("기획서 #업무 #중요 #주간 !2")
        #expect(r.title == "기획서")
        #expect(r.tags == ["업무", "중요"])
        #expect(r.scope == .week)
        #expect(r.quadrant == .schedule)
    }

    @Test func normalizesTagNames() {
        #expect(Tag.normalize("  ##사이드 프로젝트 ") == "사이드-프로젝트")
        #expect(Tag.normalizeList(["업무", "#업무", "", "공부"]) == ["업무", "공부"])
    }

    @Test func paletteIsStableAndRespectsOverride() {
        #expect(TagPalette.hex(for: "업무", overrides: [:]) == TagPalette.hex(for: "업무", overrides: [:]))
        #expect(TagPalette.hex(for: "업무", overrides: ["업무": "#123456"]) == "#123456")
    }

    @MainActor @Test func storeCountsRenamesAndDeletesTags() {
        let store = TodoStore(persists: false)
        let a = TodoItem(title: "a", tags: ["업무"])
        var b = TodoItem(title: "b", tags: ["업무", "공부"])
        b.isDone = true
        store.add(a)
        store.add(b)
        store.add(TodoItem(title: "c"))
        #expect(store.tagStats.first?.name == "업무")
        #expect(store.tagStats.first?.open == 1)
        #expect(store.tagStats.first?.total == 2)
        #expect(store.todos(tag: nil).map(\.title) == ["c"])

        store.renameTag("공부", to: "업무")   // 합치기
        #expect(store.todo(id: b.id)?.tags == ["업무"])
        #expect(store.allTags == ["업무"])

        store.toggleTag(a.id, "#개인")
        #expect(store.todo(id: a.id)?.tags == ["업무", "개인"])
        store.deleteTag("업무")
        #expect(store.todos(tag: "업무").isEmpty)
        #expect(store.allTags == ["개인"])
    }
}

@Suite struct ChatAddTests {
    @Test func parsesJSONAddWithAllFields() {
        let text = """
        내일 회의 추가했어요!
        [[ADD {"title":"팀 회의","date":"2026-10-08","time":"15:30","duration":90,"quadrant":1,"tags":["업무","#회의"],"subtasks":["안건 정리","자료 출력"],"notes":"3층","calendar":true}]]
        [[SUGGEST {"title":"회의록 정리","date":"2026-10-08","quadrant":"Q2","tags":"업무, 기록"}]]
        """
        let s = PromptBuilder.parseSuggestions(text)
        #expect(s.count == 2)
        #expect(s[0].kind == .add)
        #expect(s[0].hour == 15 && s[0].minute == 30)
        #expect(s[0].duration == 90)
        #expect(s[0].tags == ["업무", "회의"])
        #expect(s[0].subtasks == ["안건 정리", "자료 출력"])
        #expect(s[0].notes == "3층")
        #expect(s[0].addToCalendar)
        #expect(s[1].kind == .suggest)
        #expect(s[1].quadrant == .schedule)
        #expect(s[1].tags == ["업무", "기록"])
        #expect(PromptBuilder.displayText(text) == "내일 회의 추가했어요!")
    }

    @Test func makeTodoFillsTimeTagsAndSubtasks() {
        var s = TodoSuggestion(kind: .add, title: "팀 회의")
        s.date = DateFormatters.dayKey.date(from: "2026-10-08")
        s.hour = 15; s.minute = 30; s.duration = 90
        s.tags = ["업무"]; s.subtasks = ["안건"]; s.quadrant = .doFirst; s.notes = "3층"
        let t = s.makeTodo()
        #expect(t.date.dayKey == "2026-10-08")
        #expect(t.scheduledStart.map { DateFormatters.time.string(from: $0) } == "15:30")
        #expect(t.scheduledStart?.dayKey == "2026-10-08")
        #expect(t.durationMinutes == 90)
        #expect(t.tags == ["업무"])
        #expect(t.subtasks.map(\.title) == ["안건"])
        #expect(t.quadrant == .doFirst)
        #expect(t.notes == "3층")
    }

    @Test func timeIsIgnoredForWeekScope() {
        var s = TodoSuggestion(kind: .add, title: "운동 3회", scope: .week)
        s.hour = 7
        #expect(s.makeTodo().time == nil)
    }

    @Test func hidesPartialJSONTagWhileStreaming() {
        #expect(PromptBuilder.displayText("추가할게요\n[[ADD {\"title\":\"팀") == "추가할게요")
    }

    @Test func invalidJSONIsSkipped() {
        #expect(PromptBuilder.parseSuggestions("[[ADD {title: 팀 회의}]]").isEmpty)
    }

    @Test func dateTableCoversTwoWeeks() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 7
        let table = PromptBuilder.dateTable(from: AppCalendar.current.date(from: c)!)
        #expect(table.contains("10/7(수) 오늘"))
        #expect(table.contains("10/8(목) 내일"))
        #expect(table.contains("= 2026-10-20"))
    }
}

@Suite struct MotionTests {
    @Test func hopCrouchesThenFliesThenLands() {
        let crouch = Motion.hop(0.15, height: 0.3, squash: 1)
        #expect(crouch.y == 0 && crouch.sy < 1 && crouch.sx > 1)        // 웅크림
        let apex = Motion.hop(0.45, height: 0.3, squash: 1)
        #expect(apex.y < -0.29 && apex.air > 0.99)                       // 최고점
        let land = Motion.hop(0.77, height: 0.3, squash: 1)
        #expect(land.y == 0 && land.sy < 0.95)                           // 착지 찌그러짐
        #expect(abs(Motion.hop(1, height: 0.3, squash: 1).sy - 1) < 0.02) // 원래대로
    }

    @Test func keyframesInterpolateSmoothly() {
        let frames: [(Double, Double)] = [(0, 0), (0.5, 1), (1, 0)]
        #expect(Motion.keyframes(0, frames) == 0)
        #expect(Motion.keyframes(0.5, frames) == 1)
        #expect(Motion.keyframes(0.25, frames) == 0.5)
    }

    @Test func actionsOnlyApplyWhenIdleOrListening() {
        let rig = CharacterRig()
        let hop = ActionState(.hop, start: 0)
        #expect(CharacterPose.compute(rig: rig, mood: .idle, time: 0.43, action: hop).offsetY < -0.2)
        #expect(CharacterPose.compute(rig: rig, mood: .talking, time: 0.43, action: hop).offsetY > -0.05)
        let turn = CharacterPose.compute(rig: rig, mood: .idle, time: 0.375, action: ActionState(.turnAround, start: 0))
        #expect(abs(turn.turn) < 0.05)                                    // 반쯤 돌았을 때 납작
    }
}

@Suite struct PuppetBuilderTests {
    /// 크림색 동그란 몸 + 왼쪽으로 튀어나온 짧은 팔 (갈색 윤곽선)
    func makeCharacter() -> CGImage {
        let n = 200
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let ink = CGColor(red: 0.2, green: 0.1, blue: 0.07, alpha: 1)
        let cream = CGColor(red: 0.98, green: 0.94, blue: 0.83, alpha: 1)
        // CG 좌표: 아래가 0 → 화면 위쪽 y=90 은 CG y=110
        ctx.setFillColor(ink); ctx.fillEllipse(in: CGRect(x: 6, y: 92, width: 46, height: 22))     // 팔 윤곽
        ctx.setFillColor(cream); ctx.fillEllipse(in: CGRect(x: 10, y: 96, width: 40, height: 14))  // 팔 속살
        ctx.setFillColor(ink); ctx.fillEllipse(in: CGRect(x: 30, y: 30, width: 140, height: 140))  // 몸 윤곽
        ctx.setFillColor(cream); ctx.fillEllipse(in: CGRect(x: 35, y: 35, width: 130, height: 130))
        return ctx.makeImage()!
    }

    @Test func cutsArmAndHealsBodyOutline() {
        var rig = CharacterRig()
        rig.limbMode = .cutout
        rig.face.skinHex = "#FAF0D4"
        rig.limbColorHex = "#331A12"
        for kind in LimbKind.allCases { var l = rig.limb(kind); l.enabled = kind == .leftArm; rig.setLimb(kind, l) }
        var arm = rig.leftArm
        arm.grabPoint = CGPoint(x: 18.0 / 200, y: 97.0 / 200)    // 팔 속살 위 (화면 좌표)
        rig.leftArm = arm

        let image = makeCharacter()
        let result = PuppetBuilder.build(image: image, rig: rig)
        #expect(result != nil)
        #expect(result?.parts["leftArm"] != nil)
        guard let body = result?.body.cgImageValue, let bmp = PuppetBuilder.Bitmap(body),
              let part = result?.parts["leftArm"]?.cgImageValue, let pbmp = PuppetBuilder.Bitmap(part) else { return }
        // 팔이 있던 자리(몸 밖)는 몸통에서 비고, 조각에는 남아 있다
        #expect(bmp.alpha(16, 97) == 0)
        #expect(pbmp.alpha(16, 97) > 200)
        // 몸통 가운데는 그대로
        #expect(bmp.alpha(100, 100) > 200)
        // 팔이 붙어 있던 몸 가장자리(x≈32)에는 윤곽선(어두운 색)이 이어져 있다
        let edgeDark = (30...40).contains { x in bmp.alpha(x, 97) > 200 && bmp.lum(x, 97) < 125 }
        #expect(edgeDark)
        // 관절 자동 맞춤 후보가 몸 가장자리 근처에 생긴다
        if let p = result?.suggestedPivots["leftArm"] { #expect(p.x > 0.1 && p.x < 0.25) }
    }
}

@Suite struct PuppetDebugTests {
    /// CHARTODO_TEST_IMAGE 가 있을 때만 실제 이미지로 반경별 값을 출력 (진단용)
    @Test func realImageDiagnostics() {
        guard let path = ProcessInfo.processInfo.environment["CHARTODO_TEST_IMAGE"],
              let img = NSImage(contentsOfFile: path)?.cgImageValue else { return }
        var rig = CharacterRig()
        rig.limbMode = .cutout
        rig.face.skinHex = "#FAEFD3"
        rig.limbColorHex = "#321B12"
        for (k, g) in [(LimbKind.leftArm, CGPoint(x: 0.179, y: 0.704)), (.rightArm, CGPoint(x: 0.829, y: 0.704)),
                       (.leftLeg, CGPoint(x: 0.386, y: 0.968)), (.rightLeg, CGPoint(x: 0.614, y: 0.968))] {
            var l = rig.limb(k); l.grabPoint = g; rig.setLimb(k, l)
        }
        print("== \(img.width)x\(img.height)")
        let r = PuppetBuilder.build(image: img, rig: rig)
        print("PARTS", r?.parts.keys.sorted() ?? [], "PIVOTS", r?.suggestedPivots.mapValues { "(\(Int($0.x * 140)),\(Int($0.y * 125)))" } ?? [:])
    }
}
