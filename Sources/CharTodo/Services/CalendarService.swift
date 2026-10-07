import Foundation
import EventKit
import Observation
import AppKit
import SwiftUI

/// 화면에서 쓰는 캘린더 이벤트 값 타입
struct CalendarEvent: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarTitle: String
    var colorHex: String
    var location: String?

    var timeLabel: String {
        isAllDay ? "종일" : "\(DateFormatters.time.string(from: start))–\(DateFormatters.time.string(from: end))"
    }
}

struct CalendarInfo: Identifiable, Hashable {
    var id: String
    var title: String
    var colorHex: String
    var source: String
    var allowsModify: Bool
}

/// macOS 캘린더(EventKit) 연동: 일정 읽기 + 할일을 일정으로 내보내기
@MainActor
@Observable
final class CalendarService {
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var calendars: [CalendarInfo] = []
    /// 외부에서 캘린더가 바뀌면 증가 → 뷰 갱신
    private(set) var revision = 0
    private(set) var lastError: String?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var cache: [String: [CalendarEvent]] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored var hiddenCalendarIDs: Set<String> = [] {
        didSet { if hiddenCalendarIDs != oldValue { cache.removeAll(); revision += 1 } }
    }
    @ObservationIgnored var enabled = false {
        didSet { if enabled != oldValue { cache.removeAll(); revision += 1 } }
    }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cache.removeAll()
                self?.reloadCalendars()
                self?.revision += 1
            }
        }
        if hasReadAccess { reloadCalendars() }
    }

    var hasReadAccess: Bool { status == .fullAccess }
    var canWrite: Bool { status == .fullAccess || status == .writeOnly }

    var statusLabel: String {
        switch status {
        case .fullAccess: "연결됨"
        case .writeOnly: "쓰기 전용"
        case .denied: "거부됨 — 시스템 설정 > 개인정보 보호 > 캘린더에서 허용해 주세요"
        case .restricted: "제한됨"
        case .notDetermined: "아직 요청하지 않음"
        @unknown default: "알 수 없음"
        }
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            lastError = error.localizedDescription
        }
        status = EKEventStore.authorizationStatus(for: .event)
        store.reset()
        cache.removeAll()
        reloadCalendars()
        revision += 1
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func reloadCalendars() {
        guard hasReadAccess else { calendars = []; return }
        calendars = store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title,
                                colorHex: Color(nsColor: $0.color ?? .systemBlue).hexString,
                                source: $0.source?.title ?? "", allowsModify: $0.allowsContentModifications) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    // MARK: 읽기

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard enabled, hasReadAccess else { return [] }
        let key = "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
        if let hit = cache[key] { return hit }
        let cals = store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        let result = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                CalendarEvent(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "(제목 없음)",
                              start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                              calendarTitle: e.calendar?.title ?? "",
                              colorHex: Color(nsColor: e.calendar?.color ?? .systemBlue).hexString,
                              location: e.location)
            }
        cache[key] = result
        return result
    }

    func events(on day: Date) -> [CalendarEvent] {
        events(from: day.startOfDay, to: day.startOfDay.adding(days: 1))
    }

    func eventsByDay(from start: Date, days: Int) -> [Date: [CalendarEvent]] {
        let all = events(from: start.startOfDay, to: start.startOfDay.adding(days: days))
        var map: [Date: [CalendarEvent]] = [:]
        for e in all {
            // 여러 날에 걸친 일정은 각 날짜에 표시
            var d = max(e.start, start).startOfDay
            let last = e.end > e.start ? e.end.addingTimeInterval(-1) : e.end
            repeat {
                map[d, default: []].append(e)
                d = d.adding(days: 1)
            } while d <= last && d < start.adding(days: days)
        }
        return map
    }

    // MARK: 쓰기

    private var exportCalendar: EKCalendar? {
        if let id = AppEnvironment.shared.settings.settings.exportCalendarID,
           let cal = store.calendar(withIdentifier: id), cal.allowsContentModifications {
            return cal
        }
        return store.defaultCalendarForNewEvents
    }

    /// 할일을 캘린더 이벤트로 만들고 식별자를 돌려준다.
    func createEvent(for todo: TodoItem) -> String? {
        guard canWrite, let cal = exportCalendar else {
            lastError = "캘린더 쓰기 권한이 없어요."
            return nil
        }
        let event = EKEvent(eventStore: store)
        event.calendar = cal
        apply(todo, to: event)
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func updateEvent(id: String, with todo: TodoItem) {
        guard canWrite, let event = store.event(withIdentifier: id) else { return }
        apply(todo, to: event)
        try? store.save(event, span: .thisEvent, commit: true)
    }

    func removeEvent(id: String) {
        guard canWrite, let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    private func apply(_ todo: TodoItem, to event: EKEvent) {
        event.title = (todo.isDone ? "✅ " : "☑️ ") + todo.title
        var notes = todo.notes
        if !todo.subtasks.isEmpty {
            notes += (notes.isEmpty ? "" : "\n\n") + todo.subtasks.map { "\($0.isDone ? "[x]" : "[ ]") \($0.title)" }.joined(separator: "\n")
        }
        notes += (notes.isEmpty ? "" : "\n\n") + "— CharTodo"
        event.notes = notes
        switch todo.scope {
        case .day:
            if let start = todo.scheduledStart {
                event.isAllDay = false
                event.startDate = start
                event.endDate = start.addingTimeInterval(TimeInterval(max(15, todo.durationMinutes) * 60))
            } else {
                event.isAllDay = true
                event.startDate = todo.date
                event.endDate = todo.date.adding(days: 1)
            }
        case .week:
            event.isAllDay = true
            event.startDate = todo.date
            event.endDate = todo.date.adding(days: 7)
        case .month:
            event.isAllDay = true
            event.startDate = todo.date
            event.endDate = todo.date.adding(months: 1)
        }
    }

    /// TodoStore 변경을 캘린더에 반영 (연결된 할일만)
    func sync(_ mutation: TodoMutation) {
        switch mutation {
        case .added: break
        case let .updated(old, new):
            guard let id = new.calendarEventID else { return }
            if old.title != new.title || old.date != new.date || old.time != new.time || old.isDone != new.isDone
                || old.subtasks != new.subtasks || old.notes != new.notes || old.scope != new.scope
                || old.durationMinutes != new.durationMinutes {
                updateEvent(id: id, with: new)
            }
        case let .deleted(item):
            if let id = item.calendarEventID { removeEvent(id: id) }
        }
    }
}
