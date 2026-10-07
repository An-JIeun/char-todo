import SwiftUI

struct WeekView: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    @Environment(CalendarService.self) private var calendar
    @Environment(ChatController.self) private var chat
    @Environment(FloatingController.self) private var floating

    @State private var anchor = Date().startOfWeek

    var body: some View {
        let days = anchor.weekDays
        let _ = calendar.revision
        let eventsByDay = calendar.eventsByDay(from: anchor, days: 7)
        let weekGoals = store.weekGoals(for: anchor)

        VStack(alignment: .leading, spacing: 14) {
            header(days: days)
                .padding(.horizontal, 24)

            HStack(alignment: .top, spacing: 14) {
                RetroWindow("WEEKLY_GOALS", symbol: "flag.fill") {
                    Text("\(weekGoals.filter(\.isDone).count)/\(weekGoals.count)").font(theme.font(11, .heavy))
                } content: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if weekGoals.isEmpty { EmptyHint(text: "이번 주 목표를 세워 보세요") }
                            ForEach(weekGoals) { t in TodoRowView(todo: t, compact: true) }
                        }
                        .padding(8)
                    }
                    QuickAddBar(placeholder: "주간 목표 추가", defaultDate: anchor, defaultScope: .week, compact: true)
                        .padding(8)
                }
                .frame(width: 250)
                .todoDropTarget { id in store.move(id, to: anchor, scope: .week) }

                GeometryReader { geo in
                    let colWidth = max(140, (geo.size.width - 6 * 10) / 7)
                    ScrollView(.horizontal, showsIndicators: colWidth * 7 + 60 > geo.size.width) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(days, id: \.self) { d in
                                DayColumn(day: d, events: eventsByDay[d.startOfDay] ?? [])
                                    .frame(width: colWidth)
                                    .frame(maxHeight: geo.size.height)
                            }
                        }
                        .padding(.trailing, 6)
                        .padding(.bottom, 6)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func header(days: [Date]) -> some View {
        let all = days.flatMap { store.todos(on: $0) }
        let done = all.filter(\.isDone).count
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("주간 플래너").font(theme.titleFont(28)).foregroundStyle(theme.text)
                Text(anchor.weekRangeLabel).font(theme.font(13, .bold)).foregroundStyle(theme.textMuted)
            }
            Spacer()
            HStack(spacing: 8) {
                SegmentedProgress(value: all.isEmpty ? 0 : Double(done) / Double(all.count), segments: 14, height: 12)
                    .frame(width: 160)
                Text("\(done)/\(all.count)").font(theme.font(12, .heavy))
            }
            HStack(spacing: 4) {
                Button { anchor = anchor.adding(weeks: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.retro(.secondary, compact: true))
                Button("이번 주") { anchor = Date().startOfWeek }
                    .buttonStyle(.retro(.secondary, compact: true))
                Button { anchor = anchor.adding(weeks: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.retro(.secondary, compact: true))
            }
            Button {
                floating.showChat()
                chat.briefing(.week)
            } label: {
                Label("주간 점검", systemImage: "play.rectangle.fill")
            }
            .buttonStyle(.retro(.primary, compact: true))
            .disabled(chat.isBusy)
        }
        .padding(.top, 16)
    }
}

/// 주간 화면의 하루 칸
struct DayColumn: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    let day: Date
    let events: [CalendarEvent]
    @State private var targeted = false

    var body: some View {
        let todos = store.todos(on: day)
        let isToday = day.isToday
        let weekend = day.weekdayIndex == 1 || day.weekdayIndex == 7
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(DateFormatters.weekdayShort.string(from: day))
                    .font(theme.font(12, .heavy))
                Text("\(day.dayNumber)")
                    .font(theme.titleFont(18))
                Spacer()
                if !todos.isEmpty {
                    Text("\(todos.filter(\.isDone).count)/\(todos.count)").font(theme.font(10, .bold))
                }
            }
            .foregroundStyle(isToday ? theme.onAccent : (weekend ? theme.accent : theme.text))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isToday ? theme.accent : theme.surfaceAlt)
            Rectangle().fill(theme.border).frame(height: theme.borderWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(events) { e in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1).fill(Color(hex: e.colorHex) ?? theme.accent2).frame(width: 3)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(e.title).font(theme.font(10.5, .semibold)).lineLimit(2)
                                Text(e.timeLabel).font(theme.font(9.5)).foregroundStyle(theme.textMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 3).fill((Color(hex: e.colorHex) ?? theme.accent2).opacity(0.12)))
                    }
                    ForEach(todos) { t in TodoRowView(todo: t, compact: true) }
                    if todos.isEmpty && events.isEmpty {
                        Text("여기로 끌어다 놓기")
                            .font(theme.font(10.5))
                            .foregroundStyle(theme.textMuted.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .padding(6)
            }
            QuickAddBar(placeholder: "+ 추가", defaultDate: day, compact: true)
                .padding(6)
        }
        .background(targeted ? theme.highlight.opacity(0.35) : theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.border, lineWidth: isToday ? theme.borderWidth * 1.5 : theme.borderWidth))
        .background(RoundedRectangle(cornerRadius: theme.cornerRadius).fill(theme.shadow).offset(x: theme.shadowOffset, y: theme.shadowOffset))
        .todoDropTarget(isTargeted: $targeted) { id in store.move(id, to: day, scope: .day) }
    }
}
