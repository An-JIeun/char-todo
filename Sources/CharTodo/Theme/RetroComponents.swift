import SwiftUI

// MARK: - 카드 / 패널

struct RetroCardModifier: ViewModifier {
    @Environment(\.theme) private var theme
    var fill: Color?
    var shadow: Bool = true
    var radius: CGFloat?

    func body(content: Content) -> some View {
        let r = radius ?? theme.cornerRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        content
            .background(shape.fill(fill ?? theme.surface))
            .overlay(shape.strokeBorder(theme.border, lineWidth: theme.borderWidth))
            .background(
                shape.fill(theme.shadow)
                    .offset(x: shadow ? theme.shadowOffset : 0, y: shadow ? theme.shadowOffset : 0)
                    .opacity(shadow ? 1 : 0)
            )
    }
}

extension View {
    func retroCard(fill: Color? = nil, shadow: Bool = true, radius: CGFloat? = nil) -> some View {
        modifier(RetroCardModifier(fill: fill, shadow: shadow, radius: radius))
    }
}

/// 타이틀바가 달린 레트로 창 모양 패널
struct RetroWindow<Content: View, Accessory: View>: View {
    @Environment(\.theme) private var theme
    var title: String
    var symbol: String?
    var tint: Color?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(_ title: String, symbol: String? = nil, tint: Color? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: title, symbol: symbol, tint: tint ?? theme.titleBar) { accessory() }
            Rectangle().fill(theme.border).frame(height: theme.borderWidth)
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .retroCard()
    }
}

struct RetroTitleBar<Accessory: View>: View {
    @Environment(\.theme) private var theme
    var title: String
    var symbol: String?
    var tint: Color
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            // 장식용 창 버튼
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Group {
                        if theme.titleStyle == .solid {
                            Rectangle().fill(theme.surface)
                                .overlay(Rectangle().strokeBorder(theme.border, lineWidth: 1))
                                .frame(width: 10, height: 10)
                        } else {
                            Circle().fill(i == 0 ? theme.highlight : theme.titleBarText.opacity(0.85))
                                .overlay(Circle().strokeBorder(theme.border.opacity(0.8), lineWidth: 1))
                                .frame(width: 9, height: 9)
                        }
                    }
                }
            }
            if theme.titleStyle == .stripes { stripes.frame(maxWidth: 40) }
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            }
            Text(title)
                .font(theme.font(12, .bold))
                .lineLimit(1)
            if theme.titleStyle == .stripes { stripes } else { Spacer(minLength: 4) }
            accessory()
        }
        .foregroundStyle(theme.titleBarText)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(tint)
    }

    private var stripes: some View {
        VStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { _ in
                Rectangle().fill(theme.titleBarText.opacity(0.55)).frame(height: 1)
            }
        }
        .frame(height: 12)
    }
}

// MARK: - 버튼

struct RetroButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, accent2, ghost, danger }
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var kind: Kind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 2), style: .continuous)
        let (fill, fg): (Color, Color) = {
            switch kind {
            case .primary: (theme.accent, theme.isDark ? theme.background : .white)
            case .accent2: (theme.accent2, theme.isDark ? theme.background : .white)
            case .secondary: (theme.surface, theme.text)
            case .ghost: (Color.clear, theme.text)
            case .danger: (Color(hex: "#E5484D")!, .white)
            }
        }()
        let offset = kind == .ghost ? 0 : (pressed ? 0 : min(3, theme.shadowOffset))
        configuration.label
            .font(theme.font(compact ? 11 : 12.5, .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 7)
            .background(shape.fill(fill))
            .overlay(kind == .ghost ? nil : shape.strokeBorder(theme.border, lineWidth: theme.borderWidth))
            .background(shape.fill(theme.shadow).offset(x: offset, y: offset).opacity(kind == .ghost ? 0 : 1))
            .offset(x: pressed && kind != .ghost ? min(3, theme.shadowOffset) : 0,
                    y: pressed && kind != .ghost ? min(3, theme.shadowOffset) : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.06), value: pressed)
    }
}

extension ButtonStyle where Self == RetroButtonStyle {
    static var retro: RetroButtonStyle { RetroButtonStyle() }
    static var retroPrimary: RetroButtonStyle { RetroButtonStyle(kind: .primary) }
    static var retroGhost: RetroButtonStyle { RetroButtonStyle(kind: .ghost) }
    static func retro(_ kind: RetroButtonStyle.Kind, compact: Bool = false) -> RetroButtonStyle {
        RetroButtonStyle(kind: kind, compact: compact)
    }
}

/// 테두리 없는 아이콘 버튼
struct IconButton: View {
    @Environment(\.theme) private var theme
    var symbol: String
    var help: String
    var size: CGFloat = 12
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .frame(width: size + 12, height: size + 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textMuted)
        .help(help)
    }
}

// MARK: - 체크박스

struct RetroCheckbox: View {
    @Environment(\.theme) private var theme
    var isOn: Bool
    var tint: Color?
    var size: CGFloat = 18
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: min(4, theme.cornerRadius / 2))
                    .fill(isOn ? (tint ?? theme.accent) : theme.surface)
                RoundedRectangle(cornerRadius: min(4, theme.cornerRadius / 2))
                    .strokeBorder(theme.border, lineWidth: theme.borderWidth)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.55, weight: .black))
                        .foregroundStyle(theme.onAccent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isOn)
    }
}

// MARK: - 입력 필드

struct RetroFieldModifier: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(theme.font(13))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3)).fill(theme.isDark ? theme.background : Color.white.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3)).strokeBorder(theme.border, lineWidth: theme.borderWidth * 0.75))
    }
}

extension View {
    func retroField() -> some View { modifier(RetroFieldModifier()) }
}

/// 여러 줄 입력 (TextEditor) 레트로 스타일
struct RetroTextEditor: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 80

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(theme.font(13))
                .foregroundStyle(theme.text)
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.isEmpty {
                Text(placeholder)
                    .font(theme.font(13))
                    .foregroundStyle(theme.textMuted.opacity(0.8))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .background(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3)).fill(theme.isDark ? theme.background : Color.white.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3)).strokeBorder(theme.border, lineWidth: theme.borderWidth * 0.75))
    }
}

// MARK: - 진행 바 (블록 세그먼트)

struct SegmentedProgress: View {
    @Environment(\.theme) private var theme
    var value: Double
    var segments: Int = 10
    var tint: Color?
    var height: CGFloat = 10

    var body: some View {
        let filled = Int((value * Double(segments)).rounded(.down))
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                Rectangle()
                    .fill(i < filled ? (tint ?? theme.accent) : theme.surfaceAlt)
            }
        }
        .padding(2)
        .frame(height: height)
        .overlay(Rectangle().strokeBorder(theme.border, lineWidth: 1.5))
        .animation(.easeOut(duration: 0.2), value: filled)
    }
}

// MARK: - 칩 / 배지

struct Chip: View {
    @Environment(\.theme) private var theme
    var text: String
    var symbol: String?
    var color: Color?
    var filled = false

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text).font(theme.font(10.5, .bold)).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(filled ? theme.onAccent : (color ?? theme.text))
        .background(Capsule().fill(filled ? (color ?? theme.accent) : (color ?? theme.text).opacity(0.12)))
        .overlay(Capsule().strokeBorder((color ?? theme.border).opacity(filled ? 0 : 0.6), lineWidth: 1))
    }
}

/// 레트로 탭 형태의 선택기
struct RetroSegmented<T: Hashable>: View {
    @Environment(\.theme) private var theme
    var options: [T]
    @Binding var selection: T
    var label: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                let selected = opt == selection
                Button { selection = opt } label: {
                    Text(label(opt))
                        .font(theme.font(11.5, .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(selected ? theme.onAccent : theme.text)
                        .background(selected ? theme.accent : theme.surface)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < options.count - 1 {
                    Rectangle().fill(theme.border).frame(width: theme.borderWidth * 0.75)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3)))
        .overlay(RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 3)).strokeBorder(theme.border, lineWidth: theme.borderWidth))
    }
}

// MARK: - 배경 패턴

struct PatternBackground: View {
    @Environment(\.theme) private var theme
    var enabled = true

    var body: some View {
        ZStack {
            theme.background
            if enabled {
                Canvas { ctx, size in
                    let ink = theme.isDark ? theme.border.opacity(0.07) : theme.border.opacity(0.07)
                    switch theme.pattern {
                    case .none: break
                    case .dots:
                        let step: CGFloat = 18
                        var y: CGFloat = 4
                        var row = 0
                        while y < size.height {
                            var x: CGFloat = row.isMultiple(of: 2) ? 4 : 4 + step / 2
                            while x < size.width {
                                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.4, height: 2.4)), with: .color(ink))
                                x += step
                            }
                            y += step / 1.6
                            row += 1
                        }
                    case .grid:
                        let step: CGFloat = 16
                        var p = Path()
                        stride(from: 0, through: size.width, by: step).forEach { x in
                            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        stride(from: 0, through: size.height, by: step).forEach { y in
                            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        ctx.stroke(p, with: .color(ink), lineWidth: 1)
                    case .scanlines:
                        var y: CGFloat = 0
                        while y < size.height {
                            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(theme.border.opacity(0.05)))
                            y += 3
                        }
                    case .checker:
                        let step: CGFloat = 4
                        var y: CGFloat = 0
                        var row = 0
                        while y < size.height {
                            var x: CGFloat = row.isMultiple(of: 2) ? 0 : step
                            while x < size.width {
                                ctx.fill(Path(CGRect(x: x, y: y, width: step, height: step)), with: .color(Color.black.opacity(0.05)))
                                x += step * 2
                            }
                            y += step
                            row += 1
                        }
                    case .stripes:
                        var p = Path()
                        var x: CGFloat = -size.height
                        while x < size.width {
                            p.move(to: CGPoint(x: x, y: size.height))
                            p.addLine(to: CGPoint(x: x + size.height, y: 0))
                            x += 22
                        }
                        ctx.stroke(p, with: .color(ink), lineWidth: 5)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 섹션 헤더

struct SectionHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme
    var title: String
    var symbol: String?
    var count: Int?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, symbol: String? = nil, count: Int? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.symbol = symbol
        self.count = count
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(theme.accent)
            }
            Text(title).font(theme.font(13, .heavy)).foregroundStyle(theme.text)
            if let count {
                Text("\(count)")
                    .font(theme.font(10.5, .bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(theme.highlight))
                    .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
                    .foregroundStyle(Color.black.opacity(0.8))
            }
            Spacer(minLength: 4)
            trailing()
        }
    }
}

/// 비어 있을 때 보여줄 안내
struct EmptyHint: View {
    @Environment(\.theme) private var theme
    var text: String
    var symbol = "sparkles"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(theme.font(12))
        .foregroundStyle(theme.textMuted)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }
}
