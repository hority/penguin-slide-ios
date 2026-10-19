import SceneKit
import UIKit
import simd

/// ci/convert-stage.py が書き出したステージ（HelloFlight/Stage/IcyStage.bin）。
/// 先頭にレイアウト情報（すべり台の中心線・台・島・看板の位置）のJSON、続いてメッシュ。
final class PenguinStageData {
    struct Meta: Decodable {
        struct Island: Decodable { let center: [Float]; let half: [Float]; let angle: Float }
        struct Face: Decodable { let center: [Float]; let normal: [Float]; let size: [Float] }
        struct Floe: Decodable { let board: [Float]; let radius: Float; let face: Face }
        let track: [[Float]]
        let stand: [Float]
        let islandTop: Float
        let island: Island
        /// 3つの答えの浮き氷で共有する1つの氷と看板。
        let floe: Floe
    }

    static let shared = PenguinStageData()
    let meta: Meta?
    /// "island", "floe", "board"
    let geometries: [String: SCNGeometry]

    private init() {
        let file = Self.load("IcyStage", in: "Stage")
        meta = file.flatMap { try? JSONDecoder().decode(Meta.self, from: $0.header) }
        geometries = file?.geometries ?? [:]
    }

    /// "STG2" 形式（ステージとキャラで共通）：先頭にJSON、続いて名前付きのメッシュ（位置・法線・UV・添字）。
    /// JSONの "weights" に名前があるメッシュは、添字の後にリグの重み（頂点ごとに頭・腕の float×2）が続き、頂点色として持つ。
    static func load(_ name: String, in folder: String) -> (header: Data, geometries: [String: SCNGeometry])? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: folder),
              let data = try? Data(contentsOf: url), data.count > 12, data.prefix(4) == Data("STG2".utf8) else { return nil }
        var offset = 4
        func read<T: FixedWidthInteger>(_ type: T.Type) -> T {
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
            offset += MemoryLayout<T>.size
            return T(littleEndian: value)
        }
        func chunk(_ length: Int) -> Data {
            defer { offset += length }
            return data.subdata(in: offset..<(offset + length))
        }
        let header = chunk(Int(read(UInt32.self)))
        struct Layout: Decodable { var weights: [String]? }
        let weighted = Set((try? JSONDecoder().decode(Layout.self, from: header))?.weights ?? [])
        var result: [String: SCNGeometry] = [:]
        for _ in 0..<Int(read(UInt32.self)) {
            let name = String(decoding: chunk(Int(read(UInt16.self))), as: UTF8.self)
            let vertexCount = Int(read(UInt32.self)), indexCount = Int(read(UInt32.self))
            let positions = chunk(vertexCount * 12), normals = chunk(vertexCount * 12), uvs = chunk(vertexCount * 8), indices = chunk(indexCount * 4)
            var sources = [
                SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: vertexCount, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
                SCNGeometrySource(data: normals, semantic: .normal, vectorCount: vertexCount, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
                SCNGeometrySource(data: uvs, semantic: .texcoord, vectorCount: vertexCount, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8),
            ]
            if weighted.contains(name) {
                let pairs = chunk(vertexCount * 8)
                let colors: [SIMD4<Float>] = pairs.withUnsafeBytes { raw in
                    (0..<vertexCount).map { i in
                        SIMD4(raw.loadUnaligned(fromByteOffset: i * 8, as: Float.self), raw.loadUnaligned(fromByteOffset: i * 8 + 4, as: Float.self), 0, 1)
                    }
                }
                sources.append(SCNGeometrySource(data: colors.withUnsafeBytes { Data($0) }, semantic: .color, vectorCount: vertexCount, usesFloatComponents: true,
                                                 componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16))
            }
            let element = SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: indexCount / 3, bytesPerIndex: 4)
            result[name] = SCNGeometry(sources: sources, elements: [element])
        }
        return (header, result)
    }

    /// ステージ全体で1枚のテクスチャアトラスを共有する（4Kから縮小済み：色1024・法線1024・粗さ512）。
    static func makeMaterial(ao: String) -> SCNMaterial {
        func image(_ name: String, _ ext: String) -> UIImage? {
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Stage").flatMap { UIImage(contentsOfFile: $0.path) }
        }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = image("stage_base", "jpg") ?? UIColor.white
        material.normal.contents = image("stage_normal", "png")
        material.roughness.contents = image("stage_rough", "png") ?? 0.6
        material.metalness.contents = 0.0
        for property in [material.diffuse, material.normal, material.roughness] { property.mipFilter = .linear }
        material.isDoubleSided = true
        material.shaderModifiers = [.surface: ao]
        return material
    }
}

/// ci/bake-model.py が書き出したキャラと海の生き物（HelloFlight/Models/）。名前は "penguin", "whale" など。
enum PenguinAsset {
    static func geometries(_ name: String) -> [String: SCNGeometry] {
        PenguinStageData.load(name.capitalized, in: "Models")?.geometries ?? [:]
    }

    static func material(_ name: String) -> SCNMaterial {
        func image(_ suffix: String, _ ext: String) -> UIImage? {
            Bundle.main.url(forResource: "\(name)_\(suffix)", withExtension: ext, subdirectory: "Models").flatMap { UIImage(contentsOfFile: $0.path) }
        }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = image("base", "jpg") ?? UIColor.white
        material.normal.contents = image("normal", "png")
        material.roughness.contents = image("rough", "png") ?? 0.5
        material.metalness.contents = 0.0
        for property in [material.diffuse, material.normal, material.roughness] { property.mipFilter = .linear }
        material.isDoubleSided = true
        return material
    }
}

/// すべり台の中心線。ステージのすべり台の面から取り出した点列をなぞる（滑走・接地影で共通）。
enum PenguinTrack {
    private static let meta = PenguinStageData.shared.meta
    /// 読み込めなかったときの予備：以前の放物線。
    private static let samples: [SIMD3<Float>] = smoothed(meta.map { stage in stage.track.map { p in SIMD3(p[0], p[1], p[2]) } }
        ?? (0...20).map { i in let t = Float(i) / 20; return SIMD3(-0.9 * (1 - t), 0.9 + 0.95 * (1 - t) * (1 - t), -2.8 + 1.9 * t) })

    /// 面から拾った点の細かな凹凸をならす（両端は動かさない）。滑るときの体の傾きが震えないように。
    private static func smoothed(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var result = points
        for _ in 0..<6 where result.count > 2 {
            let previous = result
            for i in 1..<(result.count - 1) {
                let neighbours: SIMD3<Float> = previous[i - 1] + previous[i + 1]
                result[i] = previous[i] * 0.5 + neighbours * 0.25
            }
        }
        return result
    }

    /// ペンギンが待つ台の上（足元）。
    static let stand: SIMD3<Float> = meta.map { stage in SIMD3(stage.stand[0], stage.stand[1], stage.stand[2]) } ?? SIMD3(-1.01, 1.85, -3.03)
    static var platformY: Float { stand.y }
    static let plateauTop: Float = meta?.islandTop ?? 0.55

    /// 水平方向の進行向き（単位ベクトル）と、+zからの回転角。
    static let heading: SIMD3<Float> = {
        let d = samples[samples.count - 1] - samples[0]
        return simd_normalize(SIMD3(d.x, 0, d.z))
    }()
    static let headingAngle = atan2(heading.x, heading.z)
    /// 進行方向に向かって右手側の水平ベクトル。
    static let side = SIMD3<Float>(heading.z, 0, -heading.x)

    /// 点の間は Catmull-Rom 曲線でつなぐ（向きの変化がなめらかになる）。
    private static func segment(_ t: Float) -> (p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>, u: Float) {
        let f = min(max(t, 0), 1) * Float(samples.count - 1)
        let i = min(Int(f), samples.count - 2)
        let p1 = samples[i], p2 = samples[i + 1]
        let p0: SIMD3<Float> = i > 0 ? samples[i - 1] : p1 * 2 - p2
        let p3: SIMD3<Float> = i + 2 < samples.count ? samples[i + 2] : p2 * 2 - p1
        return (p0, p1, p2, p3, f - Float(i))
    }

    /// 曲線の係数：位置 = a + b·u + c·u² + d·u³。
    private static func coefficients(_ t: Float) -> (a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>, d: SIMD3<Float>, u: Float) {
        let (p0, p1, p2, p3, u) = segment(t)
        let b: SIMD3<Float> = (p2 - p0) * 0.5
        let c: SIMD3<Float> = p0 - p1 * 2.5 + p2 * 2 - p3 * 0.5
        let d: SIMD3<Float> = (p1 - p2) * 1.5 + (p3 - p0) * 0.5
        return (p1, b, c, d, u)
    }

    static func point(_ t: Float) -> SIMD3<Float> {
        let k = coefficients(t)
        return k.a + (k.b + (k.c + k.d * k.u) * k.u) * k.u
    }

    static func tangent(_ t: Float) -> SIMD3<Float> {
        let k = coefficients(t)
        let derivative: SIMD3<Float> = k.b + (k.c * 2 + k.d * (3 * k.u)) * k.u
        return simd_length(derivative) > 1e-5 ? simd_normalize(derivative) : heading
    }

    static func up(_ t: Float) -> SIMD3<Float> {
        simd_cross(tangent(t), side)
    }

    /// 進行方向の下り角（0で水平）。
    static func slope(_ t: Float) -> Float {
        let d = tangent(t)
        return atan2(-d.y, simd_length(SIMD2(d.x, d.z)))
    }

    /// 水平位置が最も近い中心線上の点（すべり台の上にいるかの判定用）。
    static func nearest(to p: SIMD3<Float>) -> (t: Float, distance: Float) {
        var best: (Float, Float) = (0, .infinity)
        for (i, s) in samples.enumerated() {
            let d = simd_length(SIMD2(p.x - s.x, p.z - s.z))
            if d < best.1 { best = (Float(i) / Float(samples.count - 1), d) }
        }
        return best
    }

    /// 島の上面（斜めに置いた島の範囲）にあるか。
    static func onIsland(_ p: SIMD3<Float>) -> Bool {
        guard let island = meta?.island else { return p.z < -1.3 && abs(p.x) < 2.3 }
        let dx = p.x - island.center[0], dz = p.z - island.center[1]
        let c = cos(island.angle), s = sin(island.angle)
        let lx = dx * c - dz * s, lz = dx * s + dz * c
        return abs(lx) < island.half[0] * 0.92 && abs(lz) < island.half[1] * 0.92
    }
}
