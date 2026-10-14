import Foundation
import Observation
import AppKit

// career-support(채용 공고 수집·지원 관리 툴, ~/Documents/GitHub/career-support) 연동.
// - 공고 마감일 → 할일: career-support의 backend/export_jobs.py 가 jobs.xlsx를 JSON으로 내보내면 그걸 읽는다
//   (서버가 꺼져 있어도 동작, 엑셀 스키마는 career-support 쪽 excel_store가 단일 원천).
// - 바로 가기: 웹 화면(localhost:2500)을 열고, 꺼져 있으면 백엔드·프론트를 켠다.

/// career-support의 공고 1건 (JobPosting 필드)
struct CareerJob: Decodable, Identifiable, Hashable {
    var id = ""
    var company = ""
    var position = ""
    var category = ""
    var experience = ""
    var link = ""
    var deadline = ""
    var applyMethod = ""
    var process = ""
    var requiredSkills = ""
    var matchScore = ""
    var interest = ""
    var status = ""

    enum CodingKeys: String, CodingKey {
        case id, company, position, category, experience, link, deadline, process, interest, status
        case applyMethod = "apply_method"
        case requiredSkills = "required_skills"
        case matchScore = "match_score"
    }

    init(id: String = "", company: String = "", position: String = "", link: String = "",
         deadline: String = "", status: String = "관심", interest: String = "중간") {
        self.id = id
        self.company = company
        self.position = position
        self.link = link
        self.deadline = deadline
        self.status = status
        self.interest = interest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil)?.trimmed ?? "" }
        id = s(.id); company = s(.company); position = s(.position); category = s(.category)
        experience = s(.experience); link = s(.link); deadline = s(.deadline); applyMethod = s(.applyMethod)
        process = s(.process); requiredSkills = s(.requiredSkills); matchScore = s(.matchScore)
        interest = s(.interest); status = s(.status)
    }

    /// 동기화 때 같은 공고를 찾는 키. career-support의 id(j1, j2…)는 행 순서로 다시 매겨지므로 공고 링크를 쓴다.
    var key: String {
        let base = link.isEmpty ? "\(company)|\(position)" : link
        return "career:" + base
    }

    var isApplied: Bool { CareerSupportConfig.appliedStatuses.contains(status) }

    /// "㈜숲 (SOOP CO., LTD.)" → "숲"
    var shortCompany: String {
        var name = company
        for token in ["㈜", "(주)", "（주）", "주식회사"] { name = name.replacingOccurrences(of: token, with: "") }
        name = name.trimmed
        if let open = name.firstIndex(where: { $0 == "(" || $0 == "（" }) {
            let head = String(name[..<open]).trimmed
            if !head.isEmpty { name = head }
        }
        return name.isEmpty ? company : name
    }

    var todoTitle: String {
        let pos = position.count > 48 ? String(position.prefix(47)) + "…" : position
        return pos.isEmpty ? "\(shortCompany) 지원" : "\(shortCompany) 지원 — \(pos)"
    }

    var todoNotes: String {
        func clip(_ s: String, _ n: Int = 160) -> String { s.count > n ? String(s.prefix(n - 1)) + "…" : s }
        var lines = ["career-support에서 가져온 공고 (마감: \(deadline.isEmpty ? "미정" : deadline))"]
        if !experience.isEmpty || !process.isEmpty {
            lines.append([experience, process.isEmpty ? "" : "전형 \(clip(process, 100))"].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        if !requiredSkills.isEmpty { lines.append("요구스킬: \(clip(requiredSkills))") }
        if !matchScore.isEmpty { lines.append("적합도: \(matchScore)") }
        if !applyMethod.isEmpty { lines.append("지원방법: \(clip(applyMethod))") }
        return lines.joined(separator: "\n")
    }
}

/// 자유 형식 마감 문자열 → 날짜(+시각)
/// "~2026-08-05 17:00", "2026.08.01 ~ 2026.08.31(일)", "~08/31", "채용시까지" 등
struct CareerDeadline: Equatable {
    var date: Date
    var time: Date?

    private static let full = try! NSRegularExpression(
        pattern: #"(\d{4})\s*[-./년]\s*(\d{1,2})\s*[-./월]\s*(\d{1,2})\s*일?(?:\s*\([^)]{1,4}\))?(?:\s*(\d{1,2}):(\d{2}))?"#)
    private static let short = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\s*[/.월]\s*(\d{1,2})\s*일?(?:\s*\([^)]{1,4}\))?(?:\s*(\d{1,2}):(\d{2}))?"#)
    private static let openEnded = ["상시", "채용시", "채용 시", "수시"]

    static func parse(_ raw: String, now: Date = Date()) -> CareerDeadline? {
        let text = raw.trimmed
        guard !text.isEmpty else { return nil }
        if let tilde = text.range(of: "~", options: .backwards) {
            // "시작 ~ 마감" → 물결 뒤가 마감. 뒤에 날짜가 없으면 "~ 채용시"처럼 마감 없음
            return match(in: String(text[tilde.upperBound...]), last: false, now: now)
        }
        if openEnded.contains(where: text.contains) { return nil }
        return match(in: text, last: true, now: now)
    }

    private static func match(in text: String, last: Bool, now: Date) -> CareerDeadline? {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let cal = AppCalendar.current
        func int(_ m: NSTextCheckingResult, _ i: Int) -> Int? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : Int(ns.substring(with: r))
        }
        var found: [(y: Int?, m: Int, d: Int, hh: Int?, mm: Int?)] = []
        for m in full.matches(in: text, range: range) {
            if let y = int(m, 1), let mo = int(m, 2), let d = int(m, 3) { found.append((y, mo, d, int(m, 4), int(m, 5))) }
        }
        if found.isEmpty {
            for m in short.matches(in: text, range: range) {
                if let mo = int(m, 1), let d = int(m, 2) { found.append((nil, mo, d, int(m, 3), int(m, 4))) }
            }
        }
        guard let hit = last ? found.last : found.first, (1...12).contains(hit.m), (1...31).contains(hit.d) else { return nil }

        var comps = DateComponents(year: hit.y ?? cal.component(.year, from: now), month: hit.m, day: hit.d)
        guard var day = cal.date(from: comps) else { return nil }
        // 연도 없는 날짜가 반년 넘게 지났으면 내년으로 본다
        if hit.y == nil, day < now.startOfDay.adding(days: -180) {
            comps.year = (comps.year ?? 0) + 1
            day = cal.date(from: comps) ?? day
        }
        var time: Date?
        // 23:59·24:00 같은 "그날까지"는 시각 없이 날짜만
        if let hh = hit.hh, let mm = hit.mm, (0...23).contains(hh), (0...59).contains(mm), !(hh == 23 && mm >= 59) {
            time = cal.date(bySettingHour: hh, minute: mm, second: 0, of: day)
        }
        return CareerDeadline(date: day.startOfDay, time: time)
    }
}

/// 공고 목록과 현재 할일을 비교해 해야 할 변경을 계산한다 (부수효과 없음 → 테스트 가능).
enum CareerSync {
    enum Action {
        /// 새 마감 할일
        case add(TodoItem, key: String, stamp: String)
        /// career-support에서 마감이 바뀜 → 날짜 옮기기
        case reschedule(id: UUID, date: Date, time: Date?, key: String, stamp: String)
        /// career-support에서 지원완료 이후 상태가 됨
        case complete(id: UUID, key: String)
        /// 기록만 갱신 (설정 초기화 등으로 기록이 없을 때)
        case remember(key: String, stamp: String)
    }

    static func plan(jobs: [CareerJob], todos: [TodoItem], config: CareerSupportConfig, now: Date = Date()) -> [Action] {
        let byKey = Dictionary(todos.compactMap { t in t.sourceKey.map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        let wanted = Set(config.statuses)
        let tag = Tag.normalize(config.tag)
        var seen = Set<String>()
        var actions: [Action] = []

        for job in jobs {
            let key = job.key
            guard seen.insert(key).inserted else { continue }
            let stamp = job.deadline

            if let todo = byKey[key] {
                guard !todo.isDone else { continue }
                if job.isApplied {
                    if config.completeWhenApplied { actions.append(.complete(id: todo.id, key: key)) }
                    continue
                }
                switch config.imported[key] {
                case nil:
                    actions.append(.remember(key: key, stamp: stamp))
                case let old? where old != stamp:
                    // 사용자가 옮긴 날짜는 존중하고, career-support의 마감이 바뀌었을 때만 따라간다
                    if let d = CareerDeadline.parse(stamp, now: now) {
                        actions.append(.reschedule(id: todo.id, date: d.date, time: d.time, key: key, stamp: stamp))
                    } else {
                        actions.append(.remember(key: key, stamp: stamp))
                    }
                default:
                    break
                }
                continue
            }

            // 이미 가져갔는데 할일이 없다 = 사용자가 지웠다 → 다시 만들지 않는다
            guard config.imported[key] == nil, wanted.contains(job.status) || (job.status.isEmpty && wanted.contains("관심")),
                  let d = CareerDeadline.parse(stamp, now: now), d.date >= now.startOfDay
            else { continue }

            var item = TodoItem(title: job.todoTitle, date: d.date, time: d.time, quadrant: .schedule,
                                notes: job.todoNotes, tags: tag.isEmpty ? [] : [tag])
            item.link = job.link.isEmpty ? nil : job.link
            item.sourceKey = key
            actions.append(.add(item, key: key, stamp: stamp))
        }
        return actions
    }
}

/// career-support 웹 화면
enum CareerPage: String, CaseIterable, Identifiable {
    case jobs, strategy, portfolio, generate, dashboard, config

    var id: String { rawValue }
    var path: String { "/" + rawValue }

    var title: String {
        switch self {
        case .jobs: "공고 수집·트렌드"
        case .strategy: "전략 분석"
        case .portfolio: "포트폴리오"
        case .generate: "이력서·포폴 생성"
        case .dashboard: "지원 현황"
        case .config: "설정"
        }
    }

    var symbol: String {
        switch self {
        case .jobs: "magnifyingglass"
        case .strategy: "safari"
        case .portfolio: "folder.fill"
        case .generate: "doc.richtext"
        case .dashboard: "chart.bar.fill"
        case .config: "gearshape"
        }
    }
}

enum CareerError: LocalizedError {
    case notFound
    case missing(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: "career-support 폴더를 찾지 못했어요. 설정 → 커리어에서 폴더를 지정해 주세요."
        case let .missing(s), let .failed(s): s
        }
    }
}

@MainActor
@Observable
final class CareerSupportService {
    /// 마지막으로 읽은 공고
    private(set) var jobs: [CareerJob] = []
    private(set) var isSyncing = false
    private(set) var isLaunching = false
    private(set) var lastSyncAt: Date?
    private(set) var lastMessage: String?
    private(set) var lastError: String?
    /// CharTodo가 켠 서버가 돌고 있는지
    private(set) var ownsServers = false
    private(set) var webPort = 2500

    @ObservationIgnored private unowned let env: AppEnvironment
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSeenModified: Date?
    @ObservationIgnored private var launched: [Process] = []

    init(env: AppEnvironment) {
        self.env = env
    }

    private var config: CareerSupportConfig { env.settings.settings.career }

    // MARK: 경로

    static func isValidRoot(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath + "/backend/app/services/excel_store.py")
    }

    static func detectRoot() -> String? {
        let home = NSHomeDirectory()
        return ["Documents/GitHub", "GitHub", "Developer", "Projects", "Documents", ""]
            .map { ($0.isEmpty ? home : "\(home)/\($0)") + "/career-support" }
            .first(where: isValidRoot)
    }

    /// 실제로 쓸 career-support 폴더 (설정값 → 자동 탐색)
    var root: String? {
        let custom = config.path.trimmed
        if !custom.isEmpty { return Self.isValidRoot(custom) ? (custom as NSString).expandingTildeInPath : nil }
        return Self.detectRoot()
    }

    var isAvailable: Bool { root != nil }

    var webURL: URL { URL(string: "http://localhost:\(webPort)")! }

    func url(for page: CareerPage) -> URL { webURL.appendingPathComponent(page.rawValue) }

    static var logDir: URL {
        let dir = Persistence.baseURL.appendingPathComponent("career-logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 마감이 다가오는(지원 전) 공고, 가까운 순
    var upcoming: [(job: CareerJob, deadline: CareerDeadline)] {
        let today = Date().startOfDay
        return jobs.compactMap { j in
            guard !j.isApplied, let d = CareerDeadline.parse(j.deadline), d.date >= today else { return nil }
            return (j, d)
        }
        .sorted { $0.deadline.date < $1.deadline.date }
    }

    // MARK: 동기화

    func start() {
        timer?.invalidate()
        // 1분마다 jobs.xlsx 수정 시각만 확인하고, 바뀌었을 때만 읽는다
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncIfChanged() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.syncIfChanged() }
    }

    /// 연동이 꺼져 있어도 공고는 읽어 둔다 (사이드바의 마감 임박 표시용) — 할일 반영은 sync()가 설정을 보고 한다
    func syncIfChanged() {
        guard let root else { return }
        let xlsx = URL(fileURLWithPath: root + "/backend/data/jobs.xlsx")
        let modified = (try? xlsx.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != nil, modified != lastSeenModified else { return }
        lastSeenModified = modified
        Task { await sync(manual: false) }
    }

    /// 공고를 읽고, 연동이 켜져 있으면 할일에 반영한다.
    func sync(manual: Bool) async {
        guard !isSyncing else { return }
        guard let root else {
            lastError = CareerError.notFound.localizedDescription
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let export = try await Self.export(root: root)
            jobs = export.jobs
            webPort = export.webPort ?? 2500
            lastSyncAt = Date()
            lastError = nil
            guard config.syncEnabled else {
                lastMessage = "공고 \(jobs.count)건을 읽었어요 (할일 가져오기는 꺼져 있음)"
                return
            }
            let summary = apply(CareerSync.plan(jobs: jobs, todos: env.store.todos, config: config))
            lastMessage = summary ?? "새로 가져올 마감이 없어요 · 공고 \(jobs.count)건"
            if let summary, !manual || env.floating.isCompanionVisible {
                env.companion.say("📮 career-support: \(summary)", duration: 6)
            }
        } catch {
            lastError = error.localizedDescription
            if manual { env.companion.say("career-support 동기화 실패 😢", duration: 4) }
        }
    }

    /// 변경을 적용하고 요약 문장을 돌려준다 (변경이 없으면 nil)
    private func apply(_ actions: [CareerSync.Action]) -> String? {
        var imported = config.imported
        var added = 0, moved = 0, done = 0
        for action in actions {
            switch action {
            case let .add(item, key, stamp):
                env.store.add(item)
                imported[key] = stamp
                added += 1
            case let .reschedule(id, date, time, key, stamp):
                env.store.mutate(id) { t in
                    t.scope = .day
                    t.date = date
                    t.time = time
                }
                imported[key] = stamp
                moved += 1
            case let .complete(id, _):
                env.store.mutate(id) { t in
                    t.isDone = true
                    for i in t.subtasks.indices { t.subtasks[i].isDone = true }
                }
                done += 1
            case let .remember(key, stamp):
                imported[key] = stamp
            }
        }
        if imported != config.imported { env.settings.settings.career.imported = imported }
        let parts = [added > 0 ? "새 마감 \(added)개" : nil, moved > 0 ? "마감 변경 \(moved)개" : nil,
                     done > 0 ? "지원 완료 \(done)개" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 지운 할일까지 다시 가져올 수 있게 기록을 비운다
    func resetImported() {
        env.settings.settings.career.imported = [:]
        lastSeenModified = nil
    }

    private struct Export: Decodable {
        var jobs: [CareerJob]
        var webPort: Int?
        var error: String?
        enum CodingKeys: String, CodingKey {
            case jobs, error
            case webPort = "web_port"
        }
    }

    private static func export(root: String) async throws -> Export {
        let python = root + "/backend/.venv/bin/python"
        let script = root + "/backend/export_jobs.py"
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw CareerError.missing("career-support 백엔드 가상환경이 없어요. backend 폴더에서 python3 -m venv .venv && pip install -r requirements.txt 를 먼저 실행해 주세요.")
        }
        guard FileManager.default.fileExists(atPath: script) else {
            throw CareerError.missing("career-support에 backend/export_jobs.py가 없어요. 최신 버전으로 업데이트해 주세요.")
        }
        let result = try await ProcessRunner.run(python, [script], cwd: root + "/backend", timeout: 30)
        let decoded = try? JSONDecoder().decode(Export.self, from: result.stdout)
        if let decoded, decoded.error == nil { return decoded }
        let reason = decoded?.error ?? String(decoding: result.stderr, as: UTF8.self).trimmed
        throw CareerError.failed("공고 읽기 실패: \(reason.isEmpty ? "종료 코드 \(result.status)" : String(reason.suffix(300)))")
    }

    // MARK: 바로 가기

    /// career-support 웹 화면 열기. 꺼져 있으면 (설정에 따라) 서버를 켠 뒤 연다.
    func open(_ page: CareerPage = .jobs) {
        guard let root else {
            env.openSettings(tab: SettingsTab.career.rawValue)
            env.companion.say("career-support 폴더를 먼저 지정해 주세요 📂", duration: 4)
            return
        }
        guard !isLaunching else { return }
        let target = url(for: page)
        Task {
            if await Self.responds(webURL) {
                NSWorkspace.shared.open(target)
                return
            }
            guard config.autoStartServers else {
                lastError = "career-support가 꺼져 있어요. 설정 → 커리어에서 '자동으로 켜기'를 켜거나 직접 실행해 주세요."
                env.companion.say("career-support가 꺼져 있어요", duration: 4)
                return
            }
            isLaunching = true
            defer { isLaunching = false }
            env.companion.say("career-support 켜는 중… ⏳", duration: 20)
            do {
                try await startServers(root: root)
                env.companion.say("career-support 열었어요 💼", duration: 3)
                NSWorkspace.shared.open(target)
            } catch {
                lastError = error.localizedDescription
                env.companion.say("career-support를 켜지 못했어요 😢", duration: 5)
            }
        }
    }

    private func startServers(root: String) async throws {
        let backend = root + "/backend"
        let frontend = root + "/frontend"

        // 1) 백엔드 — run.py가 고른 포트를 backend-port.txt에 쓰고, vite가 그걸 보고 프록시한다
        var backendUp = false
        if let health = backendHealthURL(backend) { backendUp = await Self.responds(health) }
        if !backendUp {
            let python = backend + "/.venv/bin/python"
            guard FileManager.default.isExecutableFile(atPath: python) else {
                throw CareerError.missing("백엔드 가상환경(backend/.venv)이 없어요.")
            }
            let p = try launch(python, ["run.py"], cwd: backend, log: "backend.log")
            try await waitUntil(p, log: "backend.log", seconds: 25) { [weak self] in
                guard let url = self?.backendHealthURL(backend) else { return false }
                return await Self.responds(url)
            }
        }

        // 2) 프론트 (Vite) — npm을 거치지 않고 node로 직접 실행해야 끌 때 깔끔하게 정리된다
        if !(await Self.responds(webURL)) {
            let vite = frontend + "/node_modules/vite/bin/vite.js"
            guard FileManager.default.fileExists(atPath: vite) else {
                throw CareerError.missing("프론트 의존성이 없어요. frontend 폴더에서 npm install을 먼저 실행해 주세요.")
            }
            let p = try launch("/usr/bin/env", ["node", vite], cwd: frontend, log: "frontend.log")
            let web = webURL
            try await waitUntil(p, log: "frontend.log", seconds: 30) { await Self.responds(web) }
        }
    }

    private func backendHealthURL(_ backend: String) -> URL? {
        let raw = (try? String(contentsOfFile: backend + "/data/backend-port.txt", encoding: .utf8))?.trimmed ?? ""
        return URL(string: "http://127.0.0.1:\(Int(raw) ?? 6700)/api/health")
    }

    private func launch(_ executable: String, _ args: [String], cwd: String, log: String) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ClaudeCodeLocator.extendedPATH
        env["PYTHONUNBUFFERED"] = "1"
        env["BROWSER"] = "none"
        p.environment = env
        let logURL = Self.logDir.appendingPathComponent(log)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        p.standardOutput = handle
        p.standardError = handle
        p.standardInput = FileHandle.nullDevice
        try p.run()
        launched.append(p)
        ownsServers = true
        return p
    }

    private func waitUntil(_ process: Process, log: String, seconds: Int, ready: @escaping () async -> Bool) async throws {
        for _ in 0..<(seconds * 2) {
            if await ready() { return }
            if !process.isRunning {
                let tail = (try? String(contentsOf: Self.logDir.appendingPathComponent(log), encoding: .utf8))?
                    .split(separator: "\n").suffix(4).joined(separator: "\n") ?? ""
                throw CareerError.failed("career-support 실행이 멈췄어요 (\(log))\n\(tail)")
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw CareerError.failed("career-support가 \(seconds)초 안에 뜨지 않았어요. 로그: \(log)")
    }

    /// CharTodo가 켠 서버만 끈다
    func stopLaunchedServers() {
        for p in launched where p.isRunning { p.terminate() }
        launched.removeAll()
        ownsServers = false
    }

    func shutdown() {
        timer?.invalidate()
        if config.stopServersOnQuit { stopLaunchedServers() }
    }

    static func responds(_ url: URL) async -> Bool {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.5)
        req.httpMethod = "GET"
        guard let (_, response) = try? await URLSession.shared.data(for: req) else { return false }
        return ((response as? HTTPURLResponse)?.statusCode ?? 500) < 500
    }
}

/// 짧게 끝나는 외부 명령 실행 (출력 전체를 받아온다)
enum ProcessRunner {
    struct Result { var status: Int32; var stdout: Data; var stderr: Data }

    static func run(_ executable: String, _ args: [String], cwd: String, timeout: TimeInterval) async throws -> Result {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = args
                p.currentDirectoryURL = URL(fileURLWithPath: cwd)
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    cont.resume(throwing: CareerError.failed(error.localizedDescription))
                    return
                }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                // stderr를 따로 비워 줘야 파이프가 차서 멈추지 않는다
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                p.waitUntilExit()
                killer.cancel()
                cont.resume(returning: Result(status: p.terminationStatus, stdout: outData, stderr: errData))
            }
        }
    }
}
