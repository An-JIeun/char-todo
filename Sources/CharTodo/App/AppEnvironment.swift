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
    let companion = CompanionState()
    private(set) var chat: ChatController!
    private(set) var floating: FloatingController!
    private(set) var director: CharacterDirector!

    private var briefingTimer: Timer?

    private init() {
        store = TodoStore()
        settings = SettingsStore()
        calendar = CalendarService()
        chat = ChatController(env: self)
        floating = FloatingController(env: self)
        director = CharacterDirector(env: self)

        calendar.enabled = settings.settings.calendarEnabled
        calendar.hiddenCalendarIDs = Set(settings.settings.hiddenCalendarIDs)

        store.onMutation = { [weak self] m in self?.handle(m) }
        settings.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
    }

    func start() {
        floating.applyVisibility()
        director.start()
        startBriefingTimer()
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
        if old.showFloatingCharacter != new.showFloatingCharacter { floating.applyVisibility() }
        if old.character != new.character {
            floating.layoutForRig()
            director.settingsChanged()
        }
        if old.llm.claudeCodePath != new.llm.claudeCodePath { ClaudeCodeLocator.resetCache() }
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
