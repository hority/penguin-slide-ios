import SceneKit
import UIKit
import simd

/// たまに出てくる海の生き物（クジラ・イルカ・トビウオ）。
/// Blenderのモデル（ci/bake-model.py → HelloFlight/Models/）を1組だけ置き、出番のたびに使い回す。
final class PenguinCritters {
    enum Kind: CaseIterable { case whale, dolphins, flyingFish }

    private let world: PenguinWorld
    private let audio: PenguinAudio
    private let whale = SCNNode()
    /// クジラの尾びれを曲げるシェーダーの材質。
    private let whaleMaterial = PenguinRig.material("whale")
    private static let tailPivot = SIMD3<Float>(0, 0, -0.75)
    private let dolphins = [SCNNode(), SCNNode()]
    private let fishes = [SCNNode(), SCNNode(), SCNNode()]
    private let spray = SCNParticleSystem()
    private var active: Kind?
    private var time: Float = 0
    private var origin = SIMD3<Float>.zero
    private var direction: Float = 1
    private var fired = Set<Int>()

    var busy: Bool { active != nil }

    init(world: PenguinWorld, audio: PenguinAudio) {
        self.world = world
        self.audio = audio
        if let body = PenguinAsset.geometries("whale")["body"] {
            // 尾びれ：胴の後ろ半分から先を、尾の付け根まわりに曲げる。
            whale.geometry = PenguinRig.weighted(body) { p in SIMD2(PenguinRig.smooth(-0.55, -1.2, p.z), 0) }
            whale.geometry?.firstMaterial = whaleMaterial
        }
        let dolphin = PenguinAsset.geometries("dolphin")["body"], fish = PenguinAsset.geometries("flyingfish")["body"]
        dolphin?.firstMaterial = PenguinAsset.material("dolphin")
        fish?.firstMaterial = PenguinAsset.material("flyingfish")
        for node in dolphins { node.geometry = dolphin }
        for node in fishes { node.geometry = fish }
        for node in [whale] + dolphins + fishes {
            node.isHidden = true
            node.castsShadow = false
            world.scene.rootNode.addChildNode(node)
        }
        spray.loops = false
        spray.birthRate = 700
        spray.emissionDuration = 0.35
        spray.particleLifeSpan = 1.1
        spray.particleVelocity = 3.2
        spray.particleVelocityVariation = 0.8
        spray.emittingDirection = SCNVector3(0, 1, 0)
        spray.spreadingAngle = 14
        spray.acceleration = SCNVector3(0, -4, 0)
        spray.particleSize = 0.07
        spray.particleSizeVariation = 0.03
        spray.particleColor = UIColor(red: 0.92, green: 0.97, blue: 1, alpha: 0.9)
        spray.particleImage = PenguinTextures.softDot()
        spray.isLightingEnabled = false
    }

    func play(_ kind: Kind? = nil) {
        guard active == nil else { return }
        let kind = kind ?? Kind.allCases.randomElement() ?? .dolphins
        active = kind
        time = 0
        fired = []
        direction = Bool.random() ? 1 : -1
        switch kind {
        case .whale:
            origin = SIMD3(.random(in: -0.6...0.9), 0, -7.5)
            whale.isHidden = false
        case .dolphins:
            dolphins.forEach { $0.isHidden = false }
        case .flyingFish:
            fishes.forEach { $0.isHidden = false }
        }
    }

    func update(_ dt: Float) {
        guard let kind = active else { return }
        time += dt
        switch kind {
        case .whale: updateWhale()
        case .dolphins: updateDolphins()
        case .flyingFish: updateFlyingFish()
        }
    }

    private func finish() {
        for node in [whale] + dolphins + fishes { node.isHidden = true }
        active = nil
    }

    /// 1回だけ実行する（しぶき・音のタイミング用）。
    private func once(_ key: Int, _ action: () -> Void) {
        guard !fired.contains(key) else { return }
        fired.insert(key)
        action()
    }

    // MARK: - Whale

    /// 島の奥でゆっくり浮かび、潮を吹いて、尾びれを上げて潜る。
    private func updateWhale() {
        let duration: Float = 7
        let s = time / duration
        var y: Float, pitch: Float, tail: Float = 0
        if s < 0.25 {
            let k = smooth(s / 0.25)
            y = -1.9 + 1.5 * k
            pitch = -0.25 * (1 - k)
        } else if s < 0.6 {
            y = -0.4 + sin(time * 2) * 0.04
            pitch = 0
        } else {
            let k = smooth(min((s - 0.6) / 0.4, 1))
            y = -0.4 - 1.7 * k
            pitch = 0.55 * k
            tail = 0.6 * sin(k * .pi)
        }
        let position = origin + SIMD3(direction * 0.3 * time, y, 0)
        whale.simdPosition = position
        whale.simdOrientation = simd_quatf(angle: direction * .pi / 2, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
        whaleMaterial.setValue(PenguinRig.pose(simd_quatf(angle: tail, axis: SIMD3(1, 0, 0)), around: Self.tailPivot), forKey: "poseHead")
        if s > 0.08 { once(0) { audio.play(.whale, volume: 0.9) } }
        if s > 0.3 {
            once(1) {
                let blowhole = position + whale.simdOrientation.act(SIMD3(0, 0.62, 0.5))
                guard let burst = spray.copy() as? SCNParticleSystem else { return }
                world.scene.addParticleSystem(burst, transform: SCNMatrix4MakeTranslation(blowhole.x, blowhole.y, blowhole.z))
                audio.play(.splash, volume: 0.5)
            }
        }
        if s >= 1 { finish() }
    }

    // MARK: - Dolphins

    /// 島と浮き氷の間を、2頭がぴょんぴょん跳ねて横切る。
    private func updateDolphins() {
        let speed: Float = 1.7, arc: Float = 1.4, duration: Float = 3.4
        for (i, dolphin) in dolphins.enumerated() {
            let t = time - Float(i) * 0.35
            let x = -direction * 2.6 + direction * speed * t
            let z: Float = i == 0 ? -0.5 : -0.2
            let p = t.truncatingRemainder(dividingBy: arc) / arc
            let y = -0.35 + 1.25 * sin(.pi * max(0, p))
            let slope = 1.25 * .pi * cos(.pi * p) / (speed * arc)
            dolphin.simdPosition = SIMD3(x, t < 0 ? -1 : y, z)
            dolphin.simdOrientation = simd_quatf(angle: direction * .pi / 2, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -atan(slope), axis: SIMD3(1, 0, 0))
            let jump = Int(max(0, t) / arc)
            if t > 0, p > 0.1, p < 0.2 { once(10 + i * 4 + jump) { splash(at: SIMD3(x, 0, z)) } }
            if t > 0, p > 0.86 { once(20 + i * 4 + jump) { splash(at: SIMD3(x, 0, z)) } }
        }
        if time > 0.3 { once(1) { audio.play(.squeak, volume: 0.7) } }
        if time >= duration + 0.4 { finish() }
    }

    // MARK: - Flying fish

    /// 手前の海面すれすれを、羽を広げて3匹が滑空する。
    private func updateFlyingFish() {
        let duration: Float = 2.6
        for (i, fish) in fishes.enumerated() {
            let t = time - Float(i) * 0.22
            let p = t / duration
            let x = -direction * 2.8 + direction * 5.6 * p
            let z = 1.75 + Float(i) * 0.2
            let y = -0.1 + 0.45 * sqrt(max(0, sin(.pi * min(max(p, 0), 1))))
            fish.isHidden = p < 0 || p > 1
            fish.simdPosition = SIMD3(x, y, z)
            fish.simdOrientation = simd_quatf(angle: direction * .pi / 2, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: sin(time * 30 + Float(i)) * 0.08, axis: SIMD3(0, 0, 1))
            if p > 0.03 { once(30 + i) { splash(at: SIMD3(x, 0, z), small: true) } }
            if p > 0.97 { once(40 + i) { splash(at: SIMD3(x, 0, z), small: true) } }
        }
        if time > 0.2 { once(1) { audio.play(.sparkle, volume: 0.6) } }
        if time >= duration + 0.5 { finish() }
    }

    // MARK: - Helpers

    private func splash(at position: SIMD3<Float>, small: Bool = false) {
        world.burst(world.splashTemplate, at: position + SIMD3(0, 0.02, 0), scale: small ? 0.3 : 0.6)
    }

    private func smooth(_ x: Float) -> Float { x * x * (3 - 2 * x) }
}
