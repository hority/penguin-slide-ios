import SceneKit
import UIKit
import simd

/// 遊ぶキャラ（ペンギン・タコ・オバケ・ユニコーン）。root は体の中心。
/// どれもBlenderのモデル（ci/bake-model.py → HelloFlight/Models/）で、足元が y=0、正面が +z。
/// 1枚続きの体なので、頭と左右の手（ひれ）は節点の向きを頂点シェーダーで重み付きに当てて曲げる（PenguinRig）。
/// 目・眉・口は頭の節点に載せ、目は縦につぶしてまばたきする。動きはどのキャラも共通。
final class PenguinModel {
    static let centerHeight: Float = 0.34
    let root = SCNNode()
    let body = SCNNode()
    let head = SCNNode()
    let leftFlipper = SCNNode()
    let rightFlipper = SCNNode()
    private(set) var eyes: [SCNNode] = []
    /// 体を曲げるシェーダーを持つ材質。
    private var rig: SCNMaterial?

    private let rim: String

    init(rim: String) {
        self.rim = rim
        root.addChildNode(body)
        // 遠めのカメラでも見えるよう、キャラを1.25倍にする。
        body.simdScale = SIMD3(repeating: 1.25)
        body.simdPosition = SIMD3(0, -Self.centerHeight, 0)
        build(.penguin)
    }

    /// キャラを作り直す。
    func build(_ kind: PenguinCharacter) {
        for node in [body, head, leftFlipper, rightFlipper] { node.childNodes.forEach { $0.removeFromParentNode() } }
        eyes = []
        rig = nil
        let setup = PenguinRig.setup(for: kind)
        head.simdPosition = setup.headPivot
        body.addChildNode(head)
        for (pivot, side) in [(leftFlipper, Float(-1)), (rightFlipper, Float(1))] {
            pivot.simdPosition = setup.armPivot * SIMD3(side, 1, 1)
            body.addChildNode(pivot)
        }
        guard let parts = PenguinRig.parts(for: kind) else { return }
        let material = PenguinRig.material(kind.rawValue, rim: rim)
        body.addChildNode(SCNNode(geometry: parts.body))
        parts.body.firstMaterial = material
        rig = material
        let still = material.copy() as! SCNMaterial
        still.shaderModifiers = [.fragment: rim]
        for (name, geometry) in parts.head {
            geometry.firstMaterial = still
            let node = SCNNode(geometry: geometry)
            // 部品の中心を軸にする（目はその場で縦につぶしてまばたき）。
            let (lo, hi) = geometry.boundingBox
            let center = (SIMD3<Float>(lo) + SIMD3<Float>(hi)) / 2
            node.simdPivot = PenguinRig.translation(center)
            node.simdPosition = center - setup.headPivot
            head.addChildNode(node)
            if name.hasPrefix("eye") { eyes.append(node) }
        }
        root.enumerateHierarchy { node, _ in node.castsShadow = true }
    }

    /// まばたき（0で開き、1で閉じる）。
    func setBlink(_ amount: Float) {
        for eye in eyes { eye.simdScale = SIMD3(1, max(0.08, 1 - amount), 1) }
    }

    /// 頭・手の節点の向きを体の頂点シェーダーへ渡す（毎フレーム、向きを決めたあとに呼ぶ）。
    func applyPose() {
        guard let rig else { return }
        rig.setValue(PenguinRig.pose(head.simdOrientation, around: head.simdPosition), forKey: "poseHead")
        // 手の角度は少し開いた向き（∓0.15）が基準なので、その分を差し引く。
        for (pivot, key, rest) in [(leftFlipper, "poseLeft", Float(-0.15)), (rightFlipper, "poseRight", 0.15)] {
            rig.setValue(PenguinRig.pose(simd_quatf(angle: pivot.simdEulerAngles.z - rest, axis: SIMD3(0, 0, 1)), around: pivot.simdPosition), forKey: key)
        }
    }
}

/// Blenderのモデル（リグなし）を頂点シェーダーで曲げる仕組み。キャラの頭・手、クジラの尾びれで使う。
enum PenguinRig {
    /// キャラごとの曲げ方。軸は体の座標（足元が原点、正面が+z）。armPivot は右手側（左手は x を反転）。
    struct Setup {
        let headPivot: SIMD3<Float>
        let armPivot: SIMD3<Float>
        /// 頂点の位置 → (頭の重み, 手の重み)。
        let weight: (SIMD3<Float>) -> SIMD2<Float>
    }

    static func setup(for kind: PenguinCharacter) -> Setup {
        switch kind {
        case .penguin:
            // 首は襟巻きのあたり、ひれは肩から先。
            return Setup(headPivot: SIMD3(0, 0.34, -0.01), armPivot: SIMD3(0.165, 0.28, 0)) { p in
                let head = smooth(0.29, 0.35, p.y)
                return SIMD2(head, smooth(0.175, 0.22, abs(p.x)) * (1 - head))
            }
        case .octopus:
            // 目より下で頭（ほぼ全身）を、横に上げた2本の足を付け根から先で曲げる。
            return Setup(headPivot: SIMD3(0, 0.16, 0), armPivot: SIMD3(0.22, 0.18, 0)) { p in
                let arm = smooth(0.21, 0.28, abs(p.x)) * (1 - smooth(0.26, 0.32, p.y))
                return SIMD2(smooth(0.1, 0.2, p.y) * (1 - arm), arm)
            }
        case .ghost:
            // 頭は目と口の下から。短い手は体の横に出た部分（高さ0.1〜0.28m・幅0.29mより外）だけ。
            // 裾も幅0.3mまで広がるので、高さで区切らないと裾が手と一緒にとがって動く。
            return Setup(headPivot: SIMD3(0, 0.22, 0), armPivot: SIMD3(0.29, 0.19, 0)) { p in
                let arm = smooth(0.29, 0.325, abs(p.x)) * smooth(0.09, 0.13, p.y) * (1 - smooth(0.25, 0.29, p.y))
                return SIMD2(smooth(0.16, 0.25, p.y) * (1 - arm), arm)
            }
        case .unicorn:
            // 首はたてがみの下、前足（ひづめ）は肩から先。
            return Setup(headPivot: SIMD3(0, 0.36, 0), armPivot: SIMD3(0.11, 0.31, 0.02)) { p in
                let head = smooth(0.33, 0.39, p.y)
                let arm = smooth(0.11, 0.15, abs(p.x)) * smooth(0.14, 0.2, p.y) * (1 - head)
                return SIMD2(head, arm)
            }
        }
    }

    static func translation(_ t: SIMD3<Float>) -> float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t, 1)
        return m
    }

    private static var cache: [PenguinCharacter: (body: SCNGeometry, head: [String: SCNGeometry])] = [:]

    /// "body" は重み付き、そのほか（目・眉・口）は頭に載せる部品。キャラを切り替えても作り直さない。
    static func parts(for kind: PenguinCharacter) -> (body: SCNGeometry, head: [String: SCNGeometry])? {
        if let parts = cache[kind] { return parts }
        let file = PenguinAsset.geometries(kind.rawValue)
        guard let body = file["body"] else { return nil }
        let parts = (weighted(body, setup(for: kind).weight), file.filter { $0.key != "body" })
        cache[kind] = parts
        return parts
    }

    static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 頂点色に重みを入れた複製（r: poseHead、g: x<0 なら poseLeft、x≥0 なら poseRight）。
    static func weighted(_ geometry: SCNGeometry, _ weight: (SIMD3<Float>) -> SIMD2<Float>) -> SCNGeometry {
        guard let source = geometry.sources(for: .vertex).first else { return geometry }
        let weights: [SIMD4<Float>] = source.data.withUnsafeBytes { raw in
            (0..<source.vectorCount).map { i in
                let at = i * source.dataStride
                let w = weight(SIMD3(raw.loadUnaligned(fromByteOffset: at, as: Float.self), raw.loadUnaligned(fromByteOffset: at + 4, as: Float.self),
                                     raw.loadUnaligned(fromByteOffset: at + 8, as: Float.self)))
                return SIMD4(w.x, w.y, 0, 1)
            }
        }
        let color = SCNGeometrySource(data: weights.withUnsafeBytes { Data($0) }, semantic: .color, vectorCount: weights.count, usesFloatComponents: true,
                                      componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        return SCNGeometry(sources: geometry.sources + [color], elements: geometry.elements)
    }

    /// 軸 pivot まわりに回す姿勢（シェーダーの poseHead などへ渡す値）。
    static func pose(_ rotation: simd_quatf, around pivot: SIMD3<Float>) -> NSValue {
        NSValue(scnMatrix4: SCNMatrix4(translation(pivot) * float4x4(rotation) * translation(-pivot)))
    }

    static let poseModifier = """
    #pragma arguments
    float4x4 poseHead;
    float4x4 poseLeft;
    float4x4 poseRight;
    #pragma body
    float4 rigWeight = _geometry.color;
    _geometry.color = float4(1.0);
    float4x4 poseFlipper = _geometry.position.x < 0.0 ? poseLeft : poseRight;
    float rigRest = 1.0 - rigWeight.r - rigWeight.g;
    float4 rigP = _geometry.position;
    _geometry.position = rigP * rigRest + (poseHead * rigP) * rigWeight.r + (poseFlipper * rigP) * rigWeight.g;
    float4 rigN = float4(_geometry.normal, 0.0);
    _geometry.normal = normalize((rigN * rigRest + (poseHead * rigN) * rigWeight.r + (poseFlipper * rigN) * rigWeight.g).xyz);
    """

    /// 曲げるシェーダー付きの材質。
    static func material(_ name: String, rim: String? = nil) -> SCNMaterial {
        let material = PenguinAsset.material(name)
        material.shaderModifiers = rim.map { [.geometry: poseModifier, .fragment: $0] } ?? [.geometry: poseModifier]
        let identity = NSValue(scnMatrix4: SCNMatrix4Identity)
        for key in ["poseHead", "poseLeft", "poseRight"] { material.setValue(identity, forKey: key) }
        return material
    }
}

/// 浮き氷と、答えを書いた看板。
struct PenguinFloe {
    let root: SCNNode
    let ice: SCNNode
    let board: SCNNode
    let face: SCNMaterial
    let home: SIMD3<Float>
    /// 選べる氷を示す水際の光る輪。
    let ring: SCNNode
    let ringMaterial: SCNMaterial
    /// 文字面の横÷縦（テクスチャをこの比で描く）。
    let faceAspect: CGFloat

    var top: SIMD3<Float> { root.simdWorldPosition + SIMD3(0, 0.11, 0) }
}

/// HD-2D風ジオラマのシーン構築。テクスチャはすべて手続き生成。
final class PenguinWorld {
    static let sunDirection = simd_normalize(SIMD3<Float>(0.55, -0.62, -0.35))
    /// 3歳でも押し分けやすいよう、左右と手前中央に大きく離して置く。
    static let floeHomes: [SIMD3<Float>] = [SIMD3(-0.95, 0, 0.35), SIMD3(0, 0, 1.25), SIMD3(0.95, 0, 0.35)]
    /// 遊ぶときのカメラのおおよその奥行き位置（看板をこちらへ向ける）。
    static let cameraRestZ: Float = 8.3
    static let background = PenguinTextures.color(PenguinTextures.horizon)

    let scene = SCNScene()
    let camera = SCNCamera()
    let cameraNode = SCNNode()
    let sunNode = SCNNode()
    let penguin: PenguinModel
    let contactShadow = SCNNode()
    private(set) var floes: [PenguinFloe] = []
    private(set) var aoMaterials: [SCNMaterial] = []
    private(set) var occluders: [(node: SCNNode, center: SIMD3<Float>, radius: Float)] = []
    private(set) var chunks: [SCNNode] = []
    /// ステージ（島・すべり台・浮き氷・看板）。1枚のアトラスを共有する1つの材質で描く。
    private let stage = PenguinStageData.shared.geometries
    private lazy var stageMaterial: SCNMaterial = {
        let material = PenguinStageData.makeMaterial(ao: Self.aoModifier)
        aoMaterials.append(material)
        return material
    }()
    /// 選んだ氷の上でくるくる回る目印（キャラの好物）。
    let marker = SCNNode()
    private(set) var markerFood = SCNNode()
    let waterMaterial = SCNMaterial()
    let sparkleTemplate = SCNParticleSystem()
    let splashTemplate = SCNParticleSystem()
    let heartTemplate = SCNParticleSystem()


    init() {
        penguin = PenguinModel(rim: Self.rimModifier)
        for geometry in stage.values { geometry.firstMaterial = stageMaterial }
        buildEnvironment()
        buildDiorama()
        buildFloes()
        buildAtmosphere()
        scene.rootNode.addChildNode(penguin.root)
        buildContactShadow()
        buildMarker()
        // 小物の分割数を抑えて頂点数を減らす（見た目に差が出ない範囲）。
        scene.rootNode.enumerateHierarchy { node, _ in
            if let sphere = node.geometry as? SCNSphere, sphere.segmentCount > 32 { sphere.segmentCount = 32 }
            if let cylinder = node.geometry as? SCNCylinder, cylinder.radialSegmentCount > 28 { cylinder.radialSegmentCount = 28 }
        }
    }

    // MARK: - Shader modifiers

    /// キャラクターのリムライト（控えめな暖色）。
    static let rimModifier = """
    float rimF = pow(1.0 - saturate(dot(_surface.normal, _surface.view)), 2.4);
    _output.color.rgb += float3(0.3, 0.21, 0.12) * rimF;
    """

    /// 接地感のための擬似AO。キャラの体・足先との距離で暗くする。
    static let aoModifier = """
    #pragma arguments
    float4 aoBody;
    float4 aoFeet;
    #pragma body
    float3 aoWp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float aoValue = 1.0;
    float bodyDist = max(distance(aoWp, aoBody.xyz) - aoBody.w, 0.0);
    aoValue *= 1.0 - 0.5 * exp(-bodyDist * 7.0);
    float feetDist = max(distance(aoWp, aoFeet.xyz) - aoFeet.w, 0.0);
    aoValue *= 1.0 - 0.45 * exp(-feetDist * 14.0);
    _surface.diffuse.rgb *= aoValue;
    """

    /// 発光物：1を超える明るさの発光でブルームをにじませる。
    static func glowMaterial(_ color: UIColor, gain: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.black
        material.emission.contents = color
        material.emission.intensity = gain
        return material
    }

    private func node(_ geometry: SCNGeometry, _ material: SCNMaterial, at position: SIMD3<Float>, parent: SCNNode? = nil) -> SCNNode {
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.simdPosition = position
        (parent ?? scene.rootNode).addChildNode(node)
        return node
    }

    // MARK: - Light, environment, camera

    private func buildEnvironment() {
        // 無限遠の背景：空のグラデーションを背景と環境光に使い、遠くの海はフォグで地平線の色へ溶かす。
        let sky = PenguinTextures.sky()
        scene.background.contents = sky
        scene.lightingEnvironment.contents = sky
        scene.lightingEnvironment.intensity = 0.7
        scene.fogColor = Self.background
        scene.fogStartDistance = 9
        scene.fogEndDistance = 40
        scene.fogDensityExponent = 1.3

        let sun = SCNLight()
        sun.type = .directional
        sun.color = PenguinTextures.color(0xffd9a6)
        sun.intensity = 1000
        sun.castsShadow = true
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowSampleCount = 8
        sun.shadowRadius = 2.5
        sun.shadowMode = .forward
        sun.shadowColor = UIColor(red: 0.02, green: 0.05, blue: 0.12, alpha: 0.72)
        // 影の範囲はSceneKitに視錐台へ合わせさせる（範囲外が黒くならない）。
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 18
        sunNode.light = sun
        sunNode.simdLook(at: Self.sunDirection)
        scene.rootNode.addChildNode(sunNode)

        // 半球光の代わりに、寒色の弱い環境光で影を青く持ち上げる。
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = PenguinTextures.color(0x9fb6e0)
        ambient.intensity = 150
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        camera.fieldOfView = 38
        camera.zNear = 0.5
        camera.zFar = 160
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // SceneKit標準のポスト処理：HDR（フィルミックトーンマップ＋sRGB）、ブルーム、周辺減光。
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0
        camera.bloomIntensity = 0.5
        camera.bloomThreshold = 0.9
        camera.bloomBlurRadius = 8
        camera.vignettingIntensity = 0.6
        camera.vignettingPower = 0.8
        camera.saturation = 1.05
        // ミニチュア感の被写界深度。焦点距離は毎フレーム主役に合わせる。
        camera.fStop = 0.2
        camera.apertureBladeCount = 6
        camera.focalBlurSampleCount = 8
        setDepthOfField(true)
    }

    func setDepthOfField(_ enabled: Bool) {
        guard camera.wantsDepthOfField != enabled else { return }
        camera.wantsDepthOfField = enabled
    }

    // MARK: - Diorama

    private func buildDiorama() {
        // 海：地平線まで続く大きな面。端はフォグで空の色に溶ける。
        let water = SCNPlane(width: 160, height: 160)
        waterMaterial.lightingModel = .physicallyBased
        waterMaterial.diffuse.contents = PenguinTextures.color(0x1c5670)
        waterMaterial.roughness.contents = 0.08
        waterMaterial.metalness.contents = 0.0
        waterMaterial.normal.contents = PenguinTextures.normalMap(from: PenguinTextures.waterNormal(), strength: 6)
        waterMaterial.normal.intensity = 0.7
        waterMaterial.normal.wrapS = .repeat
        waterMaterial.normal.wrapT = .repeat
        waterMaterial.normal.contentsTransform = SCNMatrix4MakeScale(160, 160, 1)
        waterMaterial.normal.mipFilter = .linear
        let waterNode = node(water, waterMaterial, at: SIMD3(0, 0, -20))
        waterNode.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        waterNode.castsShadow = false

        // 島・すべり台・台・はしご：テクスチャ付きステージを省メッシュ化した1つのメッシュ。
        if let island = stage["island"] {
            let islandNode = SCNNode(geometry: island)
            islandNode.castsShadow = true
            scene.rootNode.addChildNode(islandNode)
        }

        // 遠くの氷山。上から見ても板に見えないよう、とがった峰を2〜3個寄せた形にする。
        // ぼけとフォグで奥行きを出す（法線マップなしの軽い材質）。
        let snowTop = SCNMaterial()
        snowTop.lightingModel = .physicallyBased
        snowTop.diffuse.contents = PenguinTextures.color(0xf2f7fa)
        snowTop.roughness.contents = 0.55
        let bergs: [(SIMD3<Float>, Float)] = [
            (SIMD3(-7, 0, -14), 1.3), (SIMD3(5, 0, -18), 1.7), (SIMD3(13, 0, -26), 2.4),
            (SIMD3(-15, 0, -30), 2.6), (SIMD3(-4, 0, -36), 1.6), (SIMD3(9, 0, -9), 0.8),
            (SIMD3(-9, 0, -4), 0.8), (SIMD3(7, 0, 3), 0.6), (SIMD3(-6, 0, 5), 0.5),
        ]
        for (position, size) in bergs {
            let cluster = SCNNode()
            cluster.simdPosition = position
            cluster.simdEulerAngles = SIMD3(0, .random(in: 0...6), 0)
            scene.rootNode.addChildNode(cluster)
            let peaks: [(SIMD3<Float>, Float, Float)] = [(SIMD3(0, 0, 0), 1.0, 1.8), (SIMD3(0.7, 0, 0.3), 0.7, 1.1), (SIMD3(-0.5, 0, 0.5), 0.6, 0.8)]
            for (offset, radius, height) in peaks {
                let peak = SCNCone(topRadius: 0, bottomRadius: CGFloat(radius * size), height: CGFloat(height * size))
                peak.radialSegmentCount = 6
                peak.firstMaterial = snowTop
                let node = SCNNode(geometry: peak)
                node.simdPosition = offset * size + SIMD3(0, height * size / 2 - 0.15, 0)
                node.simdEulerAngles = SIMD3(.random(in: -0.12...0.12), .random(in: 0...6), .random(in: -0.12...0.12))
                node.castsShadow = false
                cluster.addChildNode(node)
            }
        }
    }

    // MARK: - Floes and signs

    private func buildFloes() {
        let info = PenguinStageData.shared.meta?.floe
        for (index, home) in Self.floeHomes.enumerated() {
            let root = SCNNode()
            root.simdPosition = home
            scene.rootNode.addChildNode(root)
            // 浮き氷：3つとも同じ氷を使い、向きだけ変えて見た目を散らす。
            let ice = SCNNode(geometry: stage["floe"])
            ice.castsShadow = true
            ice.simdEulerAngles = SIMD3(0, Float(index) * 2.1, 0)
            root.addChildNode(ice)

            // 看板：柱ごと弾ませるので別の節点にする。正面の文字面だけ問題ごとのテクスチャを貼る平面。
            let boardNode = SCNNode(geometry: stage["board"])
            boardNode.castsShadow = true
            boardNode.simdPosition = info.map { SIMD3($0.board[0], $0.board[1], $0.board[2]) } ?? SIMD3(0, 0.6, 0)
            // 文字面を正面のカメラへ向け、見下ろす角度に合わせて少し上向きに傾ける。
            let toCamera = SIMD2<Float>(-home.x, Self.cameraRestZ - home.z)
            boardNode.simdEulerAngles = SIMD3(-0.26, atan2(toCamera.x, toCamera.y), 0)
            root.addChildNode(boardNode)
            let face = SCNMaterial()
            face.lightingModel = .physicallyBased
            face.roughness.contents = 0.6
            face.metalness.contents = 0.0
            // 影の中でも白地がくすまないよう、発光を少し足す（ブルームのしきい値は超えない程度）。
            face.emission.intensity = 0.4
            let size = info?.face.size ?? [0.5, 0.45]
            let facePlane = SCNPlane(width: CGFloat(size[0]), height: CGFloat(size[1]))
            facePlane.cornerRadius = CGFloat(min(size[0], size[1]) * 0.08)
            facePlane.firstMaterial = face
            let faceNode = SCNNode(geometry: facePlane)
            if let f = info?.face {
                faceNode.simdPosition = SIMD3(f.center[0], f.center[1], f.center[2])
                faceNode.simdOrientation = simd_quatf(from: SIMD3(0, 0, 1), to: simd_normalize(SIMD3(f.normal[0], f.normal[1], f.normal[2])))
            } else {
                faceNode.simdPosition = SIMD3(0, 0, 0.06)
            }
            boardNode.addChildNode(faceNode)

            let ringMaterial = SCNMaterial()
            ringMaterial.lightingModel = .constant
            ringMaterial.diffuse.contents = UIColor.black
            ringMaterial.emission.contents = UIColor.white
            ringMaterial.blendMode = .add
            ringMaterial.writesToDepthBuffer = false
            let ringRadius = CGFloat((info?.radius ?? 0.42) + 0.08)
            let ring = node(SCNTorus(ringRadius: ringRadius, pipeRadius: 0.035), ringMaterial, at: SIMD3(0, 0.04, 0), parent: root)
            ring.castsShadow = false
            ring.isHidden = true
            floes.append(PenguinFloe(root: root, ice: ice, board: boardNode, face: face, home: home, ring: ring, ringMaterial: ringMaterial,
                                     faceAspect: CGFloat(size[0] / max(size[1], 0.01))))
        }
        // 小さな氷のかけら。
        for p: SIMD3<Float> in [SIMD3(-1.45, 0, 0.1), SIMD3(1.5, 0, 1.2), SIMD3(-1.1, 0, 1.7), SIMD3(1.2, 0, -0.5)] {
            let chunk = node(SCNBox(width: 0.22, height: 0.08, length: 0.16, chamferRadius: 0.03), chunkMaterial, at: p)
            chunk.simdEulerAngles = SIMD3(0, .random(in: 0...3), 0)
            chunks.append(chunk)
        }
    }

    private lazy var chunkMaterial: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = PenguinTextures.color(0x9fdcec)
        material.roughness.contents = 0.25
        return material
    }()

    func setSign(_ index: Int, text: String, dots: Int, highlight: Bool) {
        let image = PenguinTextures.sign(text, dots: dots, highlight: highlight, aspect: floes[index].faceAspect)
        floes[index].face.diffuse.contents = image
        floes[index].face.emission.contents = image
    }

    // MARK: - Atmosphere

    private func buildAtmosphere() {
        // 光の筋：加算合成の角柱。縞はシェーダでゆっくり流す。
        let shaftImage = PenguinTextures.lightShaft()
        for (target, width) in [(SIMD3<Float>(0.75, 0.55, -2.3), CGFloat(0.35))] {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = shaftImage
            material.blendMode = .add
            material.writesToDepthBuffer = false
            material.isDoubleSided = true
            material.shaderModifiers = [.fragment: """
            float2 shaftUv = _surface.diffuseTexcoord;
            float stripes = 0.72 + 0.28 * sin(shaftUv.x * 38.0 + shaftUv.y * 7.0 + scn_frame.time * 0.5);
            _output.color = float4(_surface.diffuse.rgb * float3(1.0, 0.8, 0.55) * 0.18 * stripes, 1.0);
            """]
            let shaft = node(SCNBox(width: width, height: 4.2, length: width, chamferRadius: 0), material, at: target - Self.sunDirection * 2.1)
            shaft.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: -Self.sunDirection)
            shaft.castsShadow = false
            shaft.renderingOrder = 20
        }

        // 漂う光の粒（約270個）。
        let dust = SCNParticleSystem()
        dust.emitterShape = SCNBox(width: 4.2, height: 2.4, length: 5.5, chamferRadius: 0)
        dust.birthLocation = .volume
        dust.birthRate = 35
        dust.particleLifeSpan = 6
        dust.particleLifeSpanVariation = 2
        dust.warmupDuration = 6
        dust.particleVelocity = 0.05
        dust.particleVelocityVariation = 0.05
        dust.spreadingAngle = 180
        dust.acceleration = SCNVector3(0.02, 0.012, 0)
        dust.particleSize = 0.02
        dust.particleSizeVariation = 0.012
        dust.particleColor = UIColor(red: 1, green: 0.92, blue: 0.75, alpha: 1)
        dust.particleImage = PenguinTextures.softDot()
        dust.blendMode = .additive
        dust.isLightingEnabled = false
        let twinkle = CAKeyframeAnimation()
        twinkle.values = [0, 0.9, 0.3, 1.0, 0]
        twinkle.keyTimes = [0, 0.2, 0.5, 0.75, 1]
        dust.propertyControllers = [.opacity: SCNParticlePropertyController(animation: twinkle)]
        let dustNode = SCNNode()
        dustNode.simdPosition = SIMD3(0, 1.3, -1.2)
        dustNode.addParticleSystem(dust)
        scene.rootNode.addChildNode(dustNode)

        sparkleTemplate.loops = false
        sparkleTemplate.birthRate = 320
        sparkleTemplate.emissionDuration = 0.08
        sparkleTemplate.particleLifeSpan = 1.1
        sparkleTemplate.particleLifeSpanVariation = 0.3
        sparkleTemplate.particleVelocity = 1.5
        sparkleTemplate.particleVelocityVariation = 0.6
        sparkleTemplate.emittingDirection = SCNVector3(0, 1, 0)
        sparkleTemplate.spreadingAngle = 55
        sparkleTemplate.acceleration = SCNVector3(0, -3, 0)
        sparkleTemplate.particleSize = 0.055
        sparkleTemplate.particleSizeVariation = 0.025
        sparkleTemplate.particleAngularVelocity = 180
        sparkleTemplate.particleAngularVelocityVariation = 180
        sparkleTemplate.particleColor = UIColor(red: 1, green: 0.8, blue: 0.35, alpha: 1)
        sparkleTemplate.particleColorVariation = SCNVector4(180, 0.3, 0.1, 0)
        sparkleTemplate.particleImage = PenguinTextures.star()
        sparkleTemplate.blendMode = .additive
        sparkleTemplate.isLightingEnabled = false

        splashTemplate.loops = false
        splashTemplate.birthRate = 420
        splashTemplate.emissionDuration = 0.06
        splashTemplate.particleLifeSpan = 0.8
        splashTemplate.particleLifeSpanVariation = 0.2
        splashTemplate.particleVelocity = 1.7
        splashTemplate.particleVelocityVariation = 0.6
        splashTemplate.emittingDirection = SCNVector3(0, 1, 0)
        splashTemplate.spreadingAngle = 35
        splashTemplate.acceleration = SCNVector3(0, -6, 0)
        splashTemplate.particleSize = 0.035
        splashTemplate.particleSizeVariation = 0.015
        splashTemplate.particleColor = UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.9)
        splashTemplate.particleImage = PenguinTextures.softDot()
        splashTemplate.blendMode = .alpha
        splashTemplate.isLightingEnabled = false

        // 食べたときに口元からふわっと上がるハート。
        heartTemplate.loops = false
        heartTemplate.birthRate = 60
        heartTemplate.emissionDuration = 0.1
        heartTemplate.particleLifeSpan = 1.2
        heartTemplate.particleLifeSpanVariation = 0.3
        heartTemplate.particleVelocity = 0.45
        heartTemplate.particleVelocityVariation = 0.2
        heartTemplate.emittingDirection = SCNVector3(0, 1, 0)
        heartTemplate.spreadingAngle = 60
        heartTemplate.acceleration = SCNVector3(0, 0.25, 0)
        heartTemplate.particleSize = 0.045
        heartTemplate.particleSizeVariation = 0.015
        heartTemplate.particleColor = UIColor(red: 1, green: 0.45, blue: 0.6, alpha: 1)
        heartTemplate.particleImage = PenguinTextures.heart()
        heartTemplate.blendMode = .alpha
        heartTemplate.isLightingEnabled = false
        let fade = CAKeyframeAnimation()
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.15, 0.7, 1]
        heartTemplate.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
    }

    func burst(_ template: SCNParticleSystem, at position: SIMD3<Float>, scale: Float = 1) {
        guard let system = template.copy() as? SCNParticleSystem else { return }
        system.birthRate *= CGFloat(scale)
        system.particleVelocity *= CGFloat(sqrt(scale))
        scene.addParticleSystem(system, transform: SCNMatrix4MakeTranslation(position.x, position.y, position.z))
    }

    // MARK: - Selection marker

    private func buildMarker() {
        marker.renderingOrder = 30
        marker.isHidden = true
        scene.rootNode.addChildNode(marker)
    }

    /// 目印をキャラの好物にする。縦軸まわりにくるくる回す。
    func setMarker(_ food: PenguinFood) {
        markerFood.removeFromParentNode()
        markerFood = PenguinFoodModel.node(food, size: 0.42)
        markerFood.castsShadow = false
        marker.addChildNode(markerFood)
    }

    // MARK: - Contact shadow

    private func buildContactShadow() {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = PenguinTextures.contactShadow()
        material.writesToDepthBuffer = false
        let plane = SCNNode(geometry: SCNPlane(width: 0.6, height: 0.6))
        plane.geometry?.firstMaterial = material
        plane.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        plane.castsShadow = false
        plane.renderingOrder = 10
        contactShadow.addChildNode(plane)
        scene.rootNode.addChildNode(contactShadow)
    }

    /// 足元の地面の高さと法線。
    func ground(below p: SIMD3<Float>) -> (height: Float, normal: SIMD3<Float>)? {
        let onSlide = PenguinTrack.nearest(to: p)
        if onSlide.distance < 0.3, onSlide.t > 0, onSlide.t < 1 {
            return (PenguinTrack.point(onSlide.t).y + 0.01, PenguinTrack.up(onSlide.t))
        }
        if simd_length(SIMD2(p.x - PenguinTrack.stand.x, p.z - PenguinTrack.stand.z)) < 0.4 { return (PenguinTrack.platformY, SIMD3(0, 1, 0)) }
        if PenguinTrack.onIsland(p) { return (PenguinTrack.plateauTop, SIMD3(0, 1, 0)) }
        for floe in floes {
            let top = floe.top
            if simd_length(SIMD2(p.x - top.x, p.z - top.z)) < 0.42 { return (top.y + 0.005, SIMD3(0, 1, 0)) }
        }
        return nil
    }
}
