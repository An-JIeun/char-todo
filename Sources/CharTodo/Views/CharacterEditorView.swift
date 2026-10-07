import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 캐릭터 리깅 편집기: 이미지 + 팔·다리·얼굴 위치를 드래그로 지정
struct CharacterEditorView: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var store

    @State private var previewMood: CharacterMood = .idle
    @State private var animate = true
    @State private var showHandles = true
    @State private var processing = false
    @State private var errorText: String?
    @State private var selectedLimb: LimbKind = .rightArm
    @State private var previewAction: ActionState?
    @State private var selectedPart: PuppetPart = .rightArm
    @State private var showHealedBody = false

    private let previewScale: CGFloat = 2.0

    var body: some View {
        @Bindable var store = store
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 10) {
                preview
                RetroSegmented(options: CharacterMood.allCases, selection: $previewMood) { $0.label }
                FlowLayout(spacing: 5) {
                    ForEach(CharacterAction.allCases) { a in
                        Button(a.label) {
                            previewMood = .idle
                            animate = true
                            previewAction = ActionState(a, start: Date().timeIntervalSinceReferenceDate,
                                                        duration: a == .waddle ? 2.4 : nil)
                        }
                        .buttonStyle(.retro(.secondary, compact: true))
                    }
                }
                HStack {
                    Toggle("움직임", isOn: $animate).toggleStyle(.switch).controlSize(.small)
                    Toggle("편집 핸들", isOn: $showHandles).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    Button("초기화") {
                        let image = store.settings.character.imageFile
                        var rig = CharacterRig()
                        rig.imageFile = image
                        if image != nil { rig.face.center = CGPoint(x: 0.5, y: 0.42) }
                        store.settings.character = rig
                    }
                    .buttonStyle(.retro(.secondary, compact: true))
                }
                .font(theme.font(11.5, .bold))
                Text(store.settings.character.limbMode == .cutout
                     ? "■ 관절(회전축)과 ◆ 잘라낼 영역을 드래그해 이미지의 팔·발에 맞춰 주세요. ● 는 얼굴(두 눈 사이)."
                     : "핸들을 드래그해 얼굴(●)과 팔다리 시작점(■)을 몸에 맞춰 주세요.")
                    .font(theme.font(11)).foregroundStyle(theme.textMuted)
            }
            .frame(width: 400)

            VStack(alignment: .leading, spacing: 14) {
                SettingsCard(title: "몸통", symbol: "photo.fill") {
                    HStack(spacing: 8) {
                        Button { pickImage() } label: { Label("이미지 넣기", systemImage: "photo.badge.plus") }
                            .buttonStyle(.retro(.primary, compact: true))
                        if store.settings.character.imageFile != nil {
                            Button { removeBackground() } label: {
                                if processing { ProgressView().controlSize(.small) } else { Label("배경 지우기", systemImage: "scissors") }
                            }
                            .buttonStyle(.retro(.accent2, compact: true))
                            .disabled(processing)
                            Button { store.removeCharacterImage() } label: { Label("이미지 빼기", systemImage: "trash") }
                                .buttonStyle(.retro(.secondary, compact: true))
                        }
                    }
                    if let image = store.characterImage {
                        Button {
                            var rig = store.settings.character
                            CharacterRig.applyImageDefaults(to: &rig, colors: ImageColorSampler.sample(image))
                            store.settings.character = rig
                        } label: { Label("이미지 색으로 얼굴·팔다리 맞추기", systemImage: "eyedropper.halffull") }
                        .buttonStyle(.retro(.ghost, compact: true))
                        .help("이미지에서 피부색·외곽선색을 뽑아 손그림 팔다리와 깜빡임 오버레이로 설정해요")
                    }
                    if let errorText { Text(errorText).font(theme.font(11)).foregroundStyle(.red) }
                    if store.settings.character.imageFile == nil {
                        SettingRow(label: "기본 스킨") {
                            Picker("", selection: Binding(
                                get: { store.settings.character.skin },
                                set: { skin in
                                    store.settings.character.skin = skin
                                    store.settings.character.face.center = skin.defaultFaceCenter
                                }
                            )) {
                                ForEach(CharacterSkin.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().frame(width: 160)
                        }
                        SettingRow(label: "몸 색") {
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: store.settings.character.bodyColorHex ?? "") ?? theme.accent },
                                set: { store.settings.character.bodyColorHex = $0.hexString }
                            ), supportsOpacity: false).labelsHidden()
                            Button("테마색") { store.settings.character.bodyColorHex = nil }.buttonStyle(.retro(.ghost, compact: true))
                        }
                    }
                    slider("크기", $store.settings.character.size, 56...200, format: "%.0fpt")
                    slider("둥실거림", $store.settings.character.bobAmount, 0...0.12)
                    slider("속도", $store.settings.character.speed, 0.3...2.5)
                    SettingRow(label: "팔다리 색") {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: store.settings.character.limbColorHex) ?? .black },
                            set: { store.settings.character.limbColorHex = $0.hexString }
                        ), supportsOpacity: false).labelsHidden()
                    }
                }

                SettingsCard(title: "얼굴", symbol: "face.smiling.fill") {
                    SettingRow(label: "얼굴 움직임", help: "끄면 표정 변화 없이 몸만 움직여요") {
                        Toggle("", isOn: $store.settings.character.face.enabled).toggleStyle(.switch).labelsHidden()
                    }
                    if store.settings.character.face.enabled {
                        SettingRow(label: "입 모양", help: "고양이 입은 ω 아래로 분홍 입이 열려요") {
                            Picker("", selection: $store.settings.character.face.mouthStyle) {
                                ForEach(MouthStyle.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().frame(width: 140)
                            Toggle("송곳니", isOn: $store.settings.character.face.fangs).toggleStyle(.checkbox)
                            Toggle("볼터치", isOn: $store.settings.character.face.blush).toggleStyle(.checkbox)
                        }
                        SettingRow(label: "얼굴 방식", help: "이미지에 얼굴이 있으면 '이미지 얼굴'을 고르세요") {
                            RetroSegmented(options: FaceStyle.allCases, selection: $store.settings.character.face.style) { $0.label }
                                .frame(width: 300)
                        }
                        if store.settings.character.face.style == .overlay {
                            SettingRow(label: "피부색", help: "깜빡일 때 눈·입을 가리는 색 (스포이트로 이미지에서 찍어도 돼요)") {
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: store.settings.character.face.skinHex) ?? .white },
                                    set: { store.settings.character.face.skinHex = $0.hexString }
                                ), supportsOpacity: false).labelsHidden()
                                Text("선 색").font(theme.font(11.5, .bold)).foregroundStyle(theme.textMuted)
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: store.settings.character.face.colorHex) ?? .black },
                                    set: { store.settings.character.face.colorHex = $0.hexString }
                                ), supportsOpacity: false).labelsHidden()
                            }
                            slider("눈 간격", $store.settings.character.face.eyeSpacing, 0.08...0.6)
                            slider("눈 크기", $store.settings.character.face.eyeSize, 0.03...0.16)
                            slider("입 위치", $store.settings.character.face.mouthOffset, 0.02...0.3)
                            slider("입 크기", $store.settings.character.face.mouthWidth, 0.04...0.3)
                            Text("● 얼굴 핸들을 두 눈 사이에 맞추고, 눈 간격·입 위치를 원래 그림에 맞춰 주세요. '말하는 중'·'졸림' 미리보기로 확인할 수 있어요.")
                                .font(theme.font(10.5)).foregroundStyle(theme.textMuted)
                        }
                    }
                    if store.settings.character.face.enabled && store.settings.character.face.style == .draw {
                        SettingRow(label: "눈 모양") {
                            Picker("", selection: $store.settings.character.face.eyeStyle) {
                                ForEach(EyeStyle.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden().frame(width: 140)
                            Toggle("볼터치", isOn: $store.settings.character.face.blush).toggleStyle(.checkbox)
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: store.settings.character.face.colorHex) ?? .black },
                                set: { store.settings.character.face.colorHex = $0.hexString }
                            ), supportsOpacity: false).labelsHidden()
                        }
                        slider("눈 간격", $store.settings.character.face.eyeSpacing, 0.08...0.6)
                        slider("눈 크기", $store.settings.character.face.eyeSize, 0.03...0.16)
                        slider("입 위치", $store.settings.character.face.mouthOffset, 0.04...0.3)
                        slider("입 크기", $store.settings.character.face.mouthWidth, 0.05...0.3)
                    }
                }

                SettingsCard(title: "팔 · 다리", symbol: "figure.wave") {
                    if store.characterImage != nil {
                        SettingRow(label: "팔다리 방식", help: "이미지에 팔·발이 그려져 있으면 '이미지 팔다리 움직이기'가 가장 자연스러워요") {
                            RetroSegmented(options: LimbMode.allCases, selection: Binding(
                                get: { store.settings.character.limbMode },
                                set: { mode in
                                    if mode == .cutout { ensureSpriteRects() }
                                    store.settings.character.limbMode = mode
                                }
                            )) { $0.label }
                            .frame(width: 300)
                        }
                    }
                    let cutout = store.settings.character.limbMode == .cutout && store.characterImage != nil
                    if !cutout {
                    SettingRow(label: "손그림 스타일", help: "채움색 + 외곽선으로 그려요") {
                        Toggle("", isOn: Binding(
                            get: { store.settings.character.limbFillHex != nil },
                            set: { store.settings.character.limbFillHex = $0 ? store.settings.character.face.skinHex : nil }
                        )).toggleStyle(.switch).labelsHidden()
                        if store.settings.character.limbFillHex != nil {
                            Text("채움").font(theme.font(11.5, .bold)).foregroundStyle(theme.textMuted)
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: store.settings.character.limbFillHex ?? "") ?? .white },
                                set: { store.settings.character.limbFillHex = $0.hexString }
                            ), supportsOpacity: false).labelsHidden()
                        }
                    }
                    SettingRow(label: "손 / 발 모양") {
                        Picker("", selection: $store.settings.character.handStyle) {
                            ForEach(HandStyle.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().frame(width: 150)
                        Picker("", selection: $store.settings.character.footStyle) {
                            ForEach(FootStyle.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().frame(width: 150)
                    }
                    SettingRow(label: "몸 앞에 그리기", help: "이미지에 원래 팔다리가 있으면 켜서 덮어요") {
                        Toggle("", isOn: $store.settings.character.limbsInFront).toggleStyle(.switch).labelsHidden()
                    }
                    }
                    if cutout {
                        Text("미리보기에서 ◆ 를 팔·발 위에 올려 두면 배경 제거처럼 그 모양만 잘라내고(색으로 표시), 빈자리는 몸 윤곽선을 이어 그려 메워요. ■ 는 관절(회전축)이에요.")
                            .font(theme.font(10.5)).foregroundStyle(theme.textMuted)
                        HStack(spacing: 8) {
                            Button { autoPivots() } label: { Label("관절 자동 맞춤", systemImage: "scope") }
                                .buttonStyle(.retro(.accent2, compact: true))
                                .disabled(store.puppet == nil)
                                .help("팔다리와 몸이 맞닿은 곳으로 관절을 옮겨요")
                            if let puppet = store.puppet {
                                let missing = LimbKind.allCases.filter { store.settings.character.limb($0).enabled && puppet.parts[$0.rawValue] == nil }
                                if !missing.isEmpty {
                                    Text("못 찾음: " + missing.map(\.label).joined(separator: ", ") + " — ◆ 를 팔·발 한가운데로 옮겨 보세요")
                                        .font(theme.font(10.5)).foregroundStyle(.red)
                                }
                            }
                        }
                        RetroSegmented(options: PuppetPart.allCases, selection: $selectedPart) { $0.label }
                        SettingRow(label: "\(selectedPart.label) 사용", help: selectedPart == .head ? "머리를 따로 기울이고 끄덕여요. 표정도 같이 움직여요" : nil) {
                            Toggle("", isOn: Binding(
                                get: { store.settings.character.partEnabled(selectedPart) },
                                set: { on in
                                    store.settings.character.setPartEnabled(selectedPart, on)
                                    if on, store.settings.character.partRect(selectedPart) == nil { ensureSpriteRects() }
                                }
                            )).toggleStyle(.switch).labelsHidden()
                            if let limb = selectedPart.limb {
                                Button("좌우 대칭 복사") { selectedLimb = limb; mirror() }.buttonStyle(.retro(.ghost, compact: true))
                            }
                        }
                        if let limb = selectedPart.limb {
                            slider("흔들림", Binding(
                                get: { store.settings.character.limb(limb).swing },
                                set: { v in var l = store.settings.character.limb(limb); l.swing = v; store.settings.character.setLimb(limb, l) }
                            ), 0...40, format: "%.0f°")
                        }
                        HStack(spacing: 8) {
                            Toggle("다듬은 몸통만 보기", isOn: $showHealedBody).toggleStyle(.switch).controlSize(.small)
                            if store.isBuildingPuppet { ProgressView().controlSize(.small); Text("다듬는 중…").font(theme.font(11)) }
                            else if store.puppet != nil { Text("✓ 다듬기 완료").font(theme.font(11)).foregroundStyle(theme.accent2) }
                        }
                        .font(theme.font(11.5, .bold))
                    } else {
                    RetroSegmented(options: LimbKind.allCases, selection: $selectedLimb) { $0.label }
                    let binding = Binding(
                        get: { store.settings.character.limb(selectedLimb) },
                        set: { store.settings.character.setLimb(selectedLimb, $0) }
                    )
                    SettingRow(label: "사용") {
                        Toggle("", isOn: binding.enabled).toggleStyle(.switch).labelsHidden()
                        Button("좌우 대칭 복사") { mirror() }.buttonStyle(.retro(.ghost, compact: true))
                    }
                    slider("길이", binding.length, 0.08...0.7)
                    slider("두께", binding.thickness, 0.02...0.12)
                    slider("기본 각도", binding.restAngle, -180...180, format: "%.0f°")
                    slider("흔들림", binding.swing, 0...40, format: "%.0f°")
                    }
                }

                SettingsCard(title: "움직임", symbol: "figure.run") {
                    slider("활발함", $store.settings.character.liveliness, 0...1)
                    slider("점프 높이", $store.settings.character.jumpHeight, 0.05...0.6)
                    slider("말랑함", $store.settings.character.squash, 0...1)
                    SettingRow(label: "돌아다니기", help: "가끔 원래 자리 근처를 종종걸음으로 걸어요") {
                        Toggle("", isOn: $store.settings.character.wanders).toggleStyle(.switch).labelsHidden()
                    }
                    Text("혼자 있을 때 깡총·두리번·손 흔들기·기지개 같은 행동을 해요. 마우스를 올리면 반응하고, 할일을 끝내면 신나서 뛰어요.")
                        .font(theme.font(10.5)).foregroundStyle(theme.textMuted)
                }
            }
        }
    }

    // MARK: 미리보기 + 핸들

    private var preview: some View {
        let rig = store.settings.character
        let layout = CharacterLayout(rig: rig, aspect: store.characterAspect, scale: previewScale)
        return ZStack(alignment: .topLeading) {
            if showHealedBody, let puppet = store.puppet {
                Image(nsImage: puppet.body)
                    .resizable()
                    .frame(width: layout.bodySize.width, height: layout.bodySize.height)
                    .offset(x: layout.bodyOrigin.x, y: layout.bodyOrigin.y)
            } else {
                CharacterView(rig: rig, image: store.characterImage, aspect: store.characterAspect, mood: previewMood,
                              bodyColor: Color(hex: rig.bodyColorHex ?? "") ?? theme.accent, scale: previewScale, animated: animate,
                              action: previewAction, puppet: store.puppet, eyeRects: store.eyeRects)
            }
            if showHandles {
                Rectangle()
                    .strokeBorder(theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: layout.bodySize.width, height: layout.bodySize.height)
                    .offset(x: layout.bodyOrigin.x, y: layout.bodyOrigin.y)
                    .allowsHitTesting(false)
                if rig.limbMode == .cutout && store.characterImage != nil {
                    // 자동으로 잡힌 팔다리 모양을 색으로 표시
                    if let puppet = store.puppet, puppet.key == rig.puppetKey {
                        ForEach(LimbKind.allCases) { kind in
                            if let img = puppet.parts[kind.rawValue] {
                                Image(nsImage: img)
                                    .resizable()
                                    .renderingMode(.template)
                                    .foregroundStyle(partColor(PuppetPart(rawValue: kind.rawValue)!).opacity(0.55))
                                    .frame(width: layout.bodySize.width, height: layout.bodySize.height)
                                    .offset(x: layout.bodyOrigin.x, y: layout.bodyOrigin.y)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    ForEach(LimbKind.allCases) { kind in
                        if let g = rig.grabPoint(kind) {
                            let part = PuppetPart(rawValue: kind.rawValue)!
                            diamondHandle(rect: CGRect(x: g.x, y: g.y, width: 0, height: 0), layout: layout, color: partColor(part)) { p in
                                var limb = store.settings.character.limb(kind)
                                limb.grabPoint = p
                                store.settings.character.setLimb(kind, limb)
                                selectedPart = part
                            }
                            handle(at: rig.limb(kind).anchor, layout: layout, color: partColor(part), label: "\(part.label) 관절", circle: false) { p in
                                store.settings.character.setPartPivot(part, p)
                                selectedPart = part
                            }
                        }
                    }
                    ForEach([PuppetPart.head]) { part in
                        if let r = rig.partRect(part) {
                            let color = partColor(part)
                            Rectangle()
                                .strokeBorder(color, style: StrokeStyle(lineWidth: part == selectedPart ? 2.2 : 1.3, dash: [3, 2]))
                                .frame(width: r.width * layout.bodySize.width, height: r.height * layout.bodySize.height)
                                .offset(x: layout.bodyOrigin.x + r.minX * layout.bodySize.width,
                                        y: layout.bodyOrigin.y + r.minY * layout.bodySize.height)
                                .allowsHitTesting(false)
                            diamondHandle(rect: r, layout: layout, color: color) { center in
                                var rr = r
                                rr.origin = CGPoint(x: center.x - r.width / 2, y: center.y - r.height / 2)
                                store.settings.character.setPartRect(part, rr)
                                selectedPart = part
                            }
                            cornerHandle(rect: r, layout: layout, color: color) { corner in
                                let rr = CGRect(x: r.minX, y: r.minY,
                                                width: max(0.03, corner.x - r.minX), height: max(0.03, corner.y - r.minY))
                                store.settings.character.setPartRect(part, rr)
                                selectedPart = part
                            }
                            handle(at: rig.partPivot(part), layout: layout, color: color, label: "\(part.label) 관절", circle: false) { p in
                                store.settings.character.setPartPivot(part, p)
                                selectedPart = part
                            }
                        }
                    }
                } else {
                ForEach(LimbKind.allCases) { kind in
                    handle(at: rig.limb(kind).anchor, layout: layout, color: kind.isArm ? theme.accent : theme.accent2,
                           label: kind.label, circle: false) { p in
                        var limb = store.settings.character.limb(kind)
                        limb.anchor = p
                        store.settings.character.setLimb(kind, limb)
                        selectedLimb = kind
                    }
                }
                }
                if rig.face.enabled {
                    handle(at: rig.face.center, layout: layout, color: theme.highlight, label: "얼굴", circle: true) { p in
                        store.settings.character.face.center = p
                    }
                }
            }
        }
        .coordinateSpace(name: "rigCanvas")
        .frame(width: max(layout.canvasSize.width, 380), height: max(layout.canvasSize.height, 300), alignment: .center)
        .frame(width: 400, height: 380)
        .clipped()
        .background(PatternBackground())
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        .retroCard()
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            loadDropped(providers)
            return true
        }
    }

    private func handle(at unit: CGPoint, layout: CharacterLayout, color: Color, label: String, circle: Bool,
                        onMove: @escaping (CGPoint) -> Void) -> some View {
        let x = layout.bodyOrigin.x + unit.x * layout.bodySize.width
        let y = layout.bodyOrigin.y + unit.y * layout.bodySize.height
        return Group {
            if circle {
                Circle().fill(color).overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
            } else {
                Rectangle().fill(color).overlay(Rectangle().strokeBorder(.black, lineWidth: 1.5))
            }
        }
        .frame(width: 13, height: 13)
        .help(label)
        .position(x: x, y: y)
        .gesture(
            DragGesture(coordinateSpace: .named("rigCanvas"))
                .onChanged { v in
                    let ux = (v.location.x - layout.bodyOrigin.x) / layout.bodySize.width
                    let uy = (v.location.y - layout.bodyOrigin.y) / layout.bodySize.height
                    onMove(CGPoint(x: min(1.4, max(-0.4, ux)), y: min(1.4, max(-0.4, uy))))
                }
        )
    }

    private func diamondHandle(rect r: CGRect, layout: CharacterLayout, color: Color,
                               onMove: @escaping (CGPoint) -> Void) -> some View {
        let x = layout.bodyOrigin.x + r.midX * layout.bodySize.width
        let y = layout.bodyOrigin.y + r.midY * layout.bodySize.height
        return Rectangle().fill(color.opacity(0.85))
            .overlay(Rectangle().strokeBorder(.black, lineWidth: 1.2))
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(45))
            .help("팔·발 위에 올려 두면 그 모양을 자동으로 잘라내요")
            .position(x: x, y: y)
            .gesture(
                DragGesture(coordinateSpace: .named("rigCanvas"))
                    .onChanged { v in
                        onMove(CGPoint(x: (v.location.x - layout.bodyOrigin.x) / layout.bodySize.width,
                                       y: (v.location.y - layout.bodyOrigin.y) / layout.bodySize.height))
                    }
            )
    }

    private func partColor(_ part: PuppetPart) -> Color {
        switch part {
        case .head: theme.highlight
        case .leftArm, .rightArm: theme.accent
        case .leftLeg, .rightLeg: theme.accent2
        }
    }

    /// 상자 오른쪽 아래 모서리: 크기 조절
    private func cornerHandle(rect r: CGRect, layout: CharacterLayout, color: Color,
                              onMove: @escaping (CGPoint) -> Void) -> some View {
        Circle().fill(color)
            .overlay(Circle().strokeBorder(.black, lineWidth: 1.2))
            .frame(width: 9, height: 9)
            .help("영역 크기 조절")
            .position(x: layout.bodyOrigin.x + r.maxX * layout.bodySize.width,
                      y: layout.bodyOrigin.y + r.maxY * layout.bodySize.height)
            .gesture(
                DragGesture(coordinateSpace: .named("rigCanvas"))
                    .onChanged { v in
                        onMove(CGPoint(x: (v.location.x - layout.bodyOrigin.x) / layout.bodySize.width,
                                       y: (v.location.y - layout.bodyOrigin.y) / layout.bodySize.height))
                    }
            )
    }

    /// 다듬기 결과의 '맞닿은 곳' 중심으로 관절을 옮긴다
    private func autoPivots() {
        guard let puppet = store.puppet else { return }
        var rig = store.settings.character
        for kind in LimbKind.allCases {
            if let p = puppet.suggestedPivots[kind.rawValue] {
                var l = rig.limb(kind)
                l.anchor = p
                rig.setLimb(kind, l)
            }
        }
        store.settings.character = rig
    }

    /// 컷아웃으로 바꿀 때 영역이 없으면 관절 주변으로 기본 영역을 만든다
    private func ensureSpriteRects() {
        var rig = store.settings.character
        for kind in LimbKind.allCases {
            var limb = rig.limb(kind)
            if limb.grabPoint == nil {
                let a = limb.anchor
                limb.grabPoint = kind.isArm ? CGPoint(x: a.x + (kind.isLeft ? -0.05 : 0.05), y: a.y)
                                            : CGPoint(x: a.x, y: min(0.99, a.y + 0.03))
                rig.setLimb(kind, limb)
            }
            guard limb.spriteRect == nil else { continue }
            let a = limb.anchor
            if kind.isArm {
                let w = 0.12, h = 0.1
                let x = kind.isLeft ? a.x - w : a.x
                limb.spriteRect = CGRect(x: x, y: a.y - h / 2, width: w, height: h)
            } else {
                limb.spriteRect = CGRect(x: a.x - 0.05, y: a.y, width: 0.1, height: 0.08)
            }
            rig.setLimb(kind, limb)
        }
        if rig.head.enabled == false && rig.head.rect == HeadPart().rect {
            // 팔 위쪽까지를 머리로 제안 (켜기는 사용자가)
            let armTop = min(rig.leftArm.anchor.y, rig.rightArm.anchor.y)
            rig.head.rect = CGRect(x: 0, y: 0, width: 1, height: max(0.3, armTop - 0.04))
            rig.head.pivot = CGPoint(x: 0.5, y: max(0.3, armTop - 0.04))
        }
        store.settings.character = rig
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, format: String = "%.2f") -> some View {
        SettingRow(label: label) {
            Slider(value: value, in: range).frame(width: 200)
            Text(String(format: format, value.wrappedValue)).font(theme.font(11, .bold)).foregroundStyle(theme.textMuted).frame(width: 52, alignment: .leading)
        }
    }

    private func mirror() {
        let src = store.settings.character.limb(selectedLimb)
        let target: LimbKind = switch selectedLimb {
        case .leftArm: .rightArm
        case .rightArm: .leftArm
        case .leftLeg: .rightLeg
        case .rightLeg: .leftLeg
        }
        var m = src
        m.anchor = CGPoint(x: 1 - src.anchor.x, y: src.anchor.y)
        m.restAngle = -src.restAngle
        if let r = src.spriteRect { m.spriteRect = CGRect(x: 1 - r.maxX, y: r.minY, width: r.width, height: r.height) }
        store.settings.character.setLimb(target, m)
    }

    // MARK: 이미지

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        store.setCharacterImage(BackgroundRemover.downscaled(image))
    }

    private func loadDropped(_ providers: [NSItemProvider]) {
        guard let p = providers.first else { return }
        if p.canLoadObject(ofClass: NSImage.self) {
            _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let img = obj as? NSImage else { return }
                DispatchQueue.main.async { store.setCharacterImage(BackgroundRemover.downscaled(img)) }
            }
        }
    }

    private func removeBackground() {
        guard let image = store.characterImage else { return }
        processing = true
        errorText = nil
        Task {
            defer { processing = false }
            do {
                let cut = try await BackgroundRemover.removeBackground(from: image)
                store.setCharacterImage(cut, applyImageDefaults: false)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
