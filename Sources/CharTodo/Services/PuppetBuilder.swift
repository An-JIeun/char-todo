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

        /// 원형으로 넓히기 (각진 모서리 없이 선 두께를 정확히 맞출 때)
        func dilateDisk(_ r: Int) -> Mask {
            guard r > 0 else { return self }
            var offsets: [(Int, Int)] = []
            for dy in -r...r { for dx in -r...r where dx * dx + dy * dy <= r * r { offsets.append((dx, dy)) } }
            var out = [UInt8](repeating: 0, count: w * h)
            for y in 0..<h {
                for x in 0..<w where v[y * w + x] != 0 {
                    for (dx, dy) in offsets {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, ny >= 0, nx < w, ny < h { out[ny * w + nx] = 1 }
                    }
                }
            }
            return Mask(w: w, h: h, v: out, ox: ox, oy: oy)
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
            let opened = found.opened      // 팔다리를 뗀 몸통 실루엣 (관절 추정용)
            let edge = limb.dilateDisk(1)                          // 안티앨리어싱 가장자리 포함
            let halo = limb.dilateDisk(3)                          // 원본 가장자리의 반투명 테두리
            let band = edge.dilateDisk(ow)                         // 잘린 경계에서 선 두께만큼 (원형)

            var sprite = Bitmap(w: w, h: h)
            var jx = 0, jy = 0, jn = 0
            for ly in 0..<band.h {
                for lx in 0..<band.w where band.v[ly * band.w + lx] != 0 {
                    let x = lx + band.ox, y = ly + band.oy
                    guard x >= 0, y >= 0, x < w, y < h else { continue }
                    let i = y * w + x
                    let a = src.px[i * 4 + 3]
                    if edge[x, y] {
                        // 조각: 팔다리 모양 그대로, 몸통에서는 지운다
                        if a > 0 { sprite.copyPixel(from: src, x, y); limbOwned[i] = 1 }
                        body.clear(x, y)
                        if limb[x, y] && (opened[x + 1, y] || opened[x - 1, y] || opened[x, y + 1] || opened[x, y - 1]) {
                            jx += x; jy += y; jn += 1
                        }
                    } else if a > 128 && window[x, y] && src.lum(x, y) >= 125 {
                        // 잘린 경계 바로 안쪽의 몸통 피부 → 원래 선 두께로 윤곽선을 잇는다
                        body.set(x, y, ink)
                    } else if halo[x, y] && !window[x, y] && a > 0 && a < 230 {
                        // 몸 밖에 남은 반투명 테두리(잔상)는 조각 쪽으로 옮긴다
                        sprite.copyPixel(from: src, x, y)
                        body.clear(x, y)
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
        var candidates: [(limb: Mask, opened: Mask, count: Int)] = []
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
            if ProcessInfo.processInfo.environment["CHARTODO_PUPPET_DEBUG"] != nil {
                // 경계(몸통과 맞닿은 속살 픽셀) 길이도 함께 기록
                var junction = 0
                for ly in 0..<core.h { for lx in 0..<core.w where core.v[ly * core.w + lx] != 0 {
                    let x = lx + core.ox, y = ly + core.oy
                    if opened[x + 1, y] || opened[x - 1, y] || opened[x, y + 1] || opened[x, y - 1] { junction += 1 }
                } }
                print("LIMB r=\(r) count=\(count) border=\(touchesBorder) junction=\(junction) ow=\(ow)")
            }
            if count < max(8, ow * ow / 3) { continue }          // 너무 작음 → 더 굵게
            if count > maxArea || touchesBorder { break }        // 몸통까지 번짐 → 그 전 결과 중에서 고른다

            // 3) 속살 둘레의 진한 윤곽선(돌출부에 속한 것)을 붙인다
            let ring = core.dilateDisk(ow + 1)
            var limb = core
            for ly in 0..<limb.h {
                for lx in 0..<limb.w where ring.v[ly * limb.w + lx] != 0 && limb.v[ly * limb.w + lx] == 0 {
                    let x = lx + limb.ox, y = ly + limb.oy
                    if protr(x, y) && (dark(x, y) || src.alpha(x, y) < 200) { limb.v[ly * limb.w + lx] = 1 }
                }
            }
            candidates.append((limb, opened, count))
        }
        // 반경을 키워도 크기가 그대로인 구간(= 팔다리가 몸에서 깔끔히 떨어진 상태)을 고른다
        for i in 0..<max(0, candidates.count - 1) where candidates[i].count == candidates[i + 1].count {
            return (candidates[i].limb, candidates[i].opened)
        }
        // 안정 구간이 없으면 급격히 커지기(몸으로 샘) 직전의 가장 큰 결과
        var pick = candidates.first
        for c in candidates.dropFirst() {
            guard let p = pick, c.count <= p.count * 4 else { break }
            pick = c
        }
        return pick.map { ($0.limb, $0.opened) }
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

/// 이미지 얼굴 분석: 깜빡일 때 눈만 정확히 가리기 위해 실제 눈 모양을 찾는다 (눈썹은 절대 건드리지 않는다)
enum FaceAnalyzer {
    struct Eyes {
        /// 몸통 단위 좌표의 눈 영역 [왼쪽, 오른쪽]
        var rects: [CGRect]
        /// 눈 모양대로 칠한 피부색 가림막 (원본과 같은 크기, 나머지는 투명)
        var cover: NSImage
    }

    static func analyze(image cg: CGImage, face: FaceConfig) -> Eyes? {
        guard let bmp = PuppetBuilder.Bitmap(cg) else { return nil }
        let w = bmp.w, h = bmp.h
        let es = max(4, Int(face.eyeSize * Double(w)))
        let skin = PuppetBuilder.hexRGB(face.skinHex)

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * w + x) * 4
            let a = max(1, Int(bmp.px[i + 3]))
            return (Int(bmp.px[i]) * 255 / a, Int(bmp.px[i + 1]) * 255 / a, Int(bmp.px[i + 2]) * 255 / a)
        }
        /// 눈썹·갈기 같은 주황/분홍 계열
        func warm(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = rgb(x, y)
            return bmp.alpha(x, y) > 128 && r > 170 && r - b > 55 && r - g > 25
        }
        func eyePixel(_ x: Int, _ y: Int) -> Bool {
            guard bmp.alpha(x, y) > 128 else { return false }
            let (r, g, b) = rgb(x, y)
            let lum = (r * 299 + g * 587 + b * 114) / 1000
            let neutralWhite = r > 232 && g > 232 && b > 232 && abs(r - b) < 18   // 하이라이트 (크림 피부는 제외)
            return lum < 130 || neutralWhite
        }

        var cover = PuppetBuilder.Bitmap(w: w, h: h)
        var rects: [CGRect] = []
        for side in [-1.0, 1.0] {
            let hx = Int((face.center.x + side * face.eyeSpacing / 2) * Double(w))
            let hy = Int(face.center.y * Double(h))
            // 1) 힌트 바로 주변(눈 크기의 0.6배)에서 가장 어두운 점 = 눈동자
            var seed: (Int, Int)?
            var best = 999
            let near = max(2, es * 6 / 10)
            for y in max(0, hy - near)..<min(h, hy + near) {
                for x in max(0, hx - near)..<min(w, hx + near) where bmp.alpha(x, y) > 128 {
                    let l = bmp.lum(x, y)
                    if l < best { best = l; seed = (x, y) }
                }
            }
            guard let s0 = seed, best < 110 else { return nil }

            // 2) 눈동자 위로 올라가며 눈썹(주황)의 아래 끝을 찾는다 → 그 아래만 눈
            var browBottom = -1
            for y in stride(from: s0.1 - 1, through: max(0, s0.1 - es * 3), by: -1) {
                if (max(0, s0.0 - es)..<min(w, s0.0 + es)).contains(where: { warm($0, y) }) { browBottom = y; break }
            }
            let topLimit = browBottom >= 0 ? browBottom + max(2, es / 8) : s0.1 - es * 2

            // 3) 어두운 눈동자 + 흰 하이라이트만 따라 채우기
            var mask = [UInt8](repeating: 0, count: w * h)
            var stack = [s0]
            var minX = s0.0, maxX = s0.0, minY = s0.1, maxY = s0.1
            let reach = es * 2
            while let (x, y) = stack.popLast() {
                guard x >= 0, y >= 0, x < w, y < h, y > topLimit, abs(x - s0.0) <= reach, abs(y - s0.1) <= reach else { continue }
                let i = y * w + x
                guard mask[i] == 0, eyePixel(x, y) else { continue }
                mask[i] = 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                stack.append((x + 1, y)); stack.append((x - 1, y)); stack.append((x, y + 1)); stack.append((x, y - 1))
            }
            guard maxX - minX >= 2, maxY - minY >= 2 else { return nil }

            // 4) 눈 모양을 2px 넓혀 피부색으로 칠한다. 눈썹 줄 위·주황 픽셀은 절대 칠하지 않는다
            let pad = max(2, es / 10)
            for y in max(topLimit + 1, minY - pad)...min(h - 1, maxY + pad) {
                for x in max(0, minX - pad)...min(w - 1, maxX + pad) where bmp.alpha(x, y) > 0 && !warm(x, y) {
                    var hit = false
                    outer: for dy in -pad...pad {
                        for dx in -pad...pad {
                            let nx = x + dx, ny = y + dy
                            if nx >= 0, ny >= 0, nx < w, ny < h, mask[ny * w + nx] != 0 { hit = true; break outer }
                        }
                    }
                    if hit { cover.set(x, y, skin) }
                }
            }
            rects.append(CGRect(x: Double(minX) / Double(w), y: Double(minY) / Double(h),
                                width: Double(maxX - minX + 1) / Double(w), height: Double(maxY - minY + 1) / Double(h)))
        }
        guard rects.count == 2, let img = cover.nsImage else { return nil }
        return Eyes(rects: rects.sorted { $0.minX < $1.minX }, cover: img)
    }
}
