import Testing
import Foundation
@testable import CharTodo

@Suite struct CareerDeadlineTests {
    let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 20; c.hour = 10
        return AppCalendar.current.date(from: c)!
    }()

    private func ymd(_ d: Date) -> [Int] {
        let c = AppCalendar.current.dateComponents([.year, .month, .day], from: d)
        return [c.year!, c.month!, c.day!]
    }

    private func hm(_ d: Date?) -> [Int]? {
        guard let d else { return nil }
        let c = AppCalendar.current.dateComponents([.hour, .minute], from: d)
        return [c.hour!, c.minute!]
    }

    @Test func parsesTildeDeadlines() {
        let a = CareerDeadline.parse("~2026-08-02", now: now)
        #expect(a.map { ymd($0.date) } == [2026, 8, 2])
        #expect(a?.time == nil)

        let b = CareerDeadline.parse("~2026-08-05 17:00", now: now)
        #expect(b.map { ymd($0.date) } == [2026, 8, 5])
        #expect(hm(b?.time) == [17, 0])

        let c = CareerDeadline.parse("~2026-08-30 (채용 시 마감)", now: now)
        #expect(c.map { ymd($0.date) } == [2026, 8, 30])
    }

    @Test func picksEndOfRangeAndWeekdaySuffix() {
        let r = CareerDeadline.parse("2026.08.01(토) ~ 2026.08.31(월) 18:00", now: now)
        #expect(r.map { ymd($0.date) } == [2026, 8, 31])
        #expect(hm(r?.time) == [18, 0])

        let k = CareerDeadline.parse("2026년 9월 3일까지", now: now)
        #expect(k.map { ymd($0.date) } == [2026, 9, 3])
    }

    @Test func shortDatesUseCurrentOrNextYear() {
        #expect(CareerDeadline.parse("~08/31", now: now).map { ymd($0.date) } == [2026, 8, 31])
        // 반년 넘게 지난 날짜면 내년 마감으로 본다
        #expect(CareerDeadline.parse("~1/15", now: now).map { ymd($0.date) } == [2027, 1, 15])
    }

    @Test func openEndedDeadlinesAreNil() {
        #expect(CareerDeadline.parse("채용시까지 (2026-03-20 09:00 공고 시작)", now: now) == nil)
        #expect(CareerDeadline.parse("상시채용", now: now) == nil)
        #expect(CareerDeadline.parse("2026-08-01 ~ 채용시", now: now) == nil)
        #expect(CareerDeadline.parse("", now: now) == nil)
    }

    @Test func endOfDayHasNoTime() {
        let r = CareerDeadline.parse("~2026-08-05 23:59", now: now)
        #expect(r.map { ymd($0.date) } == [2026, 8, 5])
        #expect(r?.time == nil)
    }
}

@Suite struct CareerSyncTests {
    let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 20; c.hour = 10
        return AppCalendar.current.date(from: c)!
    }()

    let hyundai = CareerJob(id: "j2", company: "현대자동차 (HYUNDAI MOTOR COMPANY)",
                            position: "[제조로보틱스] 로보틱스 데이터 엔지니어",
                            link: "https://example.com/hyundai", deadline: "~2026-08-05 17:00")

    private func added(_ actions: [CareerSync.Action]) -> [TodoItem] {
        actions.compactMap { if case let .add(item, _, _) = $0 { item } else { nil } }
    }

    @Test func shortCompanyStripsLegalSuffixes() {
        #expect(CareerJob(company: "㈜숲 (SOOP CO., LTD.)").shortCompany == "숲")
        #expect(CareerJob(company: "(주)리스트").shortCompany == "리스트")
        #expect(hyundai.todoTitle == "현대자동차 지원 — [제조로보틱스] 로보틱스 데이터 엔지니어")
    }

    @Test func addsTodoForUpcomingInterestedJob() {
        let items = added(CareerSync.plan(jobs: [hyundai], todos: [], config: CareerSupportConfig(), now: now))
        #expect(items.count == 1)
        let t = items[0]
        #expect(t.sourceKey == "career:https://example.com/hyundai")
        #expect(t.link == "https://example.com/hyundai")
        #expect(t.tags == ["취업"])
        #expect(t.quadrant == .schedule)
        #expect(t.scheduledStart != nil)
        #expect(t.isCareerJob)
    }

    @Test func skipsPastAppliedUnwantedAndDeletedJobs() {
        var config = CareerSupportConfig()
        let past = CareerJob(company: "A", position: "p", link: "a", deadline: "~2026-07-01")
        let applied = CareerJob(company: "B", position: "p", link: "b", deadline: "~2026-08-01", status: "지원완료")
        let open = CareerJob(company: "C", position: "p", link: "c", deadline: "상시")
        let deleted = CareerJob(company: "D", position: "p", link: "d", deadline: "~2026-08-01")
        config.imported["career:d"] = "~2026-08-01"
        let actions = CareerSync.plan(jobs: [past, applied, open, deleted], todos: [], config: config, now: now)
        #expect(actions.isEmpty)

        config.statuses = ["지원예정"]
        #expect(CareerSync.plan(jobs: [hyundai], todos: [], config: config, now: now).isEmpty)
    }

    @Test func duplicateLinksAddOnce() {
        let items = added(CareerSync.plan(jobs: [hyundai, hyundai], todos: [], config: CareerSupportConfig(), now: now))
        #expect(items.count == 1)
    }

    @Test func completesWhenAppliedAndFollowsDeadlineChanges() {
        var todo = TodoItem(title: hyundai.todoTitle, date: now)
        todo.sourceKey = hyundai.key
        var config = CareerSupportConfig()
        config.imported[hyundai.key] = hyundai.deadline

        // 그대로면 아무것도 안 함 (사용자가 옮긴 날짜 존중)
        #expect(CareerSync.plan(jobs: [hyundai], todos: [todo], config: config, now: now).isEmpty)

        // 마감이 바뀌면 날짜를 따라간다
        var moved = hyundai
        moved.deadline = "~2026-08-12"
        let r = CareerSync.plan(jobs: [moved], todos: [todo], config: config, now: now)
        guard case let .reschedule(id, date, time, _, stamp)? = r.first else { Issue.record("reschedule 없음"); return }
        #expect(id == todo.id)
        #expect(AppCalendar.current.component(.day, from: date) == 12)
        #expect(time == nil)
        #expect(stamp == "~2026-08-12")

        // 지원완료가 되면 완료 처리
        var applied = hyundai
        applied.status = "서류합격"
        let c = CareerSync.plan(jobs: [applied], todos: [todo], config: config, now: now)
        guard case let .complete(cid, _)? = c.first else { Issue.record("complete 없음"); return }
        #expect(cid == todo.id)

        config.completeWhenApplied = false
        #expect(CareerSync.plan(jobs: [applied], todos: [todo], config: config, now: now).isEmpty)
    }

    @Test func decodesExportJSON() throws {
        let json = #"{"id":"j1","company":"㈜숲","position":"데이터 분석가","link":"https://x","deadline":"~2026-08-02","required_skills":"SQL, Python","match_score":"4/5","status":"관심","extra":"무시"}"#
        let job = try JSONDecoder().decode(CareerJob.self, from: Data(json.utf8))
        #expect(job.requiredSkills == "SQL, Python")
        #expect(job.matchScore == "4/5")
        #expect(job.todoNotes.contains("요구스킬: SQL, Python"))
    }

    @Test func todoLinkFieldsRoundTrip() throws {
        var t = TodoItem(title: "x")
        t.link = "https://x"
        t.sourceKey = "career:https://x"
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(TodoItem.self, from: data)
        #expect(back.link == "https://x")
        #expect(back.sourceKey == "career:https://x")
        // 예전 데이터(필드 없음)도 그대로 읽힌다
        let old = try JSONDecoder().decode(TodoItem.self, from: Data(#"{"title":"old"}"#.utf8))
        #expect(old.link == nil && old.sourceKey == nil)
    }
}
