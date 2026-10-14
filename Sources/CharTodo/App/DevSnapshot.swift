import AppKit
import SwiftUI

/// 개발용: CHARTODO_SNAPSHOT_DIR 환경변수가 있으면 각 화면을 PNG로 저장한다.
/// (화면 녹화 권한 없이 UI를 확인하기 위한 도구)
@MainActor
enum DevSnapshot {
    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["CHARTODO_SNAPSHOT_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func runIfRequested() {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let themeOverride = ProcessInfo.processInfo.environment["CHARTODO_SNAPSHOT_THEME"]
        if let themeOverride { AppEnvironment.shared.settings.settings.themeID = themeOverride }
        // 파츠 다듬기가 끝나길 기다렸다가(최대 20초) 시트를 그린다
        func waitForPuppet(_ tries: Int) {
            let s = AppEnvironment.shared.settings
            let needs = s.settings.character.limbMode == .cutout && s.characterImage != nil
            if !needs || s.puppet != nil || tries <= 0 {
                renderCharacterSheet(to: dir)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { waitForPuppet(tries - 1) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { waitForPuppet(40) }
        let sections = AppSection.allCases
        var delay = 2.5
        for section in sections {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NotificationCenter.default.post(name: .navigateRequest, object: section.rawValue)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.2) {
                capture(mainWindow(), to: dir.appendingPathComponent("main-\(section.rawValue).png"))
            }
            delay += 2
        }
        for tab in ["persona", "character", "ai", "career"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                AppEnvironment.shared.openSettings(tab: tab)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.2) {
                capture(mainWindow(), to: dir.appendingPathComponent("settings-\(tab).png"))
            }
            delay += 2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            AppEnvironment.shared.floating.showChat()
            AppEnvironment.shared.chat.send("+ 팀 회의 @내일 ~15:00 #업무 #회의 !1 > 안건 정리, 자료 출력")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.5) {
            for (i, w) in NSApp.windows.enumerated() where w is FloatingPanel && w.isVisible {
                capture(w, to: dir.appendingPathComponent("floating-\(i).png"))
            }
            try? "done".write(to: dir.appendingPathComponent("DONE"), atomically: true, encoding: .utf8)
        }
    }

    /// 동작별로 진행 단계마다 한 프레임씩 그린 시트 + 파츠 분리 결과
    static func renderCharacterSheet(to dir: URL) {
        let settings = AppEnvironment.shared.settings
        let rig = settings.settings.character
        let image = settings.characterImage
        let aspect = settings.characterAspect
        let puppet = settings.puppet
        let color = Color(hex: rig.bodyColorHex ?? "") ?? settings.theme.accent
        let steps = [0.0, 0.1, 0.2, 0.32, 0.45, 0.6, 0.72, 0.8, 0.9]
        var rows: [(String, [(CharacterMood, ActionState?, Double)])] = []
        for a in CharacterAction.allCases {
            let st = ActionState(a, start: 0)
            rows.append((a.label, steps.map { (.idle, st, $0 * st.duration) }))
        }
        for m in [CharacterMood.idle, .talking, .happy, .thinking, .listening, .sleepy] {
            rows.append((m.label, steps.map { (m, nil, $0 * 1.7) }))
        }
        rows.append(("깜빡임", [(.idle, nil, 0.0), (.idle, nil, 4.1), (.idle, nil, 4.12)]))
        let sheet = VStack(alignment: .leading, spacing: 2) {
            Text(puppet == nil ? "파츠 없음 (원본 이미지 사용)" : "파츠: \(puppet!.parts.keys.sorted().joined(separator: ", "))")
                .font(.system(size: 12, weight: .bold))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    Text(row.0).font(.system(size: 12, weight: .bold)).frame(width: 80, alignment: .leading)
                    ForEach(Array(row.1.enumerated()), id: \.offset) { _, f in
                        CharacterFrame(rig: rig, image: image, aspect: aspect, mood: f.0, bodyColor: color,
                                       scale: 1, time: f.2, action: f.1, puppet: puppet, eyes: settings.eyes)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(hex: "#FFF6E2")!)
        save(sheet, to: dir.appendingPathComponent("character-sheet.png"))

        if let puppet {
            let size: CGFloat = 240
            let debug = HStack(alignment: .top, spacing: 8) {
                VStack { Text("다듬은 몸통").font(.caption.bold()); Image(nsImage: puppet.body).resizable().scaledToFit().frame(width: size, height: size).background(Color.gray.opacity(0.25)) }
                ForEach(puppet.parts.keys.sorted(), id: \.self) { key in
                    VStack { Text(key).font(.caption.bold()); Image(nsImage: puppet.parts[key]!).resizable().scaledToFit().frame(width: size, height: size).background(Color.gray.opacity(0.25)) }
                }
            }
            .padding(10)
            .background(Color.white)
            save(debug, to: dir.appendingPathComponent("puppet-parts.png"))
        }
    }

    private static func save<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let cg = renderer.cgImage {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    static func mainWindow() -> NSWindow? {
        NSApp.windows.first { !($0 is FloatingPanel) && $0.isVisible && $0.contentView != nil && $0.frame.width > 600 }
    }

    static func capture(_ window: NSWindow?, to url: URL) {
        guard let window, let view = window.contentView else { return }
        // 1순위: 창 서버 이미지 (권한이 있으면 가장 정확)
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
           cg.width > 10 {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        // 2순위: AppKit 캐시 렌더링 (스크롤 뷰 포함)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url.deletingPathExtension().appendingPathExtension("cache.png"))
        }
        let bounds = view.bounds
        let scale = window.backingScaleFactor
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        if let layer = view.layer, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            let cg = ctx.cgContext
            cg.translateBy(x: 0, y: bounds.height * scale)
            cg.scaleBy(x: scale, y: -scale)
            layer.render(in: cg)
        } else {
            view.cacheDisplay(in: bounds, to: rep)
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
