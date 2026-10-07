import AppKit
import CoreGraphics

/// 캐릭터 이미지를 머리·팔·다리·몸통 파츠로 나누고 잘린 자리를 다듬은 결과
struct PuppetImages {
    /// 팔다리·머리를 떼어 내고 빈자리를 메운 몸통
    var body: NSImage
    /// 파츠별 조각 (원본과 같은 크기 캔버스, 나머지는 투명)
    var parts: [String: NSImage]
    /// 어떤 설정으로 만들었는지 (설정이 바뀌면 다시 만든다)
    var key: String
    /// 팔다리와 몸이 맞닿은 곳의 중심 (관절 자동 맞춤용, 몸통 단위 좌표)
    var suggestedPivots: [String: CGPoint] = [:]
}

enum PuppetPart: String, CaseIterable, Identifiable {
    case head, leftArm, rightArm, leftLeg, rightLeg
    var id: String { rawValue }
    var label: String {
        switch self {
        case .head: "머리"
        case .leftArm: "왼팔"
        case .rightArm: "오른팔"
        case .leftLeg: "왼다리"
        case .rightLeg: "오른다리"
        }
    }
    var limb: LimbKind? {
        switch self {
        case .head: nil
        case .leftArm: .leftArm
        case .rightArm: .rightArm
        case .leftLeg: .leftLeg
        case .rightLeg: .rightLeg
        }
    }
}

extension CharacterRig {
    /// 파츠 영역 (몸통 단위 좌표)
    func partRect(_ part: PuppetPart) -> CGRect? {
        if let limb = part.limb {
            let l = self.limb(limb)
            return l.enabled ? l.spriteRect : nil
        }
        return head.enabled ? head.rect : nil
    }

    /// 팔다리 위에 찍은 점 (없으면 예전 상자 중심)
    func grabPoint(_ kind: LimbKind) -> CGPoint? {
        let l = limb(kind)
        guard l.enabled else { return nil }
        if let g = l.grabPoint { return g }
        if let r = l.spriteRect { return CGPoint(x: r.midX, y: r.midY) }
        return nil
    }

    func partPivot(_ part: PuppetPart) -> CGPoint {
        if let limb = part.limb { return self.limb(limb).anchor }
        return head.pivot
    }

    /// 파츠 결과를 다시 만들어야 하는지 판단하는 키
    var puppetKey: String {
        var s = "\(imageFile ?? "-")|\(face.skinHex)|\(limbColorHex)"
        for kind in LimbKind.allCases {
            if let g = grabPoint(kind) { s += "|\(kind.rawValue):\(g.x),\(g.y)" }
        }
        if let r = partRect(.head) { s += "|head:\(r.debugDescription)" }
        return s
    }
}

enum PuppetBuilder {
    /// RGBA8 (premultiplied) 버퍼
    struct Bitmap {
        var w: Int
        var h: Int
        var px: [UInt8]

        init(w: Int, h: Int) {
            self.w = w
            self.h = h
            px = [UInt8](repeating: 0, count: w * h * 4)
        }

        init?(_ cg: CGImage) {
            w = cg.width
            h = cg.height
            px = [UInt8](repeating: 0, count: w * h * 4)
            let ok = px.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                // 비트맵 메모리의 0행 = 이미지 위쪽 (뒤집지 않고 그대로 그린다)
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            if !ok { return nil }
        }

        func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }

        func lum(_ x: Int, _ y: Int) -> Int {
            let i = (y * w + x) * 4
            let a = max(1, Int(px[i + 3]))
            let r = Int(px[i]) * 255 / a, g = Int(px[i + 1]) * 255 / a, b = Int(px[i + 2]) * 255 / a
            return (r * 299 + g * 587 + b * 114) / 1000
        }

        mutating func set(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8), alpha a: UInt8 = 255) {
            let i = (y * w + x) * 4
            px[i] = UInt8(Int(c.0) * Int(a) / 255)
            px[i + 1] = UInt8(Int(c.1) * Int(a) / 255)
            px[i + 2] = UInt8(Int(c.2) * Int(a) / 255)
            px[i + 3] = a
        }

        mutating func clear(_ x: Int, _ y: Int) {
            let i = (y * w + x) * 4
            px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0
        }

        mutating func copyPixel(from src: Bitmap, _ x: Int, _ y: Int, alphaScale: Double = 1) {
            let i = (y * w + x) * 4
            for k in 0..<4 { px[i + k] = UInt8(Double(src.px[i + k]) * alphaScale) }
        }

        var nsImage: NSImage? {
            var copy = px
            return copy.withUnsafeMutableBytes { buf -> NSImage? in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                      let cg = ctx.makeImage() else { return nil }
                // 버퍼 0행이 위 → CGImage도 그대로 위가 0행
                return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
            }
        }
    }

    /// 0/1 마스크
    struct Mask {
        var w: Int
        var h: Int
        var v: [UInt8]

        /// 잘라낸 창의 원점 (전체 이미지 좌표)
        var ox = 0
        var oy = 0

        /// 전체 이미지 좌표로 조회
        subscript(x: Int, y: Int) -> Bool {
            let lx = x - ox, ly = y - oy
            guard lx >= 0, ly >= 0, lx < w, ly < h else { return false }
            return v[ly * w + lx] != 0
        }

        /// 필요한 영역만 잘라 계산량을 줄인다
        func crop(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Mask {
            let cx0 = max(0, x0), cy0 = max(0, y0), cx1 = min(w, x1), cy1 = min(h, y1)
            let cw = max(1, cx1 - cx0), ch = max(1, cy1 - cy0)
            var out = [UInt8](repeating: 0, count: cw * ch)
            for y in 0..<ch {
                for x in 0..<cw { out[y * cw + x] = v[(y + cy0) * w + (x + cx0)] }
            }
            return Mask(w: cw, h: ch, v: out, ox: cx0 + ox, oy: cy0 + oy)
        }

        /// 정사각 창 안이 모두 1이면 1 (erode) / 하나라도 1이면 1 (dilate). 누적합으로 O(w·h).
        func morph(radius r: Int, erode: Bool) -> Mask {
            guard r > 0 else { return self }
            func pass(_ src: [UInt8], horizontal: Bool) -> [UInt8] {
                var out = [UInt8](repeating: 0, count: w * h)
                let lines = horizontal ? h : w, len = horizontal ? w : h
                var prefix = [Int](repeating: 0, count: len + 1)
                for line in 0..<lines {
                    for i in 0..<len {
                        let idx = horizontal ? line * w + i : i * w + line
                        prefix[i + 1] = prefix[i] + Int(src[idx])
                    }
                    for i in 0..<len {
                        let lo = max(0, i - r), hi = min(len - 1, i + r)
                        let count = prefix[hi + 1] - prefix[lo]
                        let full = 2 * r + 1
                        // 가장자리 밖은 erode 때 0으로 본다
                        let on = erode ? (count == full && i - r >= 0 && i + r < len) : count > 0
                        let idx = horizontal ? line * w + i : i * w + line
                        out[idx] = on ? 1 : 0
                    }
                }
                return out
            }
            return Mask(w: w, h: h, v: pass(pass(v, horizontal: true), horizontal: false), ox: ox, oy: oy)
        }
    }

    static func hexRGB(_ hex: String) -> (UInt8, UInt8, UInt8) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0xFFFFFF
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    /// 윤곽선 두께(px) 추정: 실루엣 가장자리에서 안쪽으로 이어지는 어두운 픽셀 길이의 중앙값
    static func estimateOutline(_ bmp: Bitmap) -> Int {
        var runs: [Int] = []
        for f in stride(from: 0.3, through: 0.8, by: 0.1) {
            let y = Int(Double(bmp.h) * f)
            for dir in [1, -1] {
                var x = dir == 1 ? 0 : bmp.w - 1
                while x >= 0, x < bmp.w, bmp.alpha(x, y) < 128 { x += dir }
                var run = 0
                while x >= 0, x < bmp.w, bmp.alpha(x, y) >= 128, bmp.lum(x, y) < 120 { run += 1; x += dir }
                if run > 0 { runs.append(run) }
            }
        }
        let sorted = runs.sorted()
        let median = sorted.isEmpty ? max(2, bmp.w / 60) : sorted[sorted.count / 2]
        return min(max(2, median), max(3, bmp.w / 25))
    }

    static func pixelRect(_ unit: CGRect, _ w: Int, _ h: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
        let x0 = max(0, Int((unit.minX * CGFloat(w)).rounded(.down)))
        let y0 = max(0, Int((unit.minY * CGFloat(h)).rounded(.down)))
        let x1 = min(w, Int((unit.maxX * CGFloat(w)).rounded(.up)))
        let y1 = min(h, Int((unit.maxY * CGFloat(h)).rounded(.up)))
        return (x0, y0, max(x0, x1), max(y0, y1))
    }

    /// 파츠를 나누고 다듬는다. 무거운 작업이므로 백그라운드에서 호출.
    static func build(image cg: CGImage, rig: CharacterRig) -> PuppetImages? {
        guard let src = Bitmap(cg) else { return nil }
        let w = src.w, h = src.h
        let skin = hexRGB(rig.face.skinHex)
        let ink = hexRGB(rig.limbColorHex)
        let ow = estimateOutline(src)

        let alphaMask = Mask(w: w, h: h, v: (0..<(w * h)).map { src.px[$0 * 4 + 3] >= 128 ? 1 : 0 })
        var body = src
        var parts: [String: NSImage] = [:]

        // 팔다리가 차지한 픽셀 (머리 조각에서 빼기 위해)
        var limbOwned = [UInt8](repeating: 0, count: w * h)
        var pivots: [String: CGPoint] = [:]
        let alphaCount = alphaMask.v.reduce(0) { $0 + Int($1) }

        // 1) 팔다리: 찍은 점과 이어진 '가는 돌출부'를 배경 제거처럼 모양대로 떼어 내고,
        //    빈자리는 몸통 실루엣을 따라 윤곽선을 이어 그린다
        for kind in LimbKind.allCases {
            guard let g = rig.grabPoint(kind) else { continue }
            let gx = Int(g.x * Double(w)), gy = Int(g.y * Double(h))
            guard gx >= 0, gy >= 0, gx < w, gy < h else { continue }
            let reach = Int(Double(w) * 0.26)
            let window = materialMask(src: src, skin: skin,
                                      alphaMask.crop(gx - reach, gy - reach, gx + reach, gy + reach))

            guard let found = findLimb(src: src, window: window, gx: gx, gy: gy, ow: ow, skin: skin,
                                       maxArea: max(ow * ow * 6, alphaCount / 25)) else { continue }
            let limb = found.limb          // 팔다리 모양 (창 좌표)
            let opened = found.opened      // 팔다리를 뗀 몸통 실루엣
            let inner = opened.morph(radius: ow, erode: true)
            let near = limb.morph(radius: ow, erode: false)          // 팔다리 바로 옆
            let zone = limb.morph(radius: ow * 2 + 2, erode: false)  // 다듬을 범위
            let edge = limb.morph(radius: 1, erode: false)           // 안티앨리어싱 가장자리 포함

            var sprite = Bitmap(w: w, h: h)
            var jx = 0, jy = 0, jn = 0
            for ly in 0..<zone.h {
                for lx in 0..<zone.w where zone.v[ly * zone.w + lx] != 0 {
                    let x = lx + zone.ox, y = ly + zone.oy
                    guard x >= 0, y >= 0, x < w, y < h else { continue }
                    let i = y * w + x
                    let inLimb = limb[x, y]
                    // 조각: 팔다리 모양 그대로 (가장자리 1px 포함)
                    if edge[x, y] && !opened[x, y] && src.px[i * 4 + 3] > 0 {
                        sprite.copyPixel(from: src, x, y)
                        limbOwned[i] = 1
                    }
                    // 관절 후보: 몸통과 맞닿은 팔다리 픽셀
                    if inLimb && (opened[x + 1, y] || opened[x - 1, y] || opened[x, y + 1] || opened[x, y - 1]) {
                        jx += x; jy += y; jn += 1
                    }
                    // 몸통 다듬기
                    if opened[x, y] {
                        if !inner[x, y] {
                            body.set(x, y, ink)                  // 빈자리에 윤곽선 채우기
                        } else if near[x, y] {
                            body.set(x, y, skin)                 // 팔다리 뿌리 자국 지우기
                        }
                    } else if edge[x, y] {
                        body.clear(x, y)                         // 몸 밖으로 나온 팔다리 제거
                    }
                }
            }
            if jn > 0 {
                pivots[kind.rawValue] = CGPoint(x: Double(jx) / Double(jn) / Double(w), y: Double(jy) / Double(jn) / Double(h))
            }
            if let img = sprite.nsImage { parts[kind.rawValue] = img }
        }

        // 2) 머리: 원본에서 머리 영역을 떼고(아래쪽 경계는 부드럽게), 몸통 쪽 그 자리는 피부색 + 윤곽선으로 메운다
        if let unit = rig.partRect(.head) {
            let r = pixelRect(unit, w, h)
            if r.x1 - r.x0 > 2, r.y1 - r.y0 > 2 {
                let inner = alphaMask.crop(r.x0 - ow - 2, r.y0 - ow - 2, r.x1 + ow + 2, r.y1 + ow + 2).morph(radius: ow, erode: true)
                let feather = max(3, (r.y1 - r.y0) / 14)
                var sprite = Bitmap(w: w, h: h)
                for y in r.y0..<r.y1 {
                    for x in r.x0..<r.x1 {
                        if limbOwned[y * w + x] != 0 { continue }
                        let a = src.px[(y * w + x) * 4 + 3]
                        guard a > 0 else { continue }
                        let fromBottom = r.y1 - 1 - y
                        let fade = fromBottom < feather ? Double(fromBottom) / Double(feather) : 1
                        sprite.copyPixel(from: src, x, y, alphaScale: fade)
                        // 머리 밑 몸통: 실루엣만 남기고 얼굴·무늬는 지운다 (머리가 기울어도 겹쳐 보이지 않게)
                        if fromBottom >= feather {
                            body.set(x, y, inner[x, y] ? skin : ink, alpha: a)
                        }
                    }
                }
                if let img = sprite.nsImage { parts[PuppetPart.head.rawValue] = img }
            }
        }

        guard let bodyImage = body.nsImage else { return nil }
        return PuppetImages(body: bodyImage, parts: parts, key: rig.puppetKey, suggestedPivots: pivots)
    }

    /// 마법봉처럼: 찍은 점에서 피부색으로 이어진 '가는 돌출부'(팔·발 속살)를 채우고, 그 둘레 윤곽선을 붙인다.
    /// 가는 것부터 굵은 것 순으로 opening 반경을 키워 몸통과 분리되는 지점을 찾는다.
    static func findLimb(src: Bitmap, window: Mask, gx: Int, gy: Int, ow: Int, skin: (UInt8, UInt8, UInt8),
                         maxArea: Int) -> (limb: Mask, opened: Mask)? {
        func skinLike(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < src.w, y < src.h else { return false }
            let i = (y * src.w + x) * 4
            let a = Int(src.px[i + 3])
            guard a > 160 else { return false }
            let r = Int(src.px[i]) * 255 / a, g = Int(src.px[i + 1]) * 255 / a, b = Int(src.px[i + 2]) * 255 / a
            let dr = r - Int(skin.0), dg = g - Int(skin.1), db = b - Int(skin.2)
            return dr * dr + dg * dg + db * db < 48 * 48
        }
        func dark(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < src.w, y < src.h, src.alpha(x, y) > 60 else { return false }
            return src.lum(x, y) < 125
        }

        let radii = [ow, ow * 3 / 2, ow * 2, ow * 5 / 2, ow * 3, ow * 4, ow * 5].map { max(2, $0) }
        var best: (limb: Mask, opened: Mask, count: Int)?
        for r in radii {
            let opened = window.morph(radius: r, erode: true).morph(radius: r, erode: false)
            func protr(_ x: Int, _ y: Int) -> Bool { window[x, y] && !opened[x, y] }

            // 1) 찍은 점에서 가장 가까운 '피부색 돌출부' 픽셀
            var seed: (Int, Int)?
            var bestD = Int.max
            let rr = max(r * 2, ow * 3)
            for y in (gy - rr)...(gy + rr) {
                for x in (gx - rr)...(gx + rr) where protr(x, y) && skinLike(x, y) {
                    let d = (x - gx) * (x - gx) + (y - gy) * (y - gy)
                    if d < bestD { bestD = d; seed = (x, y) }
                }
            }
            guard let s0 = seed else { continue }

            // 2) 피부색 돌출부만 따라 채우기 → 팔·발 속살
            var core = Mask(w: window.w, h: window.h, v: [UInt8](repeating: 0, count: window.v.count), ox: window.ox, oy: window.oy)
            var stack = [s0]
            var count = 0
            var touchesBorder = false
            while let (x, y) = stack.popLast() {
                let lx = x - window.ox, ly = y - window.oy
                guard lx >= 0, ly >= 0, lx < window.w, ly < window.h else { touchesBorder = true; continue }
                let i = ly * window.w + lx
                guard core.v[i] == 0, protr(x, y), skinLike(x, y) else { continue }
                core.v[i] = 1
                count += 1
                if lx == 0 || ly == 0 || lx == window.w - 1 || ly == window.h - 1 { touchesBorder = true }
                stack.append((x + 1, y)); stack.append((x - 1, y)); stack.append((x, y + 1)); stack.append((x, y - 1))
            }
            if count < max(8, ow * ow / 3) { continue }          // 너무 작음 → 더 굵게
            if count > maxArea || touchesBorder { break }        // 몸통까지 번짐 → 직전 결과 사용
            if let b = best, count > b.count * 3 { break }       // 갑자기 커짐 = 몸으로 샘

            // 3) 속살 둘레의 진한 윤곽선(돌출부에 속한 것)을 붙인다
            let ring = core.morph(radius: ow + 2, erode: false)
            var limb = core
            for ly in 0..<limb.h {
                for lx in 0..<limb.w where ring.v[ly * limb.w + lx] != 0 && limb.v[ly * limb.w + lx] == 0 {
                    let x = lx + limb.ox, y = ly + limb.oy
                    if protr(x, y) && (dark(x, y) || src.alpha(x, y) < 200) { limb.v[ly * limb.w + lx] = 1 }
                }
            }
            best = (limb, opened, count)
        }
        return best.map { ($0.limb, $0.opened) }
    }

    /// 팔다리 분리용 실루엣: 피부색·윤곽선만 남기고(갈기 등 다른 색은 제외), 몸 안쪽 구멍(눈썹·볼터치)은 메운다
    static func materialMask(src: Bitmap, skin: (UInt8, UInt8, UInt8), _ window: Mask) -> Mask {
        var m = window
        for ly in 0..<m.h {
            for lx in 0..<m.w where m.v[ly * m.w + lx] != 0 {
                let x = lx + m.ox, y = ly + m.oy
                let i = (y * src.w + x) * 4
                let a = max(1, Int(src.px[i + 3]))
                let r = Int(src.px[i]) * 255 / a, g = Int(src.px[i + 1]) * 255 / a, b = Int(src.px[i + 2]) * 255 / a
                let dr = r - Int(skin.0), dg = g - Int(skin.1), db = b - Int(skin.2)
                let isSkin = dr * dr + dg * dg + db * db < 60 * 60
                let isDark = (r * 299 + g * 587 + b * 114) / 1000 < 125
                if !isSkin && !isDark { m.v[ly * m.w + lx] = 0 }
            }
        }
        // 창 가장자리에서 닿을 수 있는 빈 곳 = 바깥. 닿지 않는 빈 곳 = 안쪽 구멍 → 메운다
        var outside = [UInt8](repeating: 0, count: m.v.count)
        var stack: [(Int, Int)] = []
        for x in 0..<m.w { stack.append((x, 0)); stack.append((x, m.h - 1)) }
        for y in 0..<m.h { stack.append((0, y)); stack.append((m.w - 1, y)) }
        while let (x, y) = stack.popLast() {
            guard x >= 0, y >= 0, x < m.w, y < m.h else { continue }
            let i = y * m.w + x
            guard outside[i] == 0, m.v[i] == 0 else { continue }
            outside[i] = 1
            stack.append((x + 1, y)); stack.append((x - 1, y)); stack.append((x, y + 1)); stack.append((x, y - 1))
        }
        for i in 0..<m.v.count where m.v[i] == 0 && outside[i] == 0 { m.v[i] = 1 }
        return m
    }
}

/// 이미지 얼굴 분석: 깜빡일 때 눈만 정확히 가리기 위해 실제 눈(어두운 덩어리) 영역을 찾는다
enum FaceAnalyzer {
    /// 반환: 몸통 단위 좌표의 눈 영역 [왼쪽, 오른쪽]. 못 찾으면 nil
    static func eyeRects(image cg: CGImage, face: FaceConfig) -> [CGRect]? {
        guard let bmp = PuppetBuilder.Bitmap(cg) else { return nil }
        let w = bmp.w, h = bmp.h
        let es = face.eyeSize * Double(w)
        var result: [CGRect] = []
        for side in [-1.0, 1.0] {
            let hx = Int((face.center.x + side * face.eyeSpacing / 2) * Double(w))
            let hy = Int(face.center.y * Double(h))
            let win = Int(es * 1.3)
            // 1) 힌트 근처에서 가장 어두운 픽셀을 씨앗으로
            var seed: (Int, Int)?
            var best = 999
            for y in max(0, hy - win)..<min(h, hy + win) {
                for x in max(0, hx - win)..<min(w, hx + win) where bmp.alpha(x, y) > 128 {
                    let l = bmp.lum(x, y)
                    if l < best { best = l; seed = (x, y) }
                }
            }
            guard let s = seed, best < 110 else { return nil }
            // 2) 어두운 픽셀을 따라 채우기 (반경 제한)
            let limit = Int(es * 2.2)
            var visited = Set<Int>()
            var stack = [s]
            var minX = s.0, maxX = s.0, minY = s.1, maxY = s.1
            while let (x, y) = stack.popLast() {
                let key = y * w + x
                guard !visited.contains(key) else { continue }
                visited.insert(key)
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h, abs(nx - s.0) < limit, abs(ny - s.1) < limit,
                          !visited.contains(ny * w + nx), bmp.alpha(nx, ny) > 128, bmp.lum(nx, ny) < 125 else { continue }
                    stack.append((nx, ny))
                }
            }
            let bw = maxX - minX + 1, bh = maxY - minY + 1
            // 눈썹 윤곽선 등과 이어져 너무 커지면 실패 처리
            guard bw >= 2, bh >= 2, Double(bw) < es * 2.6, Double(bh) < es * 2.8 else { return nil }
            result.append(CGRect(x: Double(minX) / Double(w), y: Double(minY) / Double(h),
                                 width: Double(bw) / Double(w), height: Double(bh) / Double(h)))
        }
        return result.count == 2 ? result.sorted { $0.minX < $1.minX } : nil
    }
}
