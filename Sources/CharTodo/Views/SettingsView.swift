import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case theme, ai, persona, character, calendar, general
    var id: String { rawValue }
    var label: String {
        switch self {
        case .theme: "테마"
        case .ai: "AI 비서"
        case .persona: "말투"
        case .character: "캐릭터"
        case .calendar: "캘린더"
        case .general: "일반"
        }
    }
}

struct SettingsView: View {
    @Environment(\.theme) private var theme
    var embedded = false
    @State private var tab: SettingsTab = .theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("설정").font(theme.titleFont(28)).foregroundStyle(theme.text)
                Spacer()
                RetroSegmented(options: SettingsTab.allCases, selection: $tab) { $0.label }
                    .frame(width: 500)
            }
            .padding(.top, embedded ? 16 : 20)
            .padding(.horizontal, 24)

            ScrollView {
                Group {
                    switch tab {
                    case .theme: ThemeSettings()
                    case .ai: AISettings()
                    case .persona: PersonaSettingsView()
                    case .character: CharacterEditorView()
                    case .calendar: CalendarSettings()
                    case .general: GeneralSettings()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(embedded ? Color.clear : theme.background)
        .onReceive(NotificationCenter.default.publisher(for: .settingsTabRequest)) { note in
            if let raw = note.object as? String, let t = SettingsTab(rawValue: raw) { tab = t }
        }
    }
}

/// 설정 카드 공통 틀
struct SettingsCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var title: String
    var symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title, symbol: symbol)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroCard()
    }
}

struct SettingRow<Content: View>: View {
    @Environment(\.theme) private var theme
    var label: String
    var help: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(theme.font(12.5, .bold)).foregroundStyle(theme.text)
                if let help { Text(help).font(theme.font(10.5)).foregroundStyle(theme.textMuted) }
            }
            .frame(width: 170, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 테마

struct ThemeSettings: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var store
    @State private var fontQuery = ""

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "뉴트로 테마", symbol: "paintpalette.fill") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(Theme.all) { t in
                        ThemePreviewCard(preview: t, selected: store.settings.themeID == t.id) {
                            store.settings.themeID = t.id
                        }
                    }
                }
            }

            SettingsCard(title: "세부 조정", symbol: "slider.horizontal.3") {
                SettingRow(label: "포인트 색상", help: "테마의 강조색을 바꿔요") {
                    ColorPicker("", selection: Binding(
                        get: { theme.accent },
                        set: { store.settings.accentOverrideHex = $0.hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    if store.settings.accentOverrideHex != nil {
                        Button("기본값") { store.settings.accentOverrideHex = nil }.buttonStyle(.retro(.secondary, compact: true))
                    }
                }
                SettingRow(label: "글꼴", help: "갈무리·둥근모꼴 같은 픽셀 폰트를 설치하면 더 뉴트로해요") {
                    Picker("", selection: $store.settings.fontChoice) {
                        ForEach(FontChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                if store.settings.fontChoice == .custom {
                    SettingRow(label: "설치된 폰트") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("폰트 검색 (예: Galmuri, DungGeunMo)", text: $fontQuery).retroField().frame(width: 280)
                            let families = NSFontManager.shared.availableFontFamilies
                                .filter { fontQuery.isEmpty || $0.localizedCaseInsensitiveContains(fontQuery) }
                                .prefix(40)
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(families), id: \.self) { fam in
                                        let name = NSFontManager.shared.availableMembers(ofFontFamily: fam)?.first?.first as? String ?? fam
                                        Button {
                                            store.settings.customFontName = name
                                        } label: {
                                            HStack {
                                                Text(fam).font(.custom(name, size: 13))
                                                Text("가나다 ABC 123").font(.custom(name, size: 12)).foregroundStyle(theme.textMuted)
                                                Spacer()
                                                if store.settings.customFontName == name { Image(systemName: "checkmark") }
                                            }
                                            .padding(.vertical, 3).padding(.horizontal, 6)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(width: 380, height: 160)
                            .retroCard(shadow: false)
                        }
                    }
                }
                SettingRow(label: "배경 패턴") {
                    Toggle("", isOn: $store.settings.showPattern).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }
}

struct ThemePreviewCard: View {
    let preview: Theme
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    preview.background
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Circle().fill(preview.highlight).frame(width: 7, height: 7)
                            Text("TODAY.TXT").font(.system(size: 9, weight: .bold, design: preview.fontDesign))
                            Spacer()
                        }
                        .foregroundStyle(preview.titleBarText)
                        .padding(.horizontal, 6).frame(height: 16)
                        .background(preview.titleBar)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(i == 0 ? preview.accent : preview.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(preview.border, lineWidth: 1))
                                        .frame(width: 9, height: 9)
                                    RoundedRectangle(cornerRadius: 2).fill(preview.quadrantColors[i]).frame(width: 3, height: 9)
                                    RoundedRectangle(cornerRadius: 2).fill(preview.text.opacity(0.75)).frame(width: CGFloat(90 - i * 18), height: 5)
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(preview.surface)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: min(6, preview.cornerRadius)))
                    .overlay(RoundedRectangle(cornerRadius: min(6, preview.cornerRadius)).strokeBorder(preview.border, lineWidth: 1.5))
                    .background(RoundedRectangle(cornerRadius: min(6, preview.cornerRadius)).fill(preview.shadow).offset(x: 3, y: 3))
                    .padding(14)
                }
                .frame(height: 104)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.name).font(.system(size: 13, weight: .heavy, design: preview.fontDesign))
                    Text(preview.tagline).font(.system(size: 10.5, design: preview.fontDesign)).lineLimit(1)
                        .opacity(0.75)
                }
                .foregroundStyle(preview.text)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(preview.surfaceAlt)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? preview.accent : preview.border.opacity(0.5), lineWidth: selected ? 3 : 1.5))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(preview.accent, .white)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI

struct AISettings: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var store

    @State private var openAIKey = KeychainStore.get(KeychainStore.openAIAccount) ?? ""
    @State private var anthropicKey = KeychainStore.get(KeychainStore.anthropicAccount) ?? ""
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var modelError: String?
    @State private var testOutput = ""
    @State private var testing = false
    @State private var keySaved = false

    var body: some View {
        @Bindable var store = store
        let provider = store.settings.llm.provider
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "AI 공급자", symbol: "cpu.fill") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(LLMProvider.allCases) { p in
                        Button {
                            store.settings.llm.provider = p
                            models = []
                            modelError = nil
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: p.symbol).font(.system(size: 16, weight: .bold))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.shortLabel).font(theme.font(13, .heavy))
                                    Text(providerHint(p)).font(theme.font(10)).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .foregroundStyle(provider == p ? theme.onAccent : theme.text)
                            .retroCard(fill: provider == p ? theme.accent : theme.surface, shadow: provider == p)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            SettingsCard(title: provider.label, symbol: provider.symbol) {
                switch provider {
                case .ollama:
                    SettingRow(label: "서버 주소") {
                        TextField("http://localhost:11434", text: $store.settings.llm.ollamaBaseURL).retroField().frame(width: 300)
                    }
                    modelRow(selection: $store.settings.llm.ollamaModel, placeholder: "예: llama3.2, qwen2.5:7b, gemma3")
                    Text("Ollama 설치 후 터미널에서 `ollama pull qwen2.5:7b` 처럼 모델을 받아 두세요. 한국어는 qwen·gemma 계열이 잘 해요.")
                        .font(theme.font(11)).foregroundStyle(theme.textMuted)
                case .openAICompatible:
                    SettingRow(label: "Base URL", help: "LM Studio: http://localhost:1234/v1") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("https://api.openai.com/v1", text: $store.settings.llm.openAIBaseURL).retroField().frame(width: 320)
                            HStack(spacing: 4) {
                                presetButton("LM Studio", "http://localhost:1234/v1")
                                presetButton("OpenAI", "https://api.openai.com/v1")
                                presetButton("OpenRouter", "https://openrouter.ai/api/v1")
                                presetButton("Gemini", "https://generativelanguage.googleapis.com/v1beta/openai")
                            }
                        }
                    }
                    keyRow(text: $openAIKey, account: KeychainStore.openAIAccount, help: "로컬 서버는 비워도 돼요")
                    modelRow(selection: $store.settings.llm.openAIModel, placeholder: "모델 ID")
                case .anthropic:
                    keyRow(text: $anthropicKey, account: KeychainStore.anthropicAccount, help: "console.anthropic.com 에서 발급")
                    SettingRow(label: "모델") {
                        Picker("", selection: $store.settings.llm.anthropicModel) {
                            Text("Claude Opus 5.5").tag("claude-opus-5-5")
                            Text("Claude Sonnet 5.5").tag("claude-sonnet-5-5")
                            Text("Claude Haiku 4.5").tag("claude-haiku-4-5")
                            if !["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"].contains(store.settings.llm.anthropicModel) {
                                Text(store.settings.llm.anthropicModel).tag(store.settings.llm.anthropicModel)
                            }
                        }
                        .labelsHidden().frame(width: 220)
                    }
                    SettingRow(label: "생각 깊이 (effort)", help: "낮을수록 빠르고 저렴해요") {
                        RetroSegmented(options: ["low", "medium", "high"], selection: $store.settings.llm.anthropicEffort) {
                            ["low": "빠르게", "medium": "보통", "high": "깊게"][$0] ?? $0
                        }
                        .frame(width: 240)
                    }
                    Text("Opus/Sonnet 5.5에서는 안전 필터로 응답이 거절될 때 다른 모델로 자동 재시도하는 서버측 폴백(fallbacks: \"default\")이 켜져 있어요.")
                        .font(theme.font(10.5)).foregroundStyle(theme.textMuted)
                case .claudeCode:
                    let detected = ClaudeCodeLocator.locate(custom: store.settings.llm.claudeCodePath)
                    SettingRow(label: "claude 경로", help: "비우면 자동으로 찾아요") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("자동 탐색", text: $store.settings.llm.claudeCodePath).retroField().frame(width: 340)
                            Text(detected.map { "✓ 찾음: \($0)" } ?? "✗ claude 를 찾지 못했어요")
                                .font(theme.font(10.5)).foregroundStyle(detected == nil ? .red : theme.accent2)
                                .lineLimit(1).truncationMode(.middle).frame(width: 340, alignment: .leading)
                        }
                    }
                    SettingRow(label: "모델 (선택)", help: "예: sonnet, opus, haiku") {
                        TextField("Claude Code 기본값", text: $store.settings.llm.claudeCodeModel).retroField().frame(width: 200)
                    }
                    Text("내 Mac의 Claude Code CLI를 `claude -p` 헤드리스 모드로 호출해요. Claude 구독 로그인을 그대로 쓰므로 API 키가 필요 없어요. 터미널에서 `claude` 를 한 번 실행해 로그인해 두세요.")
                        .font(theme.font(11)).foregroundStyle(theme.textMuted)
                }

                HStack(spacing: 8) {
                    Button {
                        runTest()
                    } label: {
                        if testing { ProgressView().controlSize(.small) } else { Label("연결 테스트", systemImage: "bolt.horizontal.fill") }
                    }
                    .buttonStyle(.retro(.primary, compact: true))
                    .disabled(testing)
                    if !testOutput.isEmpty {
                        Text(testOutput).font(theme.font(11.5)).foregroundStyle(theme.text).lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }

            SettingsCard(title: "채팅으로 할일 추가", symbol: "text.badge.plus") {
                SettingRow(label: "요청하면 바로 추가", help: "\"내일 3시 회의 #업무 추가해줘\" → 날짜·시간·태그·세부 테스크까지 채워서 등록. 끄면 버튼으로 확인 후 추가") {
                    Toggle("", isOn: $store.settings.chatAutoAdd).toggleStyle(.switch).labelsHidden()
                }
                Text("채팅창에 + 로 시작하면 AI 없이 빠른 입력 문법으로 즉시 추가돼요. 예) + 팀 회의 @내일 ~15:00 #업무 !1")
                    .font(theme.font(11)).foregroundStyle(theme.textMuted)
            }

            SettingsCard(title: "자동 브리핑", symbol: "alarm.fill") {
                Text("이름·말투·말버릇은 '말투' 탭에서 설정해요.")
                    .font(theme.font(11)).foregroundStyle(theme.textMuted)
                SettingRow(label: "아침 자동 브리핑", help: "앱이 켜져 있으면 지정 시각에 한 번 브리핑해요") {
                    Toggle("", isOn: $store.settings.autoBriefingEnabled).toggleStyle(.switch).labelsHidden()
                    if store.settings.autoBriefingEnabled {
                        DatePicker("", selection: Binding(
                            get: { AppCalendar.current.date(bySettingHour: store.settings.autoBriefingHour, minute: store.settings.autoBriefingMinute, second: 0, of: Date()) ?? Date() },
                            set: {
                                let c = AppCalendar.current.dateComponents([.hour, .minute], from: $0)
                                store.settings.autoBriefingHour = c.hour ?? 9
                                store.settings.autoBriefingMinute = c.minute ?? 0
                                store.settings.lastAutoBriefingDay = nil
                            }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    }
                }
            }
        }
    }

    private func providerHint(_ p: LLMProvider) -> String {
        switch p {
        case .ollama: "로컬 · 무료 · 오프라인"
        case .openAICompatible: "LM Studio · OpenAI · 기타"
        case .anthropic: "API 키로 Claude 사용"
        case .claudeCode: "구독 로그인 그대로 사용"
        }
    }

    private func presetButton(_ name: String, _ url: String) -> some View {
        Button(name) { store.settings.llm.openAIBaseURL = url }
            .buttonStyle(.retro(.ghost, compact: true))
    }

    private func keyRow(text: Binding<String>, account: String, help: String) -> some View {
        SettingRow(label: "API 키", help: help) {
            SecureField("sk-…", text: text).retroField().frame(width: 280)
            Button(keySaved ? "저장됨 ✓" : "키체인에 저장") {
                KeychainStore.set(text.wrappedValue, for: account)
                keySaved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { keySaved = false }
            }
            .buttonStyle(.retro(.secondary, compact: true))
        }
    }

    private func modelRow(selection: Binding<String>, placeholder: String) -> some View {
        SettingRow(label: "모델") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField(placeholder, text: selection).retroField().frame(width: 240)
                    if !models.isEmpty {
                        Menu("목록에서 선택") {
                            ForEach(models, id: \.self) { m in Button(m) { selection.wrappedValue = m } }
                        }
                        .frame(width: 130)
                    }
                    Button {
                        loadModels()
                    } label: {
                        if loadingModels { ProgressView().controlSize(.small) } else { Label("모델 불러오기", systemImage: "arrow.clockwise") }
                    }
                    .buttonStyle(.retro(.secondary, compact: true))
                }
                if let modelError { Text(modelError).font(theme.font(10.5)).foregroundStyle(.red).lineLimit(2) }
                if models.isEmpty && modelError == nil && loadingModels == false {
                    EmptyView()
                }
            }
        }
    }

    private func loadModels() {
        loadingModels = true
        modelError = nil
        let llm = store.settings.llm
        Task {
            defer { loadingModels = false }
            do {
                switch llm.provider {
                case .ollama: models = try await ModelLister.ollamaModels(baseURL: llm.ollamaBaseURL)
                case .openAICompatible: models = try await ModelLister.openAIModels(baseURL: llm.openAIBaseURL, apiKey: openAIKey)
                default: models = []
                }
                if models.isEmpty { modelError = "설치된 모델이 없어요." }
            } catch {
                modelError = "불러오기 실패: \(error.localizedDescription)"
            }
        }
    }

    private func runTest() {
        // 입력만 하고 저장 안 한 키도 테스트에 반영
        if store.settings.llm.provider == .openAICompatible { KeychainStore.set(openAIKey, for: KeychainStore.openAIAccount) }
        if store.settings.llm.provider == .anthropic { KeychainStore.set(anthropicKey, for: KeychainStore.anthropicAccount) }
        testing = true
        testOutput = ""
        Task {
            defer { testing = false }
            do {
                let reply = try await AppEnvironment.shared.chat.oneShot("한 문장으로 짧게 인사해 줘. 너는 할일 앱의 귀여운 캐릭터야.")
                testOutput = "✅ " + reply
            } catch {
                testOutput = "❌ " + error.localizedDescription
            }
        }
    }
}

// MARK: - 캘린더

struct CalendarSettings: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var store
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "macOS 캘린더 연동", symbol: "calendar.badge.clock") {
                SettingRow(label: "캘린더 연동 사용", help: "일정을 오늘/주간/월간 화면과 브리핑에 표시") {
                    Toggle("", isOn: $store.settings.calendarEnabled).toggleStyle(.switch).labelsHidden()
                }
                SettingRow(label: "접근 권한") {
                    Text(calendar.statusLabel).font(theme.font(12)).foregroundStyle(calendar.hasReadAccess ? theme.accent2 : theme.textMuted)
                    if !calendar.hasReadAccess {
                        if calendar.status == .notDetermined {
                            Button("권한 요청") { Task { await calendar.requestAccess() } }.buttonStyle(.retro(.primary, compact: true))
                        } else {
                            Button("시스템 설정 열기") { calendar.openPrivacySettings() }.buttonStyle(.retro(.secondary, compact: true))
                        }
                    }
                }
                if calendar.hasReadAccess {
                    SettingRow(label: "할일 내보낼 캘린더") {
                        Picker("", selection: Binding(
                            get: { store.settings.exportCalendarID ?? "" },
                            set: { store.settings.exportCalendarID = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("기본 캘린더").tag("")
                            ForEach(calendar.calendars.filter(\.allowsModify)) { c in Text("\(c.title) (\(c.source))").tag(c.id) }
                        }
                        .labelsHidden().frame(width: 260)
                    }
                    SettingRow(label: "시간 지정 할일 자동 추가", help: "시각이 있는 할일을 만들면 캘린더에도 등록") {
                        Toggle("", isOn: $store.settings.autoAddTimedTodosToCalendar).toggleStyle(.switch).labelsHidden()
                    }
                }
            }

            if calendar.hasReadAccess {
                SettingsCard(title: "표시할 캘린더", symbol: "eye.fill") {
                    ForEach(calendar.calendars) { c in
                        Toggle(isOn: Binding(
                            get: { !store.settings.hiddenCalendarIDs.contains(c.id) },
                            set: { on in
                                if on { store.settings.hiddenCalendarIDs.removeAll { $0 == c.id } }
                                else { store.settings.hiddenCalendarIDs.append(c.id) }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: c.colorHex) ?? .blue).frame(width: 9, height: 9)
                                Text(c.title).font(theme.font(12.5, .semibold))
                                Text(c.source).font(theme.font(10.5)).foregroundStyle(theme.textMuted)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }
}

// MARK: - 일반

struct GeneralSettings: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var store
    @Environment(TodoStore.self) private var todos
    @State private var message: String?

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "일반", symbol: "gearshape.2.fill") {
                SettingRow(label: "주 시작 요일") {
                    RetroSegmented(options: [1, 2], selection: $store.settings.firstWeekday) { $0 == 1 ? "일요일" : "월요일" }
                        .frame(width: 180)
                }
                SettingRow(label: "떠 있는 캐릭터", help: "⌘⇧K 로도 켜고 끌 수 있어요") {
                    Toggle("", isOn: $store.settings.showFloatingCharacter).toggleStyle(.switch).labelsHidden()
                }
                SettingRow(label: "완료 축하 모션", help: "할일을 끝내면 캐릭터가 점프해요") {
                    Toggle("", isOn: $store.settings.celebrateOnComplete).toggleStyle(.switch).labelsHidden()
                }
            }
            SettingsCard(title: "데이터", symbol: "externaldrive.fill") {
                Text("모든 데이터는 이 Mac의 ~/Library/Application Support/CharTodo 에 JSON으로 저장돼요. API 키는 키체인에 저장돼요.")
                    .font(theme.font(11.5)).foregroundStyle(theme.textMuted)
                HStack(spacing: 8) {
                    Button { NSWorkspace.shared.open(Persistence.baseURL) } label: { Label("폴더 열기", systemImage: "folder") }
                        .buttonStyle(.retro(.secondary, compact: true))
                    Button { backup() } label: { Label("백업 내보내기", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.retro(.secondary, compact: true))
                    if let message { Text(message).font(theme.font(11)).foregroundStyle(theme.accent2) }
                }
            }
            SettingsCard(title: "빠른 입력 문법", symbol: "keyboard.fill") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([
                        ("!1 ~ !4", "아이젠하워 사분면 (Q1 지금 하기 … Q4 버리기)"),
                        ("@오늘 @내일 @모레 @금 @10/12", "날짜"),
                        ("~14:30  ~오후3시", "시각"),
                        ("#주간  #월간", "주간·월간 목표로"),
                        ("보고서 > 자료조사, 초안, 검토", "세부 테스크 한 번에"),
                    ], id: \.0) { row in
                        HStack(alignment: .top) {
                            Text(row.0).font(.system(size: 12, weight: .bold, design: .monospaced)).frame(width: 240, alignment: .leading)
                            Text(row.1).font(theme.font(12)).foregroundStyle(theme.textMuted)
                        }
                    }
                }
            }
        }
    }

    private func backup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CharTodo-backup-\(Date().dayKey).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        todos.writeNow()
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.copyItem(at: Persistence.url("data.json"), to: url)
            message = "백업 완료 ✓"
        } catch {
            message = error.localizedDescription
        }
    }
}
