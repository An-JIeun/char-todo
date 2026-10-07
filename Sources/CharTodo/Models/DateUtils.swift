import Foundation

/// 앱 전체에서 쓰는 달력 설정. 주 시작 요일은 설정에서 바뀔 수 있다.
enum AppCalendar {
    static var firstWeekday: Int = 2 // 1 = 일요일, 2 = 월요일

    static var current: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ko_KR")
        cal.timeZone = .current
        cal.firstWeekday = firstWeekday
        return cal
    }
}

extension Date {
    var startOfDay: Date { AppCalendar.current.startOfDay(for: self) }

    var startOfWeek: Date {
        let cal = AppCalendar.current
        let interval = cal.dateInterval(of: .weekOfYear, for: self)
        return interval?.start ?? startOfDay
    }

    var startOfMonth: Date {
        let cal = AppCalendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: self)) ?? startOfDay
    }

    func adding(days: Int) -> Date {
        AppCalendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(weeks: Int) -> Date {
        AppCalendar.current.date(byAdding: .weekOfYear, value: weeks, to: self) ?? self
    }

    func adding(months: Int) -> Date {
        AppCalendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    func isSameDay(as other: Date) -> Bool {
        AppCalendar.current.isDate(self, inSameDayAs: other)
    }

    func isSameWeek(as other: Date) -> Bool {
        startOfWeek == other.startOfWeek
    }

    func isSameMonth(as other: Date) -> Bool {
        startOfMonth == other.startOfMonth
    }

    var isToday: Bool { isSameDay(as: Date()) }

    /// 이 날짜가 속한 주의 7일.
    var weekDays: [Date] {
        let start = startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    /// 월간 달력 그리드(6주 × 7일 = 42칸).
    var monthGridDays: [Date] {
        let first = startOfMonth
        let gridStart = first.startOfWeek
        return (0..<42).map { gridStart.adding(days: $0) }
    }

    var dayNumber: Int { AppCalendar.current.component(.day, from: self) }
    var weekdayIndex: Int { AppCalendar.current.component(.weekday, from: self) } // 1 = 일

    /// 해당 월의 몇 번째 주인지 (1부터)
    var weekOfMonth: Int { AppCalendar.current.component(.weekOfMonth, from: self) }

    /// 시·분만 가져와 다른 날짜에 붙인다.
    func combining(time: Date) -> Date {
        let cal = AppCalendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: self) ?? self
    }

    var dayKey: String { DateFormatters.dayKey.string(from: self) }
}

enum DateFormatters {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        return f
    }

    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let monthDayWeekday = make("M월 d일 (E)")
    static let fullDate = make("yyyy년 M월 d일 EEEE")
    static let yearMonth = make("yyyy년 M월")
    static let monthDay = make("M/d")
    static let weekdayShort = make("E")
    static let time = make("HH:mm")
    static let englishMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM"
        return f
    }()
    static let englishWeekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE"
        return f
    }()
}

extension Date {
    var weekRangeLabel: String {
        let days = weekDays
        guard let first = days.first, let last = days.last else { return "" }
        let week = AppCalendar.current.component(.weekOfMonth, from: first)
        return "\(DateFormatters.yearMonth.string(from: first)) \(week)주차 · \(DateFormatters.monthDay.string(from: first)) – \(DateFormatters.monthDay.string(from: last))"
    }
}
