import Foundation

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case ollama, openAICompatible, anthropic, claudeCode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ollama: "Ollama (로컬)"
        case .openAICompatible: "OpenAI 호환 API / LM Studio"
        case .anthropic: "Claude API (Anthropic 키)"
        case .claudeCode: "Claude Code CLI"
        }
    }

    var shortLabel: String {
        switch self {
        case .ollama: "Ollama"
        case .openAICompatible: "OpenAI 호환"
        case .anthropic: "Claude API"
        case .claudeCode: "Claude Code"
        }
    }

    var symbol: String {
        switch self {
        case .ollama: "desktopcomputer"
        case .openAICompatible: "network"
        case .anthropic: "key.fill"
        case .claudeCode: "terminal.fill"
        }
    }
}

struct LLMConfig: Codable, Equatable {
    var provider: LLMProvider = .ollama

    var ollamaBaseURL = "http://localhost:11434"
    var ollamaModel = ""

    var openAIBaseURL = "http://localhost:1234/v1"
    var openAIModel = ""

    var anthropicModel = "claude-opus-5-5"
    /// low / medium / high
    var anthropicEffort = "low"

    /// 비우면 자동 탐색
    var claudeCodePath = ""
    /// 비우면 Claude Code 기본 모델
    var claudeCodeModel = ""

    var maxTokens = 2048

    var activeModelLabel: String {
        switch provider {
        case .ollama: ollamaModel.isEmpty ? "모델 미선택" : ollamaModel
        case .openAICompatible: openAIModel.isEmpty ? "모델 미선택" : openAIModel
        case .anthropic: anthropicModel
        case .claudeCode: claudeCodeModel.isEmpty ? "기본 모델" : claudeCodeModel
        }
    }
}

enum AssistantTone: String, Codable, CaseIterable, Identifiable {
    case friend, secretary, coach, tsundere
    var id: String { rawValue }
    var label: String {
        switch self {
        case .friend: "다정한 친구 (반말)"
        case .secretary: "든든한 비서 (존댓말)"
        case .coach: "열정 코치"
        case .tsundere: "츤데레"
        }
    }
    var instruction: String {
        switch self {
        case .friend: "친한 친구처럼 다정한 반말로 말해. 가볍고 따뜻하게."
        case .secretary: "유능한 개인 비서처럼 정중한 존댓말로 간결하게 말하세요."
        case .coach: "에너지 넘치는 코치처럼 동기부여하며 짧고 힘 있게 말해. 반말."
        case .tsundere: "츤데레 말투(겉으론 퉁명, 속으론 챙겨줌)의 반말로 말해. 선을 넘지 않게 귀엽게."
        }
    }
}

/// 캐릭터가 특정 상황에서 쓰는 표현
enum PersonaSituation: String, Codable, CaseIterable, Identifiable {
    case greeting, briefing, taskDone, allDone, overdue, cheer, wrapUp, thinking

    var id: String { rawValue }

    var label: String {
        switch self {
        case .greeting: "인사 (앱 켤 때)"
        case .briefing: "브리핑 시작"
        case .taskDone: "할일 완료 칭찬"
        case .allDone: "오늘 할일 전부 완료"
        case .overdue: "밀린 일 알림"
        case .cheer: "응원 · 격려"
        case .wrapUp: "하루 마무리"
        case .thinking: "생각 중일 때"
        }
    }

    var symbol: String {
        switch self {
        case .greeting: "hand.wave.fill"
        case .briefing: "megaphone.fill"
        case .taskDone: "checkmark.seal.fill"
        case .allDone: "party.popper.fill"
        case .overdue: "exclamationmark.bubble.fill"
        case .cheer: "flame.fill"
        case .wrapUp: "moon.zzz.fill"
        case .thinking: "ellipsis.bubble.fill"
        }
    }

    var placeholder: String {
        switch self {
        case .greeting: "예) 좋은 아침이다냥! 오늘도 같이 힘내자냥"
        case .briefing: "예) 자, 오늘의 할일 브리핑 시작한다냥!"
        case .taskDone: "예) 읏차! 하나 끝냈다냥 🎉"
        case .allDone: "예) 오늘 할일 올클리어! 최고다냥!!"
        case .overdue: "예) 밀린 일이 {n}개 있다냥… 같이 해치우자냥"
        case .cheer: "예) 할 수 있다냥, 조금만 더!"
        case .wrapUp: "예) 오늘도 수고했다냥, 푹 쉬라냥 🌙"
        case .thinking: "예) 으음… 생각 중이다냥"
        }
    }

    /// 사용자가 아무것도 안 넣었을 때 쓰는 기본 말풍선 (로컬 표시용)
    var fallback: [String] {
        switch self {
        case .greeting: ["안녕! 오늘도 같이 해 보자 ✨"]
        case .briefing: ["오늘 할일 브리핑 시작할게!"]
        case .taskDone: ["잘했어요! 🎉", "하나 끝! ✨", "멋져요 👍", "이 기세 그대로! 🔥", "체크 완료 ✅"]
        case .allDone: ["오늘 할일 올클리어! 🏆"]
        case .overdue: ["밀린 일이 {n}개 있어요. 오늘로 옮겨 볼까요?"]
        case .cheer: ["조금만 더 힘내요! 💪"]
        case .wrapUp: ["오늘도 수고했어요 🌙"]
        case .thinking: ["생각 중"]
        }
    }

    /// 프롬프트에 넣을 상황 설명
    var promptLabel: String {
        switch self {
        case .greeting: "인사할 때"
        case .briefing: "브리핑을 시작할 때 (첫 문장)"
        case .taskDone: "사용자가 할일을 끝낸 걸 칭찬할 때"
        case .allDone: "오늘 할일을 전부 끝냈을 때"
        case .overdue: "밀린 할일을 알려 줄 때"
        case .cheer: "응원·격려할 때 (답변 마무리)"
        case .wrapUp: "하루를 마무리할 때"
        case .thinking: "고민하거나 생각할 때"
        }
    }
}

enum CatchphraseFrequency: String, Codable, CaseIterable, Identifiable {
    case rarely, sometimes, often
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rarely: "가끔"
        case .sometimes: "적당히"
        case .often: "자주"
        }
    }
    var instruction: String {
        switch self {
        case .rarely: "가끔(답변 2~3번에 한 번 정도)"
        case .sometimes: "답변마다 한 번 정도"
        case .often: "답변마다 여러 번, 문장 곳곳에"
        }
    }
}

/// 말투·말버릇·상황별 표현
struct PersonaConfig: Codable, Equatable {
    /// 자유 서술 말투 설명
    var styleDescription = ""
    /// 문장 끝 어미 (예: ~다냥)
    var sentenceEnding = ""
    /// 말버릇
    var catchphrases: [String] = []
    var catchphraseFrequency: CatchphraseFrequency = .sometimes
    /// 상황별 표현 (키: PersonaSituation.rawValue)
    var situationLines: [String: [String]] = [:]
    /// 쓰지 말아야 할 표현
    var avoid = ""

    func lines(for situation: PersonaSituation) -> [String] {
        (situationLines[situation.rawValue] ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var isEmpty: Bool {
        styleDescription.isEmpty && sentenceEnding.isEmpty && catchphrases.isEmpty
            && situationLines.values.allSatisfy(\.isEmpty) && avoid.isEmpty
    }

    /// 말풍선용 문장 하나 고르기. {n} {이름} 치환
    func pick(_ situation: PersonaSituation, name: String, count: Int? = nil) -> String {
        let pool = lines(for: situation)
        var line = (pool.isEmpty ? situation.fallback : pool).randomElement() ?? ""
        line = line.replacingOccurrences(of: "{이름}", with: name)
        if let count { line = line.replacingOccurrences(of: "{n}", with: "\(count)") }
        return line
    }

    static let presets: [(name: String, config: PersonaConfig)] = [
        ("🐱 고양이 (~냥)", PersonaConfig(
            styleDescription: "호기심 많고 애교 있는 고양이. 가끔 그루밍하거나 하품하는 시늉을 한다.",
            sentenceEnding: "~냥 / ~다냥",
            catchphrases: ["냐앙", "골골"],
            catchphraseFrequency: .sometimes,
            situationLines: [
                "greeting": ["좋은 아침이다냥! 오늘도 같이 힘내자냥 🐾"],
                "taskDone": ["읏차! 하나 끝냈다냥 🎉", "잘했다냥~ 골골"],
                "allDone": ["오늘 할일 올클리어다냥!! 츄르 줘라냥 🏆"],
                "overdue": ["밀린 일이 {n}개 있다냥… 같이 해치우자냥"],
                "wrapUp": ["오늘도 수고했다냥, 푹 자라냥 🌙"],
            ],
            avoid: "딱딱한 보고서 말투")),
        ("🦁 느긋한 사자 (하암~)", PersonaConfig(
            styleDescription: "느긋하고 졸린 듯하지만 할 일은 꼭 챙겨 주는 아기 사자. 문장이 짧고 포근하다.",
            sentenceEnding: "~어흥 / ~다요",
            catchphrases: ["하암~", "어흥!"],
            catchphraseFrequency: .rarely,
            situationLines: [
                "greeting": ["하암~ 좋은 아침이다요. 오늘 할일 같이 보자요"],
                "taskDone": ["어흥! 하나 해치웠다요 🦁", "오오, 멋지다요!"],
                "allDone": ["다 끝냈다요! 이제 같이 낮잠 자자요 💤"],
                "overdue": ["으음… 밀린 게 {n}개 있다요. 천천히 하나씩 하자요"],
                "cheer": ["조금만 더 힘내자요, 어흥!"],
            ],
            avoid: "")),
        ("💼 깔끔한 비서", PersonaConfig(
            styleDescription: "정중하고 간결한 개인 비서. 핵심부터 말하고 숫자로 정리한다.",
            sentenceEnding: "~입니다 / ~습니다",
            catchphrases: [],
            catchphraseFrequency: .rarely,
            situationLines: [
                "greeting": ["좋은 아침입니다. 오늘 일정을 정리해 두었습니다."],
                "taskDone": ["완료 처리했습니다. 잘하셨습니다."],
                "overdue": ["지연된 업무가 {n}건 있습니다. 우선 처리를 권장드립니다."],
            ],
            avoid: "이모지 남발, 반말")),
    ]
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case themeDefault, system, rounded, monospaced, serif, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .themeDefault: "테마 기본"
        case .system: "시스템"
        case .rounded: "라운드"
        case .monospaced: "모노스페이스"
        case .serif: "세리프"
        case .custom: "설치된 폰트 직접 선택"
        }
    }
}

struct AppSettings: Codable, Equatable {
    // 테마
    var themeID = "creamLion"
    var accentOverrideHex: String?
    var fontChoice: FontChoice = .themeDefault
    var customFontName = ""
    var showPattern = true

    // 일반
    var firstWeekday = 2
    /// 태그별 사용자 지정 색 (없으면 이름으로 자동 배정)
    var tagColors: [String: String] = [:]
    var celebrateOnComplete = true

    // 어시스턴트
    var llm = LLMConfig()
    var assistantName = "플로피"
    var assistantTone: AssistantTone = .friend
    var persona = PersonaConfig()
    /// 채팅에서 "추가해줘" 한 할일을 버튼 없이 바로 등록
    var chatAutoAdd = true
    var autoBriefingEnabled = false
    var autoBriefingHour = 9
    var autoBriefingMinute = 0
    var lastAutoBriefingDay: String?

    // 캐릭터
    var showFloatingCharacter = true
    /// 앱을 쓰는 동안에는 메인 창 안에서 뛰어다니기
    var roamInApp = true
    var character = CharacterRig()

    // 캘린더
    var calendarEnabled = false
    var hiddenCalendarIDs: [String] = []
    var exportCalendarID: String?
    var autoAddTimedTodosToCalendar = false

    // career-support 연동
    var career = CareerSupportConfig()
}

/// career-support(채용 공고 관리 툴) 연동 설정
struct CareerSupportConfig: Codable, Equatable {
    /// 공고 마감일을 할일로 가져오기
    var syncEnabled = false
    /// career-support 저장소 폴더 (비우면 자동 탐색)
    var path = ""
    /// 가져온 할일에 붙일 태그
    var tag = "취업"
    /// 할일로 가져올 지원 상태
    var statuses = ["관심", "지원예정"]
    /// career-support에서 지원완료 이후 상태가 되면 할일도 완료 처리
    var completeWhenApplied = true
    /// 바로 가기를 눌렀는데 꺼져 있으면 백엔드·프론트를 켜기
    var autoStartServers = true
    /// CharTodo가 켠 서버는 CharTodo를 끌 때 같이 끄기
    var stopServersOnQuit = true
    /// 이미 가져온 공고 (출처 키 → 마감 원문). 지운 할일을 다시 만들지 않고, 마감이 바뀌었을 때만 날짜를 고친다.
    var imported: [String: String] = [:]

    static let jobStatuses = ["관심", "지원예정", "지원완료", "서류합격", "면접", "최종합격", "탈락"]
    /// 이 상태가 되면 "지원했다"로 본다
    static let appliedStatuses: Set<String> = ["지원완료", "서류합격", "면접", "최종합격", "탈락"]
}

/// 저장된 JSON에 없는 키는 기본값으로 채워서 디코딩한다 (버전 업에도 설정 유지).
enum DefaultsMerging {
    static func decode<T: Codable>(_ data: Data, defaults: T) -> T {
        let encoder = JSONEncoder()
        guard let defaultData = try? encoder.encode(defaults),
              let base = try? JSONSerialization.jsonObject(with: defaultData),
              let stored = try? JSONSerialization.jsonObject(with: data)
        else { return (try? JSONDecoder().decode(T.self, from: data)) ?? defaults }
        let merged = merge(base, stored)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let value = try? JSONDecoder().decode(T.self, from: mergedData)
        else { return defaults }
        return value
    }

    static func merge(_ base: Any, _ override: Any) -> Any {
        guard let b = base as? [String: Any], let o = override as? [String: Any] else { return override }
        var result = b
        for (k, v) in o {
            if let bv = b[k] { result[k] = merge(bv, v) } else { result[k] = v }
        }
        return result
    }
}
