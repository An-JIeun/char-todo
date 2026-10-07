import SwiftUI

struct MonthView: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    @Environment(CalendarService.self) private var calendar

    @State private var month = Date().startOfMonth
    @State private var selected = Date().startOfDay

    var body: some View {
        let grid = month.monthGridDays
        let _ = calendar.revision
        let eventsByDay = calendar.eventsByDay(from: grid.first ?? month, days: 42)

        VStack(alignment: .leading, spacing: 14) {
            header.padding(.horizontal, 24)

            HStack(alignment: .top, spacing: 16) {
                monthGrid(grid, eventsByDay: eventsByDay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 14) {
                    monthGoals
                    dayDetail(events: eventsByDay[selected] ?? [])
                }
                .frame(width: 310)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateFormatters.yearMonth.string(from: month)).font(theme.titleFont(28)).foregroundStyle(theme.text)
                let items = store.todos.filter { $0.scope == .day && $0.date.isSameMonth(as: month) }
                Text("이번 달 할일 \(items.count)개 · 완료 \(items.filter(\.isDone).count)개")
                    .font(theme.font(13, .bold)).foregroundStyle(theme.textMuted)
            }
            Spacer()
            HStack(spacing: 4) {
                Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.retro(.secondary, compact: true))
                Button("이번 달") { month = Date().startOfMonth; selected = Date().startOfDay }
                    .buttonStyle(.retro(.secondary, compact: true))
                Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.retro(.secondary, compact: true))
            }
        }
        .padding(.top, 16)
    }

    private func monthGrid(_ days: [Date], eventsByDay: [Date: [CalendarEvent]]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days.prefix(7), id: \.self) { d in
                    Text(DateFormatters.weekdayShort.string(from: d))
                        .font(theme.font(11.5, .heavy))
                        .foregroundStyle(d.weekdayIndex == 1 ? Color(hex: "#E5484D")! : (d.weekdayIndex == 7 ? theme.accent2 : theme.titleBarText))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .background(theme.titleBar)
            Rectangle().fill(theme.border).frame(height: theme.borderWidth)
            GeometryReader { geo in
                let cellH = geo.size.height / 6
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let d = days[row * 7 + col]
                                MonthCell(day: d, inMonth: d.isSameMonth(as: month), selected: d.isSameDay(as: selected),
                                          events: eventsByDay[d.startOfDay] ?? [])
                                    .frame(maxWidth: .infinity)
                                    .frame(height: cellH)
                                    .onTapGesture { selected = d.startOfDay }
                                if col < 6 { Rectangle().fill(theme.border.opacity(0.3)).frame(width: 1) }
                            }
                        }
                        if row < 5 { Rectangle().fill(theme.border.opacity(0.3)).frame(height: 1) }
                    }
                }
            }
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        .retroCard(fill: theme.surface)
    }

    private var monthGoals: some View {
        let goals = store.monthGoals(for: month)
        return RetroWindow("MONTHLY_GOALS", symbol: "star.fill", tint: theme.accent2) {
            Text("\(goals.filter(\.isDone).count)/\(goals.count)").font(theme.font(11, .heavy))
        } content: {
            VStack(alignment: .leading, spacing: 5) {
                if goals.isEmpty { EmptyHint(text: "이번 달 목표가 없어요") }
                ForEach(goals) { t in TodoRowView(todo: t, compact: true) }
                QuickAddBar(placeholder: "월간 목표 추가", defaultDate: month, defaultScope: .month, compact: true)
            }
            .padding(8)
            .todoDropTarget { id in store.move(id, to: month, scope: .month) }
        }
    }

    private func dayDetail(events: [CalendarEvent]) -> some View {
        let todos = store.todos(on: selected)
        return RetroWindow(DateFormatters.monthDayWeekday.string(from: selected), symbol: "doc.text.fill") {
            Button("오늘 화면") {
                NotificationCenter.default.post(name: .navigateRequest, object: AppSection.today.rawValue)
            }
            .buttonStyle(.plain)
            .font(theme.font(10.5, .bold))
            .opacity(selected.isToday ? 1 : 0)
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { e in
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: e.colorHex) ?? theme.accent2).frame(width: 7, height: 7)
                            Text(e.timeLabel).font(theme.font(10.5, .bold)).foregroundStyle(theme.textMuted)
                            Text(e.title).font(theme.font(12)).lineLimit(1)
                        }
                    }
                    if !events.isEmpty { Divider() }
                    if todos.isEmpty && events.isEmpty { EmptyHint(text: "비어 있는 날이에요") }
                    ForEach(todos) { t in TodoRowView(todo: t, compact: true) }
                }
                .padding(8)
            }
            QuickAddBar(placeholder: "이 날짜에 추가", defaultDate: selected, compact: true)
                .padding(8)
        }
        .todoDropTarget { id in store.move(id, to: selected, scope: .day) }
    }
}

struct MonthCell: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    let day: Date
    let inMonth: Bool
    let selected: Bool
    let events: [CalendarEvent]
    @State private var targeted = false

    var body: some View {
        let todos = store.todos(on: day)
        let maxLines = 3
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text("\(day.dayNumber)")
                    .font(theme.font(12, .heavy))
                    .foregroundStyle(day.isToday ? theme.onAccent : dayColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(day.isToday ? Capsule().fill(theme.accent) : Capsule().fill(Color.clear))
                Spacer(minLength: 0)
                if store.hasJournal(on: day) {
                    Image(systemName: "book.closed.fill").font(.system(size: 8)).foregroundStyle(theme.accent2)
                }
                if !events.isEmpty {
                    HStack(spacing: 1) {
                        ForEach(events.prefix(3)) { e in
                            Circle().fill(Color(hex: e.colorHex) ?? theme.accent2).frame(width: 5, height: 5)
                        }
                    }
                }
            }
            ForEach(todos.prefix(maxLines)) { t in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(theme.quadrantColor(t.quadrant))
                        .frame(width: 3, height: 10)
                    Text(t.title)
                        .font(theme.font(10, .medium))
                        .strikethrough(t.isDone)
                        .foregroundStyle(t.isDone ? theme.textMuted : theme.text)
                        .lineLimit(1)
                }
            }
            if todos.count > maxLines {
                Text("+\(todos.count - maxLines)").font(theme.font(9.5, .bold)).foregroundStyle(theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .opacity(inMonth ? 1 : 0.4)
        .contentShape(Rectangle())
        .todoDropTarget(isTargeted: $targeted) { id in store.move(id, to: day, scope: .day) }
    }

    private var dayColor: Color {
        switch day.weekdayIndex {
        case 1: Color(hex: "#E5484D")!
        case 7: theme.accent2
        default: theme.text
        }
    }

    private var background: Color {
        if targeted { return theme.highlight.opacity(0.4) }
        if selected { return theme.accent.opacity(0.14) }
        return Color.clear
    }
}
