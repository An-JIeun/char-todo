import AppKit
import Vision
import CoreImage

/// Vision 전경 분리로 캐릭터 이미지 배경을 지운다 (macOS 14+).
enum BackgroundRemover {
    enum Failure: LocalizedError {
        case noImage, noSubject
        var errorDescription: String? {
            switch self {
            case .noImage: "이미지를 읽을 수 없어요."
            case .noSubject: "피사체를 찾지 못했어요. 배경과 대비가 뚜렷한 이미지를 써 보세요."
            }
        }
    }

    static func removeBackground(from image: NSImage) async throws -> NSImage {
        guard let cg = image.cgImageValue else { throw Failure.noImage }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { throw Failure.noSubject }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: buffer)
            let ctx = CIContext()
            guard let out = ctx.createCGImage(ci, from: ci.extent) else { throw Failure.noImage }
            return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
        }.value
    }

    /// 너무 큰 이미지는 축소해서 저장 (최대 1024px)
    static func downscaled(_ image: NSImage, maxSide: CGFloat = 1024) -> NSImage {
        guard let cg = image.cgImageValue else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h))
        guard scale < 1 else { return NSImage(cgImage: cg, size: NSSize(width: w, height: h)) }
        let nw = Int(w * scale), nh = Int(h * scale)
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let out = ctx.makeImage() else { return image }
        return NSImage(cgImage: out, size: NSSize(width: nw, height: nh))
    }
}
