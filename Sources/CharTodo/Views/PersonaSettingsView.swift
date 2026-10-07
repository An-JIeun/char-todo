import SwiftUI

/// 말투 · 말버릇 · 상황별 표현 설정
struct PersonaSettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var store
    @Environment(CompanionState.self) private var companion
    @Environment(FloatingController.self) private var floating

    @State private var previewQuestion = "오늘 할일 짧게 브리핑해 줘"
    @State private var previewAnswer = ""
    @State private var previewing = false

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "빠른 시작 프리셋", symbol: "wand.and.stars") {
                Text("프리셋을 고른 뒤 아래에서 자유롭게 고쳐 쓰세요. (지금 설정을 덮어써요)")
                    .font(theme.font(11.5)).foregroundStyle(theme.textMuted)
                HStack(spacing: 8) {
                    ForEach(PersonaConfig.presets, id: \.name) { preset in
                        Button(preset.name) { store.settings.persona = preset.config }
                            .buttonStyle(.retro(.secondary, compact: true))
                    }
                    Button("초기화") { store.settings.persona = PersonaConfig() }
                        .buttonStyle(.retro(.ghost, compact: true))
                }
            }

            SettingsCard(title: "기본 성격", symbol: "person.crop.circle.fill") {
                SettingRow(label: "이름", help: "말풍선의 {이름} 자리에 들어가요") {
                    TextField("플로피", text: $store.settings.assistantName).retroField().frame(width: 180)
                }
                SettingRow(label: "기본 말투") {
                    Picker("", selection: $store.settings.assistantTone) {
                        ForEach(AssistantTone.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                }
                SettingRow(label: "캐릭터 설정 · 말투 설명", help: "성격, 배경, 말하는 방식을 자유롭게") {
                    RetroTextEditor(text: $store.settings.persona.styleDescription,
                                    placeholder: "예) 느긋하고 졸린 아기 사자. 문장이 짧고 포근하다. 칭찬을 아끼지 않는다.",
                                    minHeight: 64)
                        .frame(maxWidth: 460)
                }
            }

            SettingsCard(title: "말버릇 · 어미", symbol: "quote.bubble.fill") {
                SettingRow(label: "문장 끝 어미", help: "예) ~다냥, ~어흥, ~입니다") {
                    TextField("비우면 기본 말투대로", text: $store.settings.persona.sentenceEnding).retroField().frame(width: 260)
                }
                SettingRow(label: "말버릇", help: "Enter로 추가, 칩을 누르면 삭제") {
                    TagEditor(tags: $store.settings.persona.catchphrases, placeholder: "예) 하암~, 읏차!, 헤헤")
                        .frame(maxWidth: 460, alignment: .leading)
                }
                SettingRow(label: "말버릇 빈도") {
                    RetroSegmented(options: CatchphraseFrequency.allCases, selection: $store.settings.persona.catchphraseFrequency) { $0.label }
                        .frame(width: 220)
                }
                SettingRow(label: "피할 표현", help: "AI가 쓰지 않았으면 하는 말") {
                    TextField("예) 딱딱한 보고서 말투, 이모지 남발", text: $store.settings.persona.avoid).retroField().frame(width: 360)
                }
            }

            SettingsCard(title: "상황별 표현", symbol: "text.bubble.fill") {
                Text("상황마다 쓸 대사를 여러 개 넣으면 그중 하나를 골라 써요. 말풍선(완료 칭찬·인사·밀린 일 알림)에는 그대로 나오고, AI 답변에는 이 표현을 살려서 말해요. {n} = 개수, {이름} = 캐릭터 이름")
                    .font(theme.font(11.5)).foregroundStyle(theme.textMuted)
                ForEach(PersonaSituation.allCases) { situation in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: situation.symbol).foregroundStyle(theme.accent)
                            Text(situation.label).font(theme.font(12.5, .heavy))
                            Spacer()
                            Button {
                                showBubble(situation)
                            } label: { Label("말풍선 미리보기", systemImage: "eye") }
                            .buttonStyle(.retro(.ghost, compact: true))
                        }
                        TagEditor(tags: Binding(
                            get: { store.settings.persona.situationLines[situation.rawValue] ?? [] },
                            set: { store.settings.persona.situationLines[situation.rawValue] = $0 }
                        ), placeholder: situation.placeholder, multiline: true)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: max(4, theme.cornerRadius - 4)).fill(theme.surfaceAlt))
                }
            }

            SettingsCard(title: "AI 말투 테스트", symbol: "bubble.left.and.text.bubble.right.fill") {
                HStack(spacing: 8) {
                    TextField("질문", text: $previewQuestion).retroField().frame(width: 320)
                    Button {
                        runPreview()
                    } label: {
                        if previewing { ProgressView().controlSize(.small) } else { Label("물어보기", systemImage: "paperplane.fill") }
                    }
                    .buttonStyle(.retro(.primary, compact: true))
                    .disabled(previewing || previewQuestion.trimmed.isEmpty)
                }
                if !previewAnswer.isEmpty {
                    Text(MarkdownLite.render(PromptBuilder.displayText(previewAnswer)))
                        .font(theme.font(12.5))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .retroCard(shadow: false)
                }
            }
        }
    }

    private func showBubble(_ situation: PersonaSituation) {
        if !floating.isCharacterVisible { floating.showCharacter() }
        let line = AppEnvironment.shared.line(situation, count: 3)
        switch situation {
        case .taskDone, .allDone: companion.celebrate(line)
        case .thinking: companion.flash(.thinking, duration: 3); companion.say(line, duration: 3)
        case .wrapUp: companion.flash(.sleepy, duration: 3); companion.say(line, duration: 4)
        default: companion.say(line, duration: 4)
        }
    }

    private func runPreview() {
        previewing = true
        previewAnswer = ""
        Task {
            defer { previewing = false }
            do {
                previewAnswer = try await AppEnvironment.shared.chat.personaPreview(previewQuestion)
            } catch {
                previewAnswer = "❌ " + error.localizedDescription
            }
        }
    }
}

/// 칩 목록 + 입력창 (Enter로 추가, 칩 클릭으로 삭제)
struct TagEditor: View {
    @Environment(\.theme) private var theme
    @Binding var tags: [String]
    var placeholder: String
    var multiline = false
    /// 입력값 정리 규칙 (태그는 # 제거 등)
    var normalize: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// 클릭해서 바로 넣을 수 있는 추천 목록
    var suggestions: [String] = []
    var chipColor: ((String) -> Color)? = nil
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { idx, tag in
                        Button {
                            tags.remove(at: idx)
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag).font(theme.font(11.5, .semibold)).lineLimit(multiline ? 3 : 1)
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(theme.text)
                            .background(Capsule().fill((chipColor?(tag) ?? theme.accent).opacity(0.22)))
                            .overlay(Capsule().strokeBorder((chipColor?(tag) ?? theme.border).opacity(0.7), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("클릭해서 삭제")
                    }
                }
            }
            HStack(spacing: 6) {
                TextField(placeholder, text: $input)
                    .retroField()
                    .onSubmit(add)
                Button("추가", action: add)
                    .buttonStyle(.retro(.secondary, compact: true))
                    .disabled(input.trimmed.isEmpty)
            }
            let rest = suggestions.filter { s in !tags.contains(s) && (input.isEmpty || s.localizedCaseInsensitiveContains(normalize(input))) }
            if !rest.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(rest.prefix(16), id: \.self) { s in
                        Button("+ \(s)") { tags.append(s); input = "" }
                            .buttonStyle(.plain)
                            .font(theme.font(11, .semibold))
                            .foregroundStyle(chipColor?(s) ?? theme.textMuted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().strokeBorder((chipColor?(s) ?? theme.border).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    }
                }
            }
        }
    }

    private func add() {
        let t = normalize(input)
        guard !t.isEmpty, !tags.contains(t) else { input = ""; return }
        tags.append(t)
        input = ""
    }
}

/// 줄바꿈되는 가로 배치
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
