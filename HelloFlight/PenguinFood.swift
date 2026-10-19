import SceneKit
import UIKit
import simd

/// キャラごとの好物。3Dモデル（ci/convert-food.py → Models/）とイラスト（Illustrations/）は同じ名前。
struct PenguinFood {
    let asset: String
    /// 問題文と読み上げでのよび方。
    let name: String
    /// 数え方（"ひき" / "こ"）と、数をたずねる言い方（"なんびき" / "なんこ"）。
    let counter: String
    let howMany: String
    /// 島に置くときの大きさ（いちばん長い辺、m）。
    let size: Float
}

extension PenguinCharacter {
    var food: PenguinFood {
        switch self {
        case .penguin: PenguinFood(asset: "bluefish", name: "おさかな", counter: "ひき", howMany: "なんびき", size: 0.25)
        case .octopus: PenguinFood(asset: "sausage", name: "ウインナー", counter: "こ", howMany: "なんこ", size: 0.22)
        case .ghost: PenguinFood(asset: "pumpkin", name: "かぼちゃ", counter: "こ", howMany: "なんこ", size: 0.22)
        case .unicorn: PenguinFood(asset: "lollipop", name: "ロリポップ", counter: "こ", howMany: "なんこ", size: 0.26)
        }
    }
}

extension PenguinCharacter {
    /// 口の位置（モデルの座標：足元が原点、正面が+z、m）。メッシュの正面の中心線から測った値。
    /// ペンギンはくちばしの先、タコとオバケは口、ユニコーンは鼻先。
    var mouth: SIMD3<Float> {
        switch self {
        case .penguin: SIMD3(0, 0.385, 0.2)
        case .octopus: SIMD3(0, 0.25, 0.28)
        case .ghost: SIMD3(0, 0.315, 0.27)
        case .unicorn: SIMD3(0, 0.42, 0.21)
        }
    }
}

/// 好物の3Dモデル。モデルは中心が原点・いちばん長い辺が1・正面が+zなので、節点の拡大率がそのまま大きさになる。
enum PenguinFoodModel {
    private static var cache: [String: SCNGeometry] = [:]

    static func geometry(_ food: PenguinFood) -> SCNGeometry? {
        if let geometry = cache[food.asset] { return geometry }
        guard let geometry = PenguinAsset.geometries(food.asset)["body"] else { return nil }
        let material = PenguinAsset.material(food.asset)
        // 影の中でもくすまないよう少し光らせる（選んだ氷の目印と同じ考え方）。
        material.emission.contents = material.diffuse.contents
        material.emission.intensity = 0.2
        geometry.firstMaterial = material
        cache[food.asset] = geometry
        return geometry
    }

    static func node(_ food: PenguinFood, size: Float) -> SCNNode {
        let node = SCNNode(geometry: geometry(food))
        node.simdScale = SIMD3(repeating: size)
        node.castsShadow = true
        return node
    }

    /// 大きさ1のときの高さの半分（地面に置くときの持ち上げ量）。
    static func halfHeight(_ food: PenguinFood) -> Float {
        guard let geometry = geometry(food) else { return 0.5 }
        let (lo, hi) = geometry.boundingBox
        return Float(hi.y - lo.y) / 2
    }
}

/// 「×N」の数のバッジ。常にカメラを向き、ほかの物に隠れないよう最前面に描く。
final class PenguinCountLabel {
    let node = SCNNode()
    private let material = SCNMaterial()
    private var shown: Int?

    init(height: Float) {
        let plane = SCNPlane(width: CGFloat(height * 2), height: CGFloat(height))
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.clear
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        plane.firstMaterial = material
        node.geometry = plane
        node.constraints = [SCNBillboardConstraint()]
        node.renderingOrder = 50
        node.castsShadow = false
    }

    func set(_ count: Int) {
        guard count != shown else { return }
        shown = count
        let image = PenguinTextures.countLabel("×\(count)")
        material.diffuse.contents = image
    }
}

/// 集めた好物（スコア）。島の右奥の空き地に好物を1つ大きく置き、横に光る「×N」を出す。
/// 正解するたびに浮き氷から1つ飛んできて、大きな好物に吸い込まれて数が増える。
final class PenguinPantry {
    /// 置き場所（島の面の高さ）。岩とすべり台を避けた平らな所の中央。
    static let spot = SIMD3<Float>(0.4, 0.6, -2.3)
    /// 置いた好物の高さ。キャラ（約0.7m）と同じくらいにする。
    static let height: Float = 0.7
    /// 好物ごとの縦横比に合わせた大きさ（いちばん長い辺）。横長の魚が広がりすぎないよう1mまで。
    private var size: Float { min(1, Self.height / (2 * PenguinFoodModel.halfHeight(food))) }

    let root = SCNNode()
    private var food: PenguinFood
    private var item = SCNNode()
    private let label = PenguinCountLabel(height: 0.42)
    private var flights: [(node: SCNNode, from: SIMD3<Float>, time: Float)] = []
    /// 着いた数（表示している数）。
    private(set) var count = 0
    private var bounce: Float = 10
    /// 浮き氷から飛んでくるときの大きさ（選んだ氷の上の目印と同じ）。
    static let flightSize: Float = 0.42
    var onLand: () -> Void = {}

    init(food: PenguinFood) {
        self.food = food
        label.node.simdPosition = Self.spot + SIMD3(0.55, Self.height + 0.15, 0.2)
        root.addChildNode(label.node)
        setFood(food)
    }

    func setFood(_ food: PenguinFood) {
        self.food = food
        item.removeFromParentNode()
        item = PenguinFoodModel.node(food, size: size)
        item.simdPosition = position
        root.addChildNode(item)
        for i in flights.indices {
            flights[i].node.removeFromParentNode()
            flights[i].node = PenguinFoodModel.node(food, size: food.size)
            root.addChildNode(flights[i].node)
        }
        refresh()
    }

    /// 大きな好物の中心。
    var position: SIMD3<Float> { Self.spot + SIMD3(0, PenguinFoodModel.halfHeight(food) * size, 0) }

    /// 1つ増やす：from から飛んできて、着いたら数が増える。
    func add(from: SIMD3<Float>) {
        let node = PenguinFoodModel.node(food, size: Self.flightSize)
        node.simdPosition = from
        root.addChildNode(node)
        flights.append((node, from, 0))
    }

    /// 画面上の点が大きな好物の近くなら、その中心。まだ1つもないときは nil。
    func item(near point: CGPoint, radius: CGFloat, project: (SIMD3<Float>) -> CGPoint?) -> SIMD3<Float>? {
        guard count > 0, let screen = project(position), hypot(screen.x - point.x, screen.y - point.y) < radius else { return nil }
        return position
    }

    var firstLanded: SIMD3<Float>? { count > 0 ? position : nil }

    /// 食べた分を1つ減らす。
    func consume() {
        guard count > 0 else { return }
        count -= 1
        bounce = 0
        refresh()
    }

    func update(_ dt: Float, time: Float) {
        for f in flights.indices {
            flights[f].time += dt
            let (node, from, t) = flights[f]
            let k = min(t / 0.7, 1)
            node.simdPosition = from + (position - from) * k + SIMD3(0, sin(k * .pi) * 0.9, 0)
            node.simdEulerAngles = SIMD3(0, (1 - k) * 2 * .pi, 0)
            node.simdScale = SIMD3(repeating: Self.flightSize * (1 - 0.4 * k))
            if k >= 1 {
                node.removeFromParentNode()
                count += 1
                bounce = 0
                refresh()
                onLand()
            }
        }
        flights.removeAll { $0.time >= 0.7 }
        // 増えたときに弾み、ふだんはゆっくり左右に揺れる。
        bounce += dt
        let squash = 1 + 0.18 * exp(-bounce * 6) * sin(bounce * 20)
        item.simdScale = SIMD3(size / squash.squareRoot(), size * squash, size / squash.squareRoot())
        item.simdEulerAngles = SIMD3(0, sin(time * 0.8) * 0.3, 0)
    }

    private func refresh() {
        item.isHidden = count == 0
        label.node.isHidden = count == 0
        label.set(count)
    }
}

/// ドラッグで食べさせる仕組み。指で運ぶ好物（コピー）、口へ入る演出、顔のアップで顔のまわりに浮かぶ好物。
final class PenguinFeeder {
    let root = SCNNode()
    private var food: PenguinFood
    /// 指で運んでいる好物。target は指の位置（なめらかに追いかける）。
    private(set) var held: SCNNode?
    private var heldTarget = SIMD3<Float>.zero
    private var heldFloat: Int?
    /// 顔のアップで浮かぶ好物。取ったら gone に時間が入り、少しして同じ場所にまた出てくる。
    private var floats: [(node: SCNNode, gone: Float?)] = []
    /// 口へ向かっている好物。
    private var bites: [(node: SCNNode, from: SIMD3<Float>, size: Float, time: Float)] = []
    private static let biteDuration: Float = 0.45
    /// 口へ飛んでいる好物があるか。
    var eating: Bool { !bites.isEmpty }
    /// 最後にかじってからの時間（もぐもぐの動き用）。
    private(set) var sinceBite: Float = 10
    var onBite: () -> Void = {}

    init(food: PenguinFood) {
        self.food = food
        label.node.isHidden = true
        root.addChildNode(label.node)
    }

    var heldPosition: SIMD3<Float>? { held?.simdPosition }
    /// 運ぶ好物と浮かぶ好物の大きさ（カメラのすぐ前に置くので、どの画面でも同じ見た目の大きさ）。
    private let heldSize: Float = 0.15

    func setFood(_ food: PenguinFood) {
        self.food = food
        let wasShown = !floats.isEmpty
        showFloats(false)
        if wasShown { showFloats(true) }
    }

    /// 顔のアップで浮かぶ好物（1つ）と、その横の光る「×N」。
    private static let floatCount = 1
    private var floatSize: Float { heldSize }
    private let label = PenguinCountLabel(height: 0.075)
    /// 集めた数が0なら浮かぶ好物も出さない。
    private var empty = false

    func showFloats(_ on: Bool) {
        floats.forEach { $0.node.removeFromParentNode() }
        floats = []
        label.node.isHidden = !on
        guard on else { return }
        for _ in 0..<Self.floatCount {
            let node = PenguinFoodModel.node(food, size: floatSize)
            node.castsShadow = false
            node.simdScale = SIMD3(repeating: 0.01)
            root.addChildNode(node)
            floats.append((node, nil))
        }
    }

    /// 画面上の点に近い、浮かんでいる好物の番号。
    func float(near point: CGPoint, radius: CGFloat, project: (SIMD3<Float>) -> CGPoint?) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (i, f) in floats.enumerated() where f.gone == nil && !empty {
            guard let screen = project(f.node.simdPosition) else { continue }
            let d = hypot(screen.x - point.x, screen.y - point.y)
            if d < radius, d < (best?.distance ?? .infinity) { best = (i, d) }
        }
        return best?.index
    }

    func floatPosition(_ index: Int) -> SIMD3<Float> { floats[index].node.simdPosition }

    /// at から好物をつまむ。浮かんでいる好物ならそれを持ち、置き場のものならコピーを持つ。
    func grab(at position: SIMD3<Float>, float index: Int?) {
        drop()
        let node = PenguinFoodModel.node(food, size: heldSize)
        node.castsShadow = false
        node.simdPosition = position
        node.renderingOrder = 40
        root.addChildNode(node)
        held = node
        heldTarget = position
        heldFloat = index
        if let index { floats[index].gone = 0 }
    }

    func move(to position: SIMD3<Float>) { heldTarget = position }

    /// 口へ運ぶ（true）か、離して消す。浮かんでいた好物は少しして元の場所にまた出てくる。
    func release(eat: Bool) {
        guard let node = held else { return }
        held = nil
        heldFloat = nil
        if eat {
            bites.append((node, node.simdPosition, node.simdScale.x, 0))
        } else {
            node.runAction(.sequence([.scale(to: 0.01, duration: 0.18), .removeFromParentNode()]))
        }
    }

    private func drop() {
        held?.removeFromParentNode()
        held = nil
    }

    func reset() {
        drop()
        bites.forEach { $0.node.removeFromParentNode() }
        bites = []
        showFloats(false)
        sinceBite = 10
    }

    /// mouth は口（食べる位置）、spots は浮かぶ好物の置き場所（画面の下の方、顔の手前）、count は集めた数。
    /// カメラから見た右・上へのずらし（ラベルを好物の横に置く）。
    var cameraRight = SIMD3<Float>(1, 0, 0), cameraUp = SIMD3<Float>(0, 1, 0)
    private func world(right: Float, up: Float) -> SIMD3<Float> { cameraRight * right + cameraUp * up }

    func update(_ dt: Float, time: Float, mouth: SIMD3<Float>, spots: [SIMD3<Float>], count: Int) {
        label.set(count)
        empty = count == 0
        label.node.isHidden = floats.isEmpty || empty
        if let spot = spots.first { label.node.simdPosition = spot + world(right: floatSize * 0.6 + 0.07, up: 0.02) }
        sinceBite += dt
        if let held {
            held.simdPosition += (heldTarget - held.simdPosition) * min(1, dt * 14)
            held.simdEulerAngles = SIMD3(sin(time * 9) * 0.15, 0, sin(time * 7) * 0.12)
        }
        for i in bites.indices {
            bites[i].time += dt
            // 放物線を描いて口へ（離れているほど高く上がる）。
            let k = min(bites[i].time / Self.biteDuration, 1)
            let arc = max(0.25, simd_distance(bites[i].from, mouth) * 0.3)
            bites[i].node.simdPosition = bites[i].from + (mouth - bites[i].from) * k + SIMD3(0, sin(k * .pi) * arc, 0)
            bites[i].node.simdEulerAngles = SIMD3(0, k * 2 * .pi, 0)
            bites[i].node.simdScale = SIMD3(repeating: bites[i].size * (1 - 0.7 * k * k))
            if k >= 1 {
                bites[i].node.removeFromParentNode()
                sinceBite = 0
                onBite()
            }
        }
        bites.removeAll { $0.time >= Self.biteDuration }
        for i in floats.indices where i < spots.count {
            let node = floats[i].node
            node.simdPosition = spots[i] + SIMD3(0, sin(time * 2 + Float(i) * 2) * 0.012, 0)
            node.simdEulerAngles = SIMD3(0, sin(time * 1.5 + Float(i)) * 0.5, 0)
            if let gone = floats[i].gone {
                // 取られている間は隠し、離されてから0.5秒でぽんと出てくる。
                let next = heldFloat == i ? 0 : gone + dt
                floats[i].gone = next > 0.5 ? nil : next
                node.isHidden = true
                node.simdScale = SIMD3(repeating: 0.01)
            } else if empty {
                node.isHidden = true
                node.simdScale = SIMD3(repeating: 0.01)
            } else {
                node.isHidden = false
                node.simdScale += (SIMD3(repeating: floatSize) - node.simdScale) * min(1, dt * 12)
            }
        }
    }
}
