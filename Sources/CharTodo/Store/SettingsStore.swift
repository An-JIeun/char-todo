import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            AppCalendar.firstWeekday = settings.firstWeekday
            if settings.character.imageFile != oldValue.character.imageFile { reloadCharacterImage() }
            if settings.character.puppetKey != oldValue.character.puppetKey
                || settings.character.limbMode != oldValue.character.limbMode { schedulePuppetRebuild() }
            if settings.character.face != oldValue.character.face { refreshEyeRects() }
            persist()
            onChange?(oldValue, settings)
        }
    }

    @ObservationIgnored var onChange: ((AppSettings, AppSettings) -> Void)?

    /// 캐릭터 사용자 이미지 (캐시)
    private(set) var characterImage: NSImage? {
        didSet { schedulePuppetRebuild() }
    }
    /// 파츠 분리 결과 (머리·팔·다리 조각 + 다듬은 몸통)
    private(set) var puppet: PuppetImages?
    private(set) var isBuildingPuppet = false
    /// 이미지 얼굴의 실제 눈 영역·가림막 (깜빡일 때 눈썹은 남기고 눈만 가리기 위해)
    private(set) var eyes: FaceAnalyzer.Eyes?
    var eyeRects: [CGRect]? { eyes?.rects }
    @ObservationIgnored private var eyeKey = ""
    @ObservationIgnored private var puppetWork: DispatchWorkItem?

    @ObservationIgnored private let saver = Debouncer(delay: 0.3)
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let fileName = "settings.json"

    init(persists: Bool = true) {
        self.persists = persists
        if persists, let data = try? Data(contentsOf: Persistence.url(fileName)) {
            settings = DefaultsMerging.decode(data, defaults: AppSettings())
        } else {
            settings = AppSettings()
        }
        AppCalendar.firstWeekday = settings.firstWeekday
        reloadCharacterImage()
        schedulePuppetRebuild()
    }

    var theme: Theme {
        Theme.resolve(id: settings.themeID, accentHex: settings.accentOverrideHex,
                      fontChoice: settings.fontChoice, customFont: settings.customFontName)
    }

    /// 눈 위치 힌트(얼굴 중심·간격·크기)가 바뀌면 실제 눈 영역을 다시 찾는다
    func refreshEyeRects() {
        let face = settings.character.face
        guard face.style == .overlay, let cg = characterImage?.cgImageValue else { eyes = nil; eyeKey = ""; return }
        let key = "\(settings.character.imageFile ?? "")|\(face.center)|\(face.eyeSpacing)|\(face.eyeSize)|\(face.skinHex)"
        guard key != eyeKey else { return }
        eyeKey = key
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FaceAnalyzer.analyze(image: cg, face: face)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.eyeKey == key else { return }
                self.eyes = result
            }
        }
    }

    /// 파츠 모드일 때 설정이 바뀌면 잠시 뒤 백그라운드에서 다시 자르고 다듬는다
    func schedulePuppetRebuild() {
        refreshEyeRects()
        puppetWork?.cancel()
        let rig = settings.character
        guard rig.limbMode == .cutout, let cg = characterImage?.cgImageValue else {
            puppet = nil
            return
        }
        if puppet?.key == rig.puppetKey { return }
        let work = DispatchWorkItem { [weak self] in
            self?.isBuildingPuppet = true
            DispatchQueue.global(qos: .userInitiated).async {
                let result = PuppetBuilder.build(image: cg, rig: rig)
                DispatchQueue.main.async {
                    guard let self else { return }
                    // 그사이 설정이 또 바뀌었으면 버린다
                    if self.settings.character.puppetKey == rig.puppetKey { self.puppet = result }
                    self.isBuildingPuppet = false
                }
            }
        }
        puppetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func reloadCharacterImage() {
        guard let name = settings.character.imageFile else { characterImage = nil; return }
        characterImage = NSImage(contentsOf: Persistence.characterDir.appendingPathComponent(name))
    }

    /// 사용자 이미지를 앱 폴더로 복사(PNG)하고 리그에 연결한다.
    /// `applyImageDefaults`: 이미지 색에서 피부·외곽선 색을 뽑아 얼굴 오버레이와 손그림 팔다리로 맞춘다.
    func setCharacterImage(_ image: NSImage, applyImageDefaults: Bool = true) {
        guard let png = image.pngData() else { return }
        let name = "character-\(UUID().uuidString.prefix(8)).png"
        let url = Persistence.characterDir.appendingPathComponent(name)
        do {
            try png.write(to: url)
            if let old = settings.character.imageFile {
                try? FileManager.default.removeItem(at: Persistence.characterDir.appendingPathComponent(old))
            }
            var rig = settings.character
            rig.imageFile = name
            if rig.face.center == rig.skin.defaultFaceCenter { rig.face.center = CGPoint(x: 0.5, y: 0.42) }
            if applyImageDefaults { CharacterRig.applyImageDefaults(to: &rig, colors: ImageColorSampler.sample(image)) }
            settings.character = rig
        } catch {
            NSLog("CharTodo: failed to save character image: \(error)")
        }
    }

    func removeCharacterImage() {
        if let old = settings.character.imageFile {
            try? FileManager.default.removeItem(at: Persistence.characterDir.appendingPathComponent(old))
        }
        settings.character.imageFile = nil
        settings.character.face.center = settings.character.skin.defaultFaceCenter
    }

    /// 몸통 비율(높이/너비): 이미지가 있으면 이미지 비율
    var characterAspect: Double {
        if let img = characterImage, img.size.width > 0 {
            return min(2.0, max(0.4, img.size.height / img.size.width))
        }
        return settings.character.skin.aspect
    }

    private func persist() {
        guard persists else { return }
        saver.schedule { [weak self] in self?.writeNow() }
    }

    func writeNow() {
        guard persists else { return }
        Persistence.save(settings, to: fileName)
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    var cgImageValue: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}


/// 캐릭터 이미지에서 피부(밝은 주색)와 외곽선(어두운 색)을 뽑는다.
enum ImageColorSampler {
    struct Colors: Equatable { var skin: String?; var ink: String? }

    static func sample(_ image: NSImage) -> Colors {
        guard let cg = image.cgImageValue else { return Colors() }
        let n = 64
        var buf = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &buf, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Colors() }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var skinCounts: [Int: Int] = [:]
        var inkSum = (0, 0, 0, 0)
        for y in 0..<n {
            for x in 0..<n {
                let i = (y * n + x) * 4
                let a = Int(buf[i + 3])
                guard a > 220 else { continue }
                let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
                let lum = (r * 299 + g * 587 + b * 114) / 1000
                if lum < 90 {
                    inkSum = (inkSum.0 + r, inkSum.1 + g, inkSum.2 + b, inkSum.3 + 1)
                }
                // 가운데 영역의 밝은 색 = 피부 (버퍼 0행 = 이미지 위쪽)
                let fx = Double(x) / Double(n), fy = Double(y) / Double(n)
                if lum > 150, (0.25...0.75).contains(fx), (0.35...0.9).contains(fy) {
                    let key = (r / 8) << 10 | (g / 8) << 5 | (b / 8)
                    skinCounts[key, default: 0] += 1
                }
            }
        }
        var colors = Colors()
        if let top = skinCounts.max(by: { $0.value < $1.value })?.key {
            let r = ((top >> 10) & 31) * 8 + 4, g = ((top >> 5) & 31) * 8 + 4, b = (top & 31) * 8 + 4
            colors.skin = String(format: "#%02X%02X%02X", min(255, r), min(255, g), min(255, b))
        }
        if inkSum.3 > 0 {
            colors.ink = String(format: "#%02X%02X%02X", inkSum.0 / inkSum.3, inkSum.1 / inkSum.3, inkSum.2 / inkSum.3)
        }
        return colors
    }
}

extension CharacterRig {
    /// 얼굴과 팔다리가 이미 그려진 이미지 캐릭터용 추천 설정
    static func applyImageDefaults(to rig: inout CharacterRig, colors: ImageColorSampler.Colors) {
        let skin = colors.skin ?? "#FFF4DC"
        let ink = colors.ink ?? "#3A2218"
        rig.face.style = .overlay
        rig.face.blush = false
        rig.face.skinHex = skin
        rig.face.colorHex = ink
        rig.limbColorHex = ink
        rig.limbFillHex = skin
        rig.handStyle = .none
        rig.footStyle = .none
        rig.limbsInFront = true
        for kind in LimbKind.allCases {
            var limb = rig.limb(kind)
            limb.length = kind.isArm ? 0.14 : 0.08
            limb.thickness = kind.isArm ? 0.075 : 0.085
            limb.swing = kind.isArm ? 20 : 10
            rig.setLimb(kind, limb)
        }
    }
}

extension CharacterRig {
    mutating func setPartRect(_ part: PuppetPart, _ rect: CGRect) {
        if let limb = part.limb {
            var l = self.limb(limb)
            l.spriteRect = rect
            setLimb(limb, l)
        } else {
            head.rect = rect
        }
    }

    mutating func setPartPivot(_ part: PuppetPart, _ p: CGPoint) {
        if let limb = part.limb {
            var l = self.limb(limb)
            l.anchor = p
            setLimb(limb, l)
        } else {
            head.pivot = p
        }
    }

    func partEnabled(_ part: PuppetPart) -> Bool {
        if let limb = part.limb { return self.limb(limb).enabled }
        return head.enabled
    }

    mutating func setPartEnabled(_ part: PuppetPart, _ on: Bool) {
        if let limb = part.limb {
            var l = self.limb(limb)
            l.enabled = on
            setLimb(limb, l)
        } else {
            head.enabled = on
        }
    }
}
