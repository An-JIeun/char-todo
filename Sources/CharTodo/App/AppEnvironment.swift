import Foundation
import Observation
import AppKit
import SwiftUI

/// 캐릭터의 일시적 상태 (말풍선, 축하 모션)
@MainActor
@Observable
final class CompanionState {
    private(set) var bubble: String?
    private(set) var transientMood: CharacterMood?
    @ObservationIgnored private var bubbleWork: DispatchWorkItem?
    @ObservationIgnored private var moodWork: DispatchWorkItem?

    func say(_ text: String, duration: TimeInterval = 5) {
        bubble = text
        bubbleWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.bubble = nil }
        bubbleWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
    }

    func dismissBubble() {
        bubbleWork?.cancel()
        bubble = nil
    }

    func flash(_ mood: CharacterMood, duration: TimeInterval = 2.2) {
        transientMood = mood
        moodWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.transientMood = nil }
        moodWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
    }

    func celebrate(_ line: String) {
        flash(.happy)
        say(line, duration: 3)
    }
}

/// 앱 전역 객체 묶음. SwiftUI 씬과 AppKit 플로팅 패널이 같은 인스턴스를 공유한다.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let store: TodoStore
    let settings: SettingsStore
    let calendar: CalendarService
    let meetings: MeetingStore
    let companion = CompanionState()
    private(set) var chat: ChatController!
    private(set) var floating: FloatingController!
    private(set) var director: CharacterDirector!
    private(set) var career: CareerSupportService!

    private var briefingTimer: Timer?

    private init() {
        store = TodoStore()
        settings = SettingsStore()
        calendar = CalendarService()
        meetings = MeetingStore()
        chat = ChatController(env: self)
        floating = FloatingController(env: self)
        director = CharacterDirector(env: self)
        career = CareerSupportService(env: self)

        // 회의록 정리 JSON은 길어서 토큰 한도를 넉넉히 잡는다
        meetings.analyzer = { [weak self] prompt in
            guard let self else { throw CancellationError() }
            return try await self.chat.oneShot(prompt, minTokens: 4096)
        }
        meetings.onAnalyzed = { [weak self] m in
            guard let self, self.settings.settings.showFloatingCharacter else { return }
            let found = m.actions.isEmpty ? "" : " 할일 \(m.actions.count)개도 찾았어요 📌"
            self.companion.flash(.happy, duration: 1.5)
            self.companion.say("'\(m.title)' 회의록 정리 끝!\(found)", duration: 6)
        }

        calendar.enabled = settings.settings.calendarEnabled
        calendar.hiddenCalendarIDs = Set(settings.settings.hiddenCalendarIDs)

        store.onMutation = { [weak self] m in self?.handle(m) }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.floating.refreshMainWindow()
                self?.floating.appActive = true
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.floating.appActive = false }
        }
        settings.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
    }

    func start() {
        floating.applyVisibility()
        director.start()
        startBriefingTimer()
        career.start()
        greet()
        DevSnapshot.runIfRequested()
    }

    /// 앱을 켤 때 인사 → 밀린 일이 있으면 알림 (말투 설정의 상황별 표현 사용)
    private func greet() {
        let s = settings.settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, s.showFloatingCharacter else { return }
            self.companion.flash(.happy, duration: 1.5)
            self.companion.say(s.persona.pick(.greeting, name: s.assistantName), duration: 5)
        }
        let overdue = store.overdue().count
        guard overdue > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self, !self.floating.isChatVisible else { return }
            let p = self.settings.settings
            self.companion.say(p.persona.pick(.overdue, name: p.assistantName, count: overdue), duration: 7)
        }
    }

    /// 말투 설정의 상황별 표현 하나
    func line(_ situation: PersonaSituation, count: Int? = nil) -> String {
        let s = settings.settings
        return s.persona.pick(situation, name: s.assistantName, count: count)
    }

    func flush() {
        store.writeNow()
        settings.writeNow()
        meetings.writeNow()
    }

    /// 앱 종료: CharTodo가 켠 career-support 서버 정리 + 저장
    func shutdown() {
        career.shutdown()
        flush()
    }

    // MARK: 변경 처리

    private func handle(_ m: TodoMutation) {
        calendar.sync(m)
        let s = settings.settings
        switch m {
        case let .added(item):
            autoLinkCalendar(item, enabled: s.autoAddTimedTodosToCalendar)
        case let .updated(old, new):
            if !old.isDone && new.isDone && s.celebrateOnComplete {
                let today = store.todos(on: Date())
                let allDone = new.scope == .day && new.date.isToday && today.allSatisfy(\.isDone)
                companion.celebrate(line(allDone ? .allDone : .taskDone))
            }
            if old.scheduledStart == nil { autoLinkCalendar(new, enabled: s.autoAddTimedTodosToCalendar) }
        case .deleted:
            break
        }
    }

    private func autoLinkCalendar(_ item: TodoItem, enabled: Bool) {
        guard enabled, calendar.enabled, calendar.canWrite, item.scheduledStart != nil, item.calendarEventID == nil else { return }
        if let id = calendar.createEvent(for: item) {
            store.mutate(item.id) { $0.calendarEventID = id }
        }
    }

    func linkToCalendar(_ id: UUID) {
        guard let item = store.todo(id: id) else { return }
        if let eventID = calendar.createEvent(for: item) {
            store.mutate(id) { $0.calendarEventID = eventID }
            companion.say("캘린더에 추가했어요 📅", duration: 2.5)
        }
    }

    func unlinkFromCalendar(_ id: UUID) {
        guard let item = store.todo(id: id), let eventID = item.calendarEventID else { return }
        calendar.removeEvent(id: eventID)
        store.mutate(id) { $0.calendarEventID = nil }
    }

    private func settingsChanged(_ old: AppSettings, _ new: AppSettings) {
        calendar.enabled = new.calendarEnabled
        calendar.hiddenCalendarIDs = Set(new.hiddenCalendarIDs)
        if old.showFloatingCharacter != new.showFloatingCharacter || old.roamInApp != new.roamInApp { floating.applyVisibility() }
        if old.character != new.character {
            floating.layoutForRig()
            director.settingsChanged()
        }
        if old.llm.claudeCodePath != new.llm.claudeCodePath { ClaudeCodeLocator.resetCache() }
        // career-support 연동을 켜거나 폴더·가져오기 조건을 바꾸면 바로 한 번 읽는다
        let oc = old.career, nc = new.career
        if (nc.syncEnabled && !oc.syncEnabled) || oc.path != nc.path
            || (nc.syncEnabled && (oc.statuses != nc.statuses || oc.tag != nc.tag)) {
            Task { await career.sync(manual: true) }
        }
    }

    // MARK: 어시스턴트 컨텍스트

    func assistantContext(now: Date = Date()) -> AssistantContext {
        let today = now.startOfDay
        let upcoming = (1...3).map { offset -> (Date, [TodoItem]) in
            let d = today.adding(days: offset)
            return (d, store.todos(on: d).filter { !$0.isDone })
        }
        let yesterday = store.journals.first { $0.date.isSameDay(as: today.adding(days: -1)) }
        let upcomingEvents = calendar.events(from: today.adding(days: 1), to: today.adding(days: 4))
        return AssistantContext(
            now: now,
            today: store.todos(on: today),
            overdue: store.overdue(now: now),
            weekGoals: store.weekGoals(for: today),
            monthGoals: store.monthGoals(for: today),
            upcoming: upcoming,
            events: calendar.events(on: today),
            upcomingEvents: upcomingEvents,
            completedToday: store.completed(on: today),
            yesterdayPlan: yesterday?.plan,
            todayJournal: store.journals.first { $0.date.isSameDay(as: today) },
            knownTags: store.allTags
        )
    }

    /// 채팅 제안을 모든 필드(시간·태그·세부·메모·소요 시간)를 채워 등록한다.
    /// 같은 제목·날짜·범위의 할일이 이미 있으면 새로 만들지 않고 기존 id를 돌려준다.
    @discardableResult
    func addSuggestion(_ s: TodoSuggestion) -> UUID {
        let item = s.makeTodo()
        if let existing = store.todos.first(where: {
            $0.title == item.title && $0.scope == item.scope && $0.date == item.date && !$0.isDone
        }) {
            return existing.id
        }
        store.add(item)
        if s.addToCalendar, calendar.enabled, calendar.canWrite, store.todo(id: item.id)?.calendarEventID == nil {
            linkToCalendar(item.id)
        }
        return item.id
    }

    // MARK: 회의록

    /// 질문과 관련된 회의록 지식 (회의록이 없으면 nil)
    func meetingKnowledge(for question: String) -> String? {
        meetings.knowledgeContext(for: question) { [store] id in store.todo(id: id)?.isDone }
    }

    /// 회의 할일을 앱 할일로 등록한다. 이미 등록돼 있고 지워지지 않았으면 건너뛴다. 새로 등록한 개수를 돌려준다.
    @discardableResult
    func addMeetingActions(_ meetingID: UUID, actionIDs: [UUID]? = nil) -> Int {
        guard let m = meetings.meeting(id: meetingID) else { return 0 }
        var added = 0
        for a in m.actions where actionIDs?.contains(a.id) ?? true {
            if let existing = a.todoID, store.todo(id: existing) != nil { continue }
            let item = a.makeTodo(meeting: m)
            store.add(item)
            meetings.setTodoID(item.id, meeting: m.id, action: a.id)
            added += 1
        }
        if added > 0 { companion.say("회의 할일 \(added)개 등록! 📌", duration: 3) }
        return added
    }

    /// 질문봇을 열고 이 회의에 대해 묻는다.
    func askAboutMeeting(_ id: UUID) {
        guard let m = meetings.meeting(id: id) else { return }
        floating.showChat()
        chat.send("\(m.date.dayKey) '\(m.title)' 회의 내용을 정리해 주고, 내가 챙겨야 할 할일과 다음에 확인할 점을 알려 줘.")
    }

    // MARK: 자동 브리핑

    private func startBriefingTimer() {
        briefingTimer?.invalidate()
        briefingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAutoBriefing() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.checkAutoBriefing() }
    }

    func checkAutoBriefing(now: Date = Date()) {
        let s = settings.settings
        guard s.autoBriefingEnabled, s.lastAutoBriefingDay != now.dayKey else { return }
        let cal = AppCalendar.current
        let h = cal.component(.hour, from: now), m = cal.component(.minute, from: now)
        guard h * 60 + m >= s.autoBriefingHour * 60 + s.autoBriefingMinute else { return }
        settings.settings.lastAutoBriefingDay = now.dayKey
        floating.showChat()
        chat.briefing(.today)
    }

    // MARK: 창

    /// 태그 화면에서 해당 태그로 모아 보기
    func openTag(_ tag: String) {
        pendingTag = tag
        openMainWindow()
        NotificationCenter.default.post(name: .navigateRequest, object: "tags")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .tagSelectRequest, object: tag)
        }
    }

    /// 태그 화면이 처음 나타날 때 선택할 태그
    var pendingTag: String?

    func tagColor(_ tag: String) -> Color {
        TagPalette.color(for: tag, overrides: settings.settings.tagColors)
    }

    /// 메인 창의 설정 화면에서 특정 탭을 연다.
    func openSettings(tab: String) {
        openMainWindow()
        NotificationCenter.default.post(name: .navigateRequest, object: "settings")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .settingsTabRequest, object: tab)
        }
    }

    /// chartodo:// 링크 (career-support 웹 화면의 바로 가기 등)
    /// open · today|week|month|matrix|tags|journal|settings|meetings · career(취업 태그 모아보기) · tag/<태그> · sync(공고 다시 읽기)
    /// web[/jobs|strategy|portfolio|generate|dashboard|config] (career-support 웹 화면 — 단축어·Raycast 등에서 바로 가기)
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "chartodo" else { return }
        let target = (url.host ?? "").lowercased()
        switch target {
        case "career":
            let tag = Tag.normalize(settings.settings.career.tag)
            if tag.isEmpty { openMainWindow() } else { openTag(tag) }
        case "tag":
            let tag = url.pathComponents.dropFirst().joined(separator: "/")
            if tag.isEmpty { openMainWindow() } else { openTag(tag) }
        case "sync":
            openMainWindow()
            Task { await career.sync(manual: true) }
        case "web":
            career.open(CareerPage(rawValue: url.pathComponents.dropFirst().first ?? "") ?? .jobs)
        default:
            openMainWindow()
            if AppSection(rawValue: target) != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .navigateRequest, object: target)
                }
            }
        }
    }

    /// SwiftUI의 openWindow 액션 (메인 창이 닫혀 있을 때 다시 열기 위해 보관)
    var openWindowAction: OpenWindowAction?

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.identifier?.rawValue.hasPrefix("main") == true }),
           window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else if let open = openWindowAction {
            open(id: "main")
        }
    }
}

extension Notification.Name {
    static let navigateRequest = Notification.Name("CharTodo.navigate")
    /// 설정 화면의 특정 탭 열기 (object: SettingsTab.rawValue)
    static let settingsTabRequest = Notification.Name("CharTodo.settingsTab")
    /// 태그 화면에서 특정 태그 선택 (object: 태그 이름)
    static let tagSelectRequest = Notification.Name("CharTodo.tagSelect")
}
