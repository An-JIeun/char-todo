import SwiftUI
import AppKit

enum BackgroundPattern: String {
    case none, dots, grid, scanlines, checker, stripes
}

/// 뉴트로 테마 정의. 색·폰트·모서리·그림자 스타일을 묶는다.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let isDark: Bool

    var background: Color
    var backgroundAlt: Color
    var surface: Color
    var surfaceAlt: Color
    var border: Color
    var text: Color
    var textMuted: Color
    var accent: Color
    var accent2: Color
    var highlight: Color
    var titleBar: Color
    var titleBarText: Color
    var shadow: Color
    var quadrantColors: [Color] // Q1~Q4

    var fontDesign: Font.Design
    var customFontName: String?
    var titleFontName: String?
    var cornerRadius: CGFloat
    var borderWidth: CGFloat
    var shadowOffset: CGFloat
    var pattern: BackgroundPattern
    /// 윈도 타이틀바 장식: stripes(클래식 맥) / gradient(윈도95) / dots
    var titleStyle: TitleStyle

    /// 강조색 위 글자색 (nil이면 밝은 테마는 흰색, 어두운 테마는 배경색)
    var onAccentOverride: Color? = nil

    enum TitleStyle: Equatable { case stripes, solid, dots }

    var onAccent: Color { onAccentOverride ?? (isDark ? background : .white) }

    func quadrantColor(_ q: Quadrant?) -> Color {
        guard let q else { return textMuted }
        return quadrantColors[q.rawValue - 1]
    }

    // MARK: 폰트

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = customFontName, !name.isEmpty {
            return .custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: fontDesign)
    }

    /// 제목용 (디스플레이) 폰트
    func titleFont(_ size: CGFloat) -> Font {
        if let name = customFontName, !name.isEmpty { return .custom(name, size: size).weight(.bold) }
        if let name = titleFontName, NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: .heavy, design: fontDesign)
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

extension Theme {
    static let all: [Theme] = [.creamLion, .cassette, .dabang, .retroPC, .crt, .gameboy, .citypop]

    static func resolve(id: String, accentHex: String?, fontChoice: FontChoice, customFont: String) -> Theme {
        var theme = all.first { $0.id == id } ?? .creamLion
        if let hex = accentHex, let c = Color(hex: hex) { theme.accent = c }
        switch fontChoice {
        case .themeDefault: break
        case .system: theme.fontDesign = .default; theme.titleFontName = nil
        case .rounded: theme.fontDesign = .rounded; theme.titleFontName = nil
        case .monospaced: theme.fontDesign = .monospaced; theme.titleFontName = nil
        case .serif: theme.fontDesign = .serif; theme.titleFontName = nil
        case .custom:
            if !customFont.isEmpty, NSFont(name: customFont, size: 12) != nil { theme.customFontName = customFont }
        }
        return theme
    }

    /// 크림 사자 — 크림 몸통 · 귤빛 갈기 · 볼터치 핑크 · 진갈색 외곽선 (캐릭터 팔레트)
    static let creamLion = Theme(
        id: "creamLion", name: "크림 사자", tagline: "크림 · 귤빛 갈기 · 볼터치 핑크, 손그림 감성", isDark: false,
        background: Color(hex: "#FFF6E2")!, backgroundAlt: Color(hex: "#FCEACB")!,
        surface: Color(hex: "#FFFCF4")!, surfaceAlt: Color(hex: "#FFF0E8")!,
        border: Color(hex: "#3A2218")!, text: Color(hex: "#3A2218")!, textMuted: Color(hex: "#9A7A66")!,
        accent: Color(hex: "#EE9A6C")!, accent2: Color(hex: "#F2A3B0")!, highlight: Color(hex: "#FFE29A")!,
        titleBar: Color(hex: "#EE9A6C")!, titleBarText: Color(hex: "#3A2218")!, shadow: Color(hex: "#3A2218")!,
        quadrantColors: [Color(hex: "#E2673F")!, Color(hex: "#E58A9C")!, Color(hex: "#EDAA45")!, Color(hex: "#B8A58F")!],
        fontDesign: .rounded, customFontName: nil, titleFontName: nil,
        cornerRadius: 14, borderWidth: 2, shadowOffset: 3, pattern: .dots, titleStyle: .dots,
        onAccentOverride: Color(hex: "#3A2218")!
    )

    /// 카세트 팝 — 크림 + 핑크/민트, 두꺼운 외곽선과 하드 섀도
    static let cassette = Theme(
        id: "cassette", name: "카세트 팝", tagline: "크림 · 핑크 · 민트, 90년대 문구점 감성", isDark: false,
        background: Color(hex: "#FFF3E0")!, backgroundAlt: Color(hex: "#FFE7C7")!,
        surface: Color(hex: "#FFFDF8")!, surfaceAlt: Color(hex: "#FFF0F5")!,
        border: Color(hex: "#2B2118")!, text: Color(hex: "#2B2118")!, textMuted: Color(hex: "#8A7563")!,
        accent: Color(hex: "#FF5C93")!, accent2: Color(hex: "#3CCFB4")!, highlight: Color(hex: "#FFD23F")!,
        titleBar: Color(hex: "#FF5C93")!, titleBarText: .white, shadow: Color(hex: "#2B2118")!,
        quadrantColors: [Color(hex: "#FF5C5C")!, Color(hex: "#4D8CFF")!, Color(hex: "#FFB020")!, Color(hex: "#9C8E80")!],
        fontDesign: .rounded, customFontName: nil, titleFontName: "Chalkboard SE",
        cornerRadius: 10, borderWidth: 2, shadowOffset: 4, pattern: .dots, titleStyle: .stripes
    )

    /// 다방 뉴트로 — 갈색·주황·크림, 70~80년대 다방/레트로 간판
    static let dabang = Theme(
        id: "dabang", name: "다방 뉴트로", tagline: "갈색 · 주황 · 크림, 을지로 다방 감성", isDark: false,
        background: Color(hex: "#F1E3C8")!, backgroundAlt: Color(hex: "#E8D3AE")!,
        surface: Color(hex: "#FFF8EA")!, surfaceAlt: Color(hex: "#F8EBD3")!,
        border: Color(hex: "#4A2C1A")!, text: Color(hex: "#3B2416")!, textMuted: Color(hex: "#8C6A4F")!,
        accent: Color(hex: "#D9581E")!, accent2: Color(hex: "#2F6B4F")!, highlight: Color(hex: "#F2B33D")!,
        titleBar: Color(hex: "#4A2C1A")!, titleBarText: Color(hex: "#FFF1D6")!, shadow: Color(hex: "#4A2C1A")!,
        quadrantColors: [Color(hex: "#C8402B")!, Color(hex: "#2F6B4F")!, Color(hex: "#E08E2B")!, Color(hex: "#9A8470")!],
        fontDesign: .serif, customFontName: nil, titleFontName: "AppleMyungjo",
        cornerRadius: 6, borderWidth: 2, shadowOffset: 3, pattern: .stripes, titleStyle: .stripes
    )

    /// 레트로 PC — 윈도95 회색 + 청록 바탕
    static let retroPC = Theme(
        id: "retroPC", name: "레트로 PC", tagline: "회색 베벨 창 · 청록 바탕화면", isDark: false,
        background: Color(hex: "#3A8C8C")!, backgroundAlt: Color(hex: "#2F7777")!,
        surface: Color(hex: "#D9D5CC")!, surfaceAlt: Color(hex: "#ECE9E2")!,
        border: Color(hex: "#111111")!, text: Color(hex: "#111111")!, textMuted: Color(hex: "#555555")!,
        accent: Color(hex: "#1B2BA0")!, accent2: Color(hex: "#0E8A5F")!, highlight: Color(hex: "#FFF59A")!,
        titleBar: Color(hex: "#1B2BA0")!, titleBarText: .white, shadow: Color(hex: "#111111")!,
        quadrantColors: [Color(hex: "#C21F1F")!, Color(hex: "#1B2BA0")!, Color(hex: "#B86E00")!, Color(hex: "#6B6B6B")!],
        fontDesign: .monospaced, customFontName: nil, titleFontName: nil,
        cornerRadius: 0, borderWidth: 2, shadowOffset: 3, pattern: .checker, titleStyle: .solid
    )

    /// CRT 터미널 — 초록 형광 다크
    static let crt = Theme(
        id: "crt", name: "CRT 터미널", tagline: "초록 형광 · 주사선, 해커 감성", isDark: true,
        background: Color(hex: "#050A06")!, backgroundAlt: Color(hex: "#08120A")!,
        surface: Color(hex: "#0B160D")!, surfaceAlt: Color(hex: "#102014")!,
        border: Color(hex: "#39FF7A")!, text: Color(hex: "#8DFFAE")!, textMuted: Color(hex: "#3E9A5C")!,
        accent: Color(hex: "#39FF7A")!, accent2: Color(hex: "#FFB000")!, highlight: Color(hex: "#FFB000")!,
        titleBar: Color(hex: "#39FF7A")!, titleBarText: Color(hex: "#041006")!, shadow: Color(hex: "#1D7A3D")!,
        quadrantColors: [Color(hex: "#FF5F56")!, Color(hex: "#39FF7A")!, Color(hex: "#FFB000")!, Color(hex: "#3E9A5C")!],
        fontDesign: .monospaced, customFontName: nil, titleFontName: nil,
        cornerRadius: 2, borderWidth: 1.5, shadowOffset: 3, pattern: .scanlines, titleStyle: .dots
    )

    /// 게임보이 — 4색 연두 팔레트
    static let gameboy = Theme(
        id: "gameboy", name: "포켓 게임기", tagline: "4색 연두 도트, 휴대용 게임기 감성", isDark: false,
        background: Color(hex: "#A8B878")!, backgroundAlt: Color(hex: "#98A868")!,
        surface: Color(hex: "#C4D09A")!, surfaceAlt: Color(hex: "#B5C285")!,
        border: Color(hex: "#1E3A1E")!, text: Color(hex: "#1E3A1E")!, textMuted: Color(hex: "#4A6A3A")!,
        accent: Color(hex: "#306230")!, accent2: Color(hex: "#7A3A6A")!, highlight: Color(hex: "#E8F0C0")!,
        titleBar: Color(hex: "#306230")!, titleBarText: Color(hex: "#E8F0C0")!, shadow: Color(hex: "#1E3A1E")!,
        quadrantColors: [Color(hex: "#8E2B3A")!, Color(hex: "#1E3A1E")!, Color(hex: "#8A6A1A")!, Color(hex: "#5A7A4A")!],
        fontDesign: .monospaced, customFontName: nil, titleFontName: nil,
        cornerRadius: 4, borderWidth: 2.5, shadowOffset: 4, pattern: .grid, titleStyle: .solid
    )

    /// 시티팝 선셋 — 남색 밤 + 네온 핑크/오렌지
    static let citypop = Theme(
        id: "citypop", name: "시티팝 선셋", tagline: "남색 밤하늘 · 네온 핑크, 80s 드라이브", isDark: true,
        background: Color(hex: "#1A1340")!, backgroundAlt: Color(hex: "#241A55")!,
        surface: Color(hex: "#2A1F5E")!, surfaceAlt: Color(hex: "#352874")!,
        border: Color(hex: "#FF6FB5")!, text: Color(hex: "#FCEBFF")!, textMuted: Color(hex: "#B7A3E0")!,
        accent: Color(hex: "#FF6FB5")!, accent2: Color(hex: "#FFB86B")!, highlight: Color(hex: "#5CE1E6")!,
        titleBar: Color(hex: "#FF6FB5")!, titleBarText: Color(hex: "#1A1340")!, shadow: Color(hex: "#0B0720")!,
        quadrantColors: [Color(hex: "#FF5E7E")!, Color(hex: "#5CE1E6")!, Color(hex: "#FFB86B")!, Color(hex: "#9C8CC8")!],
        fontDesign: .rounded, customFontName: nil, titleFontName: "Futura-Bold",
        cornerRadius: 12, borderWidth: 2, shadowOffset: 4, pattern: .stripes, titleStyle: .stripes
    )
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .creamLion
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Color(hex:)

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255; a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)), Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
    }
}


// MARK: - 태그 색

enum TagPalette {
    static let hexes = ["#EE9A6C", "#E58A9C", "#6FA8C9", "#8BB174", "#EDAA45", "#A98BC9",
                        "#5FB3A1", "#D9785B", "#C99A6B", "#7C93D6"]

    /// 실행마다 바뀌지 않는 해시로 색을 고른다.
    static func hex(for tag: String, overrides: [String: String]) -> String {
        if let o = overrides[tag] { return o }
        var h: UInt32 = 5381
        for u in tag.unicodeScalars { h = (h &* 33) &+ u.value }
        return hexes[Int(h % UInt32(hexes.count))]
    }

    static func color(for tag: String, overrides: [String: String]) -> Color {
        Color(hex: hex(for: tag, overrides: overrides)) ?? .gray
    }
}
