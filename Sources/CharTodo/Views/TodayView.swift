import SwiftUI

struct TodayView: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    @Environment(CalendarService.self) private var calendar
    @Environment(ChatController.self) private var chat
    @Environment(FloatingController.self) private var floating

    @State private var day = Date().startOfDay
    @State private var creating: TodoItem?

    var body: some View {
        let todos = store.todos(on: day)
        let overdue = day.isToday ? store.overdue() : []
        let _ = calendar.revision
        let events = calendar.events(on: day)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(todos: todos)
                QuickAddBar(defaultDate: day)

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        RetroWindow(day.isToday ? "TODAY.TXT" : "\(day.dayKey).TXT", symbol: "checklist") {
                            Button { creating = TodoItem(title: "", date: day) } label: { Image(systemName: "plus.square.fill") }
                                .buttonStyle(.plain).font(.system(size: 13, weight: .bold)).help("자세히 추가")
                        } content: {
                            todoList(todos, empty: "오늘 할일이 비어 있어요. 위에서 추가해 보세요!")
                        }

                        if !overdue.isEmpty {
                            RetroWindow("밀린 할일 \(overdue.count)", symbol: "exclamationmark.triangle.fill", tint: theme.quadrantColors[0]) {
                                Button("모두 오늘로") { store.moveOverdueToToday() }
                                    .buttonStyle(.retro(.secondary, compact: true))
                            } content: {
                                todoList(overdue, showDate: true, empty: "")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 18) {
                        scheduleWindow(events: events, todos: todos)
                        goalsWindow(title: "이번 주 목표", symbol: "flag.fill", items: store.weekGoals(for: day), scope: .week)
                        goalsWindow(title: "이번 달 목표", symbol: "star.fill", items: store.monthGoals(for: day), scope: .month)
                    }
                    .frame(width: 320)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .sheet(item: $creating) { item in TodoEditorSheet(original: item, isNew: true) }
    }

    // MARK: 헤더 (뜯는 달력)

    private func header(todos: [TodoItem]) -> some View {
        let done = todos.filter(\.isDone).count
        let total = todos.count
        return HStack(alignment: .center, spacing: 18) {
            TearOffCalendar(date: day)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(day.isToday ? "오늘의 할일" : DateFormatters.monthDayWeekday.string(from: day))
                        .font(theme.titleFont(28))
                        .foregroundStyle(theme.text)
                    if !day.isToday {
                        Button("오늘로") { day = Date().startOfDay }.buttonStyle(.retro(.secondary, compact: true))
                    }
                }
                Text(DateFormatters.fullDate.string(from: day))
                    .font(theme.font(13, .bold))
                    .foregroundStyle(theme.textMuted)
                HStack(spacing: 10) {
                    SegmentedProgress(value: total == 0 ? 0 : Double(done) / Double(total), segments: 16, height: 14)
                        .frame(width: 220)
                    Text(total == 0 ? "할일 없음" : "\(done)/\(total) 완료")
                        .font(theme.font(12, .heavy))
                        .foregroundStyle(theme.text)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    IconButton(symbol: "chevron.left", help: "전날") { day = day.adding(days: -1) }
                    IconButton(symbol: "chevron.right", help: "다음날") { day = day.adding(days: 1) }
                }
                Button {
                    floating.showChat()
                    chat.briefing(.today)
                } label: {
                    Label("오늘 브리핑 받기", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(.retro(.primary))
                .disabled(chat.isBusy)
                Button {
                    floating.showChat()
                    chat.briefing(.priorities)
                } label: {
                    Label("뭐부터 할까?", systemImage: "list.number")
                }
                .buttonStyle(.retro(.secondary, compact: true))
                .disabled(chat.isBusy)
            }
        }
        .padding(.top, 16)
    }

    private func todoList(_ items: [TodoItem], showDate: Bool = false, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty && !empty.isEmpty { EmptyHint(text: empty) }
            ForEach(items) { t in
                TodoRowView(todo: t, showDate: showDate)
            }
        }
        .padding(10)
        .todoDropTarget { id in store.move(id, to: day, scope: .day) }
    }

    // MARK: 일정 (캘린더 + 시간 지정 할일)

    private func scheduleWindow(events: [CalendarEvent], todos: [TodoItem]) -> some View {
        let timed = todos.filter { $0.scheduledStart != nil && $0.calendarEventID == nil }
        return RetroWindow("SCHEDULE", symbol: "clock.fill", tint: theme.accent2) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                if !calendar.enabled {
                    Button {
                        NotificationCenter.default.post(name: .navigateRequest, object: AppSection.settings.rawValue)
                    } label: {
                        Label("macOS 캘린더 연결하기", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.retro(.secondary, compact: true))
                }
                if events.isEmpty && timed.isEmpty {
                    EmptyHint(text: "예정된 일정이 없어요", symbol: "cup.and.saucer.fill")
                }
                ForEach(mergedTimeline(events: events, timed: timed), id: \.id) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.time)
                            .font(theme.font(11, .heavy))
                            .foregroundStyle(theme.textMuted)
                            .frame(width: 70, alignment: .leading)
                        RoundedRectangle(cornerRadius: 2).fill(entry.color).frame(width: 4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(theme.font(12.5, .semibold)).foregroundStyle(theme.text).lineLimit(2)
                            if let sub = entry.subtitle {
                                Text(sub).font(theme.font(10.5)).foregroundStyle(theme.textMuted).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(10)
        }
    }

    private struct TimelineEntry {
        var id: String
        var sort: Date
        var time: String
        var title: String
        var subtitle: String?
        var color: Color
    }

    private func mergedTimeline(events: [CalendarEvent], timed: [TodoItem]) -> [TimelineEntry] {
        var out = events.map {
            TimelineEntry(id: $0.id, sort: $0.isAllDay ? .distantPast : $0.start, time: $0.timeLabel, title: $0.title,
                          subtitle: [$0.calendarTitle, $0.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                          color: Color(hex: $0.colorHex) ?? theme.accent)
        }
        out += timed.map {
            TimelineEntry(id: $0.id.uuidString, sort: $0.scheduledStart!, time: DateFormatters.time.string(from: $0.scheduledStart!),
                          title: ($0.isDone ? "✓ " : "☐ ") + $0.title, subtitle: "할일", color: theme.quadrantColor($0.quadrant))
        }
        return out.sorted { $0.sort < $1.sort }
    }

    private func goalsWindow(title: String, symbol: String, items: [TodoItem], scope: TodoScope) -> some View {
        let done = items.filter(\.isDone).count
        return RetroWindow(title, symbol: symbol, tint: scope == .week ? theme.accent : theme.highlight) {
            Text("\(done)/\(items.count)").font(theme.font(11, .heavy))
        } content: {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items) { t in TodoRowView(todo: t, compact: true) }
                QuickAddBar(placeholder: scope == .week ? "주간 목표 추가" : "월간 목표 추가",
                            defaultDate: day, defaultScope: scope, compact: true)
            }
            .padding(8)
            .todoDropTarget { id in store.move(id, to: day, scope: scope) }
        }
    }
}

/// 뜯는 달력 모양 날짜 카드
struct TearOffCalendar: View {
    @Environment(\.theme) private var theme
    var date: Date
    var size: CGFloat = 92

    var body: some View {
        VStack(spacing: 0) {
            Text(DateFormatters.englishMonth.string(from: date).uppercased())
                .font(theme.font(size * 0.15, .black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, size * 0.05)
                .background(theme.accent)
            Text("\(date.dayNumber)")
                .font(theme.titleFont(size * 0.46))
                .foregroundStyle(date.weekdayIndex == 1 ? Color(hex: "#E5484D")! : theme.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(DateFormatters.englishWeekday.string(from: date).uppercased())
                .font(theme.font(size * 0.12, .heavy))
                .foregroundStyle(theme.textMuted)
                .padding(.bottom, size * 0.06)
        }
        .frame(width: size, height: size * 1.05)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: max(2, theme.cornerRadius - 2)))
        .overlay(
            // 링 구멍
            HStack(spacing: size * 0.3) {
                ForEach(0..<2, id: \.self) { _ in
                    Capsule().fill(theme.border).frame(width: size * 0.06, height: size * 0.16)
                }
            }
            .offset(y: -size * 0.08),
            alignment: .top
        )
        .retroCard(fill: theme.surface)
        .rotationEffect(.degrees(-3))
    }
}
