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

/// 島の右奥の空き地に並ぶ、集めた好物（スコア）。正解するたびに浮き氷から1つ飛んできて並ぶ。
final class PenguinPantry {
    /// 置き場所（島の面の高さ）。中央から外へ順に埋まる。岩とすべり台を避けた平らな所。
    static let slots: [SIMD3<Float>] = [
        SIMD3(0.41, 0.569, -2.30), SIMD3(0.64, 0.563, -2.30), SIMD3(0.18, 0.574, -2.30), SIMD3(0.52, 0.552, -2.09),
        SIMD3(0.52, 0.575, -2.51), SIMD3(0.29, 0.557, -2.09), SIMD3(0.29, 0.584, -2.51), SIMD3(0.75, 0.545, -2.09),
        SIMD3(0.75, 0.560, -2.51), SIMD3(0.06, 0.559, -2.09), SIMD3(0.06, 0.591, -2.51), SIMD3(0.87, 0.546, -2.30),
        SIMD3(-0.05, 0.576, -2.30), SIMD3(0.41, 0.576, -2.72), SIMD3(0.64, 0.565, -2.72), SIMD3(0.18, 0.587, -2.72),
        SIMD3(0.98, 0.535, -2.09), SIMD3(0.98, 0.544, -2.51), SIMD3(0.87, 0.550, -2.72), SIMD3(-0.05, 0.602, -2.72),
    ]

    let root = SCNNode()
    private var food: PenguinFood
    /// 置いてある好物（着いたものだけ見える）。
    private var items: [(node: SCNNode, landed: Bool)] = []
    private var flights: [(index: Int, from: SIMD3<Float>, time: Float)] = []
    /// 置き場がいっぱいになったら上に数を出す。
    private let badge = SCNNode()
    private(set) var count = 0
    var onLand: () -> Void = {}

    init(food: PenguinFood) {
        self.food = food
        let plane = SCNPlane(width: 0.5, height: 0.32)
        let material = SCNMaterial()
        material.lightingModel = .constant
        plane.firstMaterial = material
        badge.geometry = plane
        badge.constraints = [SCNBillboardConstraint()]
        badge.simdPosition = SIMD3(0.45, 1.05, -2.4)
        badge.isHidden = true
        root.addChildNode(badge)
    }

    func setFood(_ food: PenguinFood) {
        self.food = food
        for (i, item) in items.enumerated() {
            item.node.removeFromParentNode()
            items[i].node = makeItem(i)
            items[i].node.isHidden = !item.landed
        }
    }

    /// 1つ増やす。置き場に空きがあれば from から飛んでくる。
    func add(from: SIMD3<Float>) {
        count += 1
        if items.count < Self.slots.count {
            let index = items.count
            let node = makeItem(index)
            node.isHidden = true
            items.append((node, false))
            flights.append((index, from, 0))
        } else {
            updateBadge()
        }
    }

    /// 置いた好物の中心。
    func position(_ index: Int) -> SIMD3<Float> {
        Self.slots[index] + SIMD3(0, PenguinFoodModel.halfHeight(food) * food.size, 0)
    }

    /// 画面上の点にいちばん近い、置いてある好物の中心。
    func item(near point: CGPoint, radius: CGFloat, project: (SIMD3<Float>) -> CGPoint?) -> SIMD3<Float>? {
        var best: (position: SIMD3<Float>, distance: CGFloat)?
        for (i, item) in items.enumerated() where item.landed {
            guard let screen = project(position(i)) else { continue }
            let d = hypot(screen.x - point.x, screen.y - point.y)
            if d < radius, d < (best?.distance ?? .infinity) { best = (position(i), d) }
        }
        return best?.position
    }

    var firstLanded: SIMD3<Float>? { items.firstIndex { $0.landed }.map(position) }

    func update(_ dt: Float) {
        for f in flights.indices {
            flights[f].time += dt
            let (index, from, time) = flights[f]
            let node = items[index].node
            let k = min(time / 0.7, 1)
            let to = position(index)
            node.isHidden = false
            node.simdPosition = from + (to - from) * k + SIMD3(0, sin(k * .pi) * 0.9, 0)
            node.simdEulerAngles = SIMD3(0, Self.yaw(index) + (1 - k) * 2 * .pi, 0)
            node.simdScale = SIMD3(repeating: food.size * (0.6 + 0.4 * k))
            if k >= 1 {
                items[index].landed = true
                onLand()
            }
        }
        flights.removeAll { $0.time >= 0.7 }
    }

    private func makeItem(_ index: Int) -> SCNNode {
        let node = PenguinFoodModel.node(food, size: food.size)
        node.simdPosition = position(index)
        node.simdEulerAngles = SIMD3(0, Self.yaw(index), 0)
        root.addChildNode(node)
        return node
    }

    /// 正面（カメラ側）を向いたまま、少しずつ向きを散らす。
    private static func yaw(_ index: Int) -> Float { sin(Float(index) * 2.4) * 0.45 }

    private func updateBadge() {
        badge.isHidden = count <= Self.slots.count
        let image = PenguinTextures.sign("×\(count)", dots: 0, highlight: true, aspect: 1.6)
        badge.geometry?.firstMaterial?.diffuse.contents = image
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
    /// 最後にかじってからの時間（もぐもぐの動き用）。
    private(set) var sinceBite: Float = 10
    var onBite: () -> Void = {}

    init(food: PenguinFood) {
        self.food = food
    }

    var heldPosition: SIMD3<Float>? { held?.simdPosition }
    /// 運ぶ好物の大きさ。顔のアップではカメラが近いので小さめにする。
    var closeUp = false
    private var heldSize: Float { food.size * (closeUp ? 0.55 : 1.25) }

    func setFood(_ food: PenguinFood) {
        self.food = food
        let wasShown = !floats.isEmpty
        showFloats(false)
        if wasShown { showFloats(true) }
    }

    /// 顔のアップで浮かぶ好物の数と大きさ。
    private static let floatCount = 3
    private var floatSize: Float { food.size * 0.5 }

    func showFloats(_ on: Bool) {
        floats.forEach { $0.node.removeFromParentNode() }
        floats = []
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
        for (i, f) in floats.enumerated() where f.gone == nil {
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

    /// mouth は口（食べる位置）、spots は浮かぶ好物の置き場所（画面の下の方、顔の手前）。
    func update(_ dt: Float, time: Float, mouth: SIMD3<Float>, spots: [SIMD3<Float>]) {
        sinceBite += dt
        if let held {
            held.simdPosition += (heldTarget - held.simdPosition) * min(1, dt * 14)
            held.simdEulerAngles = SIMD3(sin(time * 9) * 0.15, 0, sin(time * 7) * 0.12)
        }
        for i in bites.indices {
            bites[i].time += dt
            let k = min(bites[i].time / 0.22, 1)
            bites[i].node.simdPosition = bites[i].from + (mouth - bites[i].from) * k
            bites[i].node.simdScale = SIMD3(repeating: bites[i].size * (1 - 0.85 * k))
            if k >= 1 {
                bites[i].node.removeFromParentNode()
                sinceBite = 0
                onBite()
            }
        }
        bites.removeAll { $0.time >= 0.22 }
        for i in floats.indices where i < spots.count {
            let node = floats[i].node
            node.simdPosition = spots[i] + SIMD3(0, sin(time * 2 + Float(i) * 2) * 0.012, 0)
            node.simdEulerAngles = SIMD3(0, sin(time * 1.5 + Float(i)) * 0.5, 0)
            if let gone = floats[i].gone {
                // 取られている間は隠し、離されてから0.5秒でぽんと出てくる。
                let next = heldFloat == i ? 0 : gone + dt
                floats[i].gone = next > 0.5 ? nil : next
                node.simdScale = SIMD3(repeating: 0.01)
            } else {
                node.simdScale += (SIMD3(repeating: floatSize) - node.simdScale) * min(1, dt * 12)
            }
        }
    }
}
