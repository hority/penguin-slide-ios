import UIKit
import simd

/// 画像ファイルを使わず、Core Graphicsで手続き生成するテクスチャ。
enum PenguinTextures {
    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    static func image(_ width: Int, _ height: Int, opaque: Bool = true, _ draw: (CGContext, CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { draw($0.cgContext, rect) }
    }

    /// 明度から法線マップを作る（bumpMap 相当）。
    static func normalMap(from source: UIImage, strength: Float) -> UIImage? {
        guard let cgImage = source.cgImage else { return nil }
        let w = cgImage.width, h = cgImage.height
        var gray = [UInt8](repeating: 0, count: w * h)
        gray.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?
                .draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let left = Float(gray[y * w + (x + w - 1) % w]), right = Float(gray[y * w + (x + 1) % w])
                let up = Float(gray[((y + h - 1) % h) * w + x]), down = Float(gray[((y + 1) % h) * w + x])
                let n = simd_normalize(SIMD3<Float>((left - right) / 255 * strength, (down - up) / 255 * strength, 1))
                let i = (y * w + x) * 4
                out[i] = UInt8(max(0, min(255, (n.x * 0.5 + 0.5) * 255)))
                out[i + 1] = UInt8(max(0, min(255, (n.y * 0.5 + 0.5) * 255)))
                out[i + 2] = UInt8(max(0, min(255, (n.z * 0.5 + 0.5) * 255)))
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }

    /// タイル可能な水面の波（サイン波の和）。
    static func waterNormal() -> UIImage {
        image(256, 256) { cg, rect in
            cg.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
            cg.fill(rect)
            for _ in 0..<5 {
                let kx = CGFloat(Int.random(in: 1...4)), ky = CGFloat(Int.random(in: 1...4)), phase = CGFloat.random(in: 0...6)
                for y in stride(from: 0, to: 256, by: 2) {
                    for x in stride(from: 0, to: 256, by: 2) {
                        let v = sin((CGFloat(x) * kx + CGFloat(y) * ky) / 256 * 2 * .pi + phase)
                        cg.setFillColor(UIColor(white: v > 0 ? 1 : 0, alpha: abs(v) * 0.08).cgColor)
                        cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                    }
                }
            }
        }
    }

    /// 空のグラデーションと明るい太陽の正距円筒画像（環境ライティング用）。
    /// 地平線のもや色。空の地平線・遠くの海のフォグ・背景で共通にし、境目を見せない。
    static let horizon: UInt32 = 0xbfd2db

    static func sky() -> UIImage {
        image(512, 256) { cg, rect in
            let colors = [color(0x5d8fc4), color(0x9cc0dc), color(horizon), color(horizon), color(0x2a5a72)].map(\.cgColor) as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.36, 0.5, 0.54, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
            }
            let sun = CGPoint(x: 512 * 0.375, y: 256 * 0.3)
            let glow = [UIColor(red: 1, green: 0.95, blue: 0.82, alpha: 1).cgColor, UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glow, locations: [0, 1]) {
                cg.drawRadialGradient(gradient, startCenter: sun, startRadius: 6, endCenter: sun, endRadius: 70, options: [])
            }
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: sun.x - 12, y: sun.y - 12, width: 24, height: 24))
        }
    }

    static func softDot() -> UIImage {
        image(64, 64, opaque: false) { cg, _ in
            let colors = [UIColor.white.cgColor, UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) {
                cg.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
            }
        }
    }

    static func star(_ fill: UIColor = .white) -> UIImage {
        image(64, 64, opaque: false) { cg, _ in
            let path = CGMutablePath()
            for i in 0..<10 {
                let r: CGFloat = i % 2 == 0 ? 30 : 13
                let a = CGFloat(i) * .pi / 5 - .pi / 2
                let p = CGPoint(x: 32 + cos(a) * r, y: 32 + sin(a) * r)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            cg.addPath(path)
            cg.setFillColor(fill.cgColor)
            cg.fillPath()
        }
    }

    /// 光る数字「×N」の文字面：白い文字に濃紺の太い縁、そのまわりに琥珀色のにじみ。雪の上でも海の上でも読める。
    static func countLabel(_ text: String) -> UIImage {
        image(256, 128, opaque: false) { cg, rect in
            let font = UIFont(name: PenguinFonts.name, size: 92) ?? .systemFont(ofSize: 92, weight: .black)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let outline = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: color(0x101a36),
                                                                       .strokeColor: color(0x101a36), .strokeWidth: -26])
            let fill = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: UIColor.white])
            let height = fill.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], context: nil).height
            let box = CGRect(x: 0, y: (rect.height - height) / 2, width: rect.width, height: height)
            cg.setShadow(offset: .zero, blur: 14, color: color(0xffc24a, 0.95).cgColor)
            outline.draw(in: box)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            fill.draw(in: box)
        }
    }

    static func heart() -> UIImage {
        image(64, 64, opaque: false) { cg, _ in
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 32, y: 56))
            path.addCurve(to: CGPoint(x: 4, y: 22), control1: CGPoint(x: 14, y: 44), control2: CGPoint(x: 4, y: 34))
            path.addArc(center: CGPoint(x: 18, y: 20), radius: 14, startAngle: .pi, endAngle: 0, clockwise: false)
            path.addArc(center: CGPoint(x: 46, y: 20), radius: 14, startAngle: .pi, endAngle: 0, clockwise: false)
            path.addCurve(to: CGPoint(x: 32, y: 56), control1: CGPoint(x: 60, y: 34), control2: CGPoint(x: 50, y: 44))
            cg.addPath(path)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillPath()
        }
    }

    /// 接地影のデカール。
    static func contactShadow() -> UIImage {
        image(128, 128, opaque: false) { cg, _ in
            let colors = [UIColor(white: 0, alpha: 0.62).cgColor, UIColor(white: 0, alpha: 0.25).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
                cg.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
            }
        }
    }

    /// 光の筋：v方向で減衰し、u方向の端はsinでフェード。加算合成用に黒地。
    static func lightShaft() -> UIImage {
        image(64, 256) { cg, rect in
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(rect)
            for y in 0..<64 {
                let v = CGFloat(y) / 63
                let fadeV = pow(1 - v, 0.8) * min(1, v * 6 + 0.2)
                for x in 0..<16 {
                    let u = (CGFloat(x) + 0.5) / 16
                    let value = pow(sin(.pi * u), 1.6) * fadeV
                    cg.setFillColor(UIColor(white: value, alpha: 1).cgColor)
                    cg.fill(CGRect(x: CGFloat(x) * 4, y: CGFloat(y) * 4, width: 4, height: 4))
                }
            }
        }
    }

    /// 看板の文字面（板の枠の内側に貼る）。板の縦横比に合わせて描き、文字を伸ばさない。
    /// 白地に濃紺の太い文字で、遠めのカメラからでも読めるよう面いっぱいに大きく描く。
    static func sign(_ text: String, dots: Int, highlight: Bool, aspect: CGFloat = 1) -> UIImage {
        let height: CGFloat = 256, width = (height * max(0.6, min(aspect, 1.8))).rounded()
        return image(Int(width), Int(height)) { cg, rect in
            cg.setFillColor(color(highlight ? 0xfff1b8 : 0xffffff).cgColor)
            cg.fill(rect)
            cg.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), cornerRadius: 22).cgPath)
            cg.setStrokeColor(color(highlight ? 0xf0b13e : 0x5cc9a0).cgColor)
            cg.setLineWidth(12)
            cg.strokePath()
            let size: CGFloat = dots > 0 ? 150 : (text.count > 1 ? 150 : 196)
            let font = UIFont(name: PenguinFonts.name, size: size) ?? .systemFont(ofSize: size, weight: .black)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(0x101a36), .paragraphStyle: style,
                                                              .strokeColor: color(0x101a36), .strokeWidth: -4]
            let string = NSAttributedString(string: text, attributes: attributes)
            let bounds = string.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], context: nil)
            let top = (dots > 0 ? 104 : 128) - bounds.height / 2
            string.draw(in: CGRect(x: 0, y: top, width: width, height: bounds.height))
            guard dots > 0 else { return }
            let perRow = min(dots, 5), rows = (dots + 4) / 5, dot: CGFloat = 24
            for i in 0..<dots {
                let row = i / 5, column = i % 5
                let count = row == rows - 1 ? dots - row * 5 : perRow
                let x = width / 2 - CGFloat(count) * (dot + 6) / 2 + CGFloat(column) * (dot + 6) + 3
                let y = 196 + CGFloat(row) * (dot + 4) - CGFloat(rows - 1) * 16
                cg.setFillColor(color(0xe2662b).cgColor)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
            }
        }
    }
}
