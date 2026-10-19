import Observation
import SceneKit
import UIKit
import simd

struct PenguinPop: Identifiable {
    let id = UUID()
    var text: String
    var position: CGPoint
    var big: Bool
    var star = true
}

/// SwiftUIに見せる状態だけを持つ。毎フレーム変わる値は置かない。
@Observable
final class PenguinHUD {
    enum Screen { case title, playing }
    var screen: Screen = .title
    var mode: PenguinMode = .math
    var question: PenguinQuestion?
    var stars = 0
    var pops: [PenguinPop] = []
    var soundOn = true
    var autoOrbit = false
    var character: PenguinCharacter = .penguin
    var depthOfField = true
}

/// ゲームの進行。タップした浮き氷へ、ペンギンがすべり台からジャンプする。
final class PenguinGame {
    enum Phase { case idle, waiting, flop, sliding, flying, celebrate, fall, returning }

    let hud = PenguinHUD()
    let audio = PenguinAudio()
    let world = PenguinWorld()
    var viewSize = CGSize(width: 390, height: 844)
    private var focusDistance: Float = 11

    private var phase = Phase.idle
    private var phaseTime: Float = 0
    private var time: Float = 0
    private var idleTime: Float = 0
    private var chosen = 0
    private var lastCorrect = true
    private var hintIndex: Int?
    private var flightStart = SIMD3<Float>.zero
    private var flightVelocity = SIMD3<Float>.zero
    private var landTime: Float = 10
    private var nextBlink: Float = 2
    /// 問題の切り替え演出の経過時間（氷が沈み、新しい看板で浮かぶ）。nil なら演出なし。
    private var swapTime: Float?
    private var swapSplashed = false
    private var nextCritter: Float = 12
    /// 氷を選んでからの経過時間（看板の弾み用）。
    private var selectTime: Float = 10
    private lazy var critters = PenguinCritters(world: world, audio: audio)
    private var fallStart = SIMD3<Float>.zero
    private var splashed = false
    /// 頭から腹ばいで滑る（たまのレア演出）。ふだんはお尻で座って滑る。
    private var headFirst = false
    private var returnPopped = false
    private var penguinPosition = PenguinGame.standPosition
    private var cameraTarget = SIMD3<Float>(0, 1.5, -1.0)
    private var orbit: Float = 0
    /// カメラの距離と仰角。タイトルではキャラに寄り、遊ぶときは全体を映す位置へなめらかに移る。
    private var cameraDistance: Float = PenguinGame.titleDistance
    private var cameraElevation: Float = PenguinGame.titleElevation
    private var cameraAzimuth: Float = 0.25
    private static let titleDistance: Float = 6.9
    private static let titleElevation: Float = 0.28
    private static let characterKey = "penguin.character"

    private static let gravity: Float = 7
    private static let flightDuration: Float = 0.8
    private static let slideDuration: Float = 1.1
    private static let baseTarget = SIMD3<Float>(0, 1.5, -1.0)
    private static let elevation: Float = 0.62
    private static let distance: Float = 11.5
    private static var standPosition: SIMD3<Float> { SIMD3(PenguinTrack.stand.x, PenguinTrack.platformY + PenguinModel.centerHeight, PenguinTrack.stand.z) }

    init() {
        for i in world.floes.indices { world.setSign(i, text: "?", dots: 0, highlight: false) }
        if let saved = UserDefaults.standard.string(forKey: Self.characterKey).flatMap(PenguinCharacter.init(rawValue:)) {
            hud.character = saved
            world.penguin.build(saved)
        }
        cameraTarget = Self.titleTarget
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") { demoTime = 0 }
        #endif
        step(0)
    }

    /// タイトル画面のカメラの注視点。キャラが画面の上の方に大きく映るよう、少し下を見る。
    /// タイトル：上の大きなロゴと下のカードの間にキャラが収まるよう、少し引いて注視点を上げる。
    private static var titleTarget: SIMD3<Float> { standPosition + SIMD3(0.05, -0.52, 0) }

    func selectCharacter(_ character: PenguinCharacter) {
        guard character != hud.character else {
            hop()
            return
        }
        hud.character = character
        UserDefaults.standard.set(character.rawValue, forKey: Self.characterKey)
        world.penguin.build(character)
        world.burst(world.sparkleTemplate, at: penguinPosition + SIMD3(0, 0.2, 0), scale: 0.5)
        audio.play(.pop)
        audio.say([.ja(character.name)])
        landTime = -0.45
    }

    // MARK: - Flow

    func start(_ mode: PenguinMode) {
        hud.mode = mode
        hud.screen = .playing
        audio.play(.pop)
        nextQuestion(new: true)
    }

    func goHome() {
        hud.screen = .title
        hud.question = nil
        hintIndex = nil
        swapTime = nil
        phase = .idle
        phaseTime = 0
        for i in world.floes.indices { world.setSign(i, text: "?", dots: 0, highlight: false) }
        audio.play(.pi)
    }

    func repeatQuestion() {
        guard let question = hud.question else { return }
        audio.say(question.ask)
        idleTime = 0
    }

    func setSound(_ on: Bool) {
        hud.soundOn = on
        audio.enabled = on
    }

    private func nextQuestion(new: Bool) {
        if new || hud.question == nil {
            hud.question = PenguinQuiz.make(hud.mode, stars: hud.stars, avoiding: hud.question.map { $0.choices[$0.answer] })
            hintIndex = nil
            swapTime = 0
            swapSplashed = false
            audio.play(.blub, volume: 0.7)
        } else {
            applySigns()
        }
        guard let question = hud.question else { return }
        phase = .waiting
        phaseTime = 0
        idleTime = 0
        audio.say(question.ask)
    }

    private func applySigns() {
        guard let question = hud.question else { return }
        for i in world.floes.indices {
            world.setSign(i, text: question.choices[i], dots: question.dots[i], highlight: i == hintIndex)
        }
    }

    // MARK: - Input

    func tap(at point: CGPoint) {
        guard hud.screen == .playing else {
            hop()
            return
        }
        guard phase == .waiting, swapTime == nil else { return }
        if let index = floe(at: point) {
            select(index)
        } else {
            hop()
        }
    }

    private func select(_ index: Int) {
        chosen = index
        phase = .flop
        phaseTime = 0
        headFirst = Double.random(in: 0...1) < 0.1
        selectTime = 0
        audio.play(.pi)
        world.burst(world.sparkleTemplate, at: world.floes[index].board.simdWorldPosition, scale: 0.4)
    }

    /// 浮き氷以外をタップしたとき：その場で小さく跳ねる。たまに面白い音。
    private func hop() {
        guard phase == .waiting || phase == .idle, landTime > 0.45 else { return }
        landTime = -0.45
        if Double.random(in: 0...1) < 0.35 { audio.playFunny() } else { audio.play(.jump, volume: 0.5) }
    }

    private func floe(at point: CGPoint) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (i, floe) in world.floes.enumerated() {
            let base = floe.root.simdWorldPosition
            let board = floe.board.simdWorldPosition
            for p in [base + SIMD3(0, 0.1, 0), board, mix(base, board, t: 0.5)] {
                guard let screen = project(p) else { continue }
                let d = hypot(screen.x - point.x, screen.y - point.y)
                if d < (best?.distance ?? .infinity) { best = (i, d) }
            }
        }
        guard let best, best.distance < max(80, viewSize.width * 0.24) else { return nil }
        return best.index
    }

    #if DEBUG
    // MARK: - Demo

    /// プロモ動画の収録用（シミュレータで -demo を付けて起動）。キャラを選び、ひらがな→かずを自動で遊ぶ。
    private var demoTime: Float = -1
    private var demoRound = 0
    private var demoAnswers = 0

    private func demoStep(_ dt: Float) {
        guard demoTime >= 0 else { return }
        demoTime += dt
        switch hud.screen {
        case .title:
            let modes: [PenguinMode] = [.hiragana, .math]
            guard demoRound < modes.count else { return }
            if demoRound == 0 {
                let picks: [(Float, PenguinCharacter)] = [(1.5, .octopus), (2.7, .ghost), (3.9, .unicorn), (5.1, .penguin)]
                for (at, character) in picks where demoTime - dt < at && demoTime >= at { selectCharacter(character) }
            }
            if demoTime > (demoRound == 0 ? 6.5 : 2) {
                demoTime = 0
                start(modes[demoRound])
            }
        case .playing:
            guard phase == .waiting, swapTime == nil, let question = hud.question else {
                demoTime = 0
                return
            }
            guard demoTime > 2.2 else { return }
            demoTime = 0
            if demoAnswers == 4 {
                demoAnswers = 0
                demoRound += 1
                goHome()
                return
            }
            // ひらがなの2問目はわざと外して、ヒントの演出も映す。
            let wrong = demoRound == 0 && demoAnswers == 1
            select(wrong ? (question.answer + 1) % question.choices.count : question.answer)
            demoAnswers += 1
        }
    }
    #endif

    // MARK: - Projection

    private func viewProjection() -> simd_float4x4 {
        let aspect = Float(max(viewSize.width, 1) / max(viewSize.height, 1))
        let f = 1 / tan(Float(world.camera.fieldOfView) * .pi / 360)
        let near = Float(world.camera.zNear), far = Float(world.camera.zFar)
        let projection = simd_float4x4(columns: (
            SIMD4(f / aspect, 0, 0, 0),
            SIMD4(0, f, 0, 0),
            SIMD4(0, 0, (far + near) / (near - far), -1),
            SIMD4(0, 0, 2 * far * near / (near - far), 0)))
        return projection * world.cameraNode.simdWorldTransform.inverse
    }

    /// ワールド座標を画面座標（ポイント、左上原点）へ。
    func project(_ p: SIMD3<Float>) -> CGPoint? {
        let clip = viewProjection() * SIMD4(p, 1)
        guard clip.w > 0.01 else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return CGPoint(x: CGFloat(ndc.x * 0.5 + 0.5) * viewSize.width, y: CGFloat(0.5 - ndc.y * 0.5) * viewSize.height)
    }

    // MARK: - Frame update

    func step(_ dt: Float) {
        #if DEBUG
        demoStep(dt)
        #endif
        time += dt
        phaseTime += dt
        landTime += dt
        selectTime += dt
        updatePenguin(dt)
        advanceSwap(dt)
        updateWorld(dt)
        updateMarker()
        updateCamera(dt)
        updateShading()
        critters.update(dt)
        // ときどき海の生き物が出てくる。
        if time > nextCritter, phase == .waiting || phase == .idle {
            critters.play()
            nextCritter = time + .random(in: 25...45)
        }
    }

    private func updatePenguin(_ dt: Float) {
        let model = world.penguin
        var position = Self.standPosition
        var pitch: Float = 0, yaw: Float = 0, roll: Float = 0
        var flap: Float = sin(time * 2.2) * 0.12
        var scale: Float = 1

        switch phase {
        case .idle, .waiting:
            idleTime += dt
            roll = sin(time * 2.4) * 0.07
            position.y += abs(sin(time * 2.4)) * 0.015
            if phase == .waiting, idleTime > 9 { repeatQuestion() }
        case .flop:
            let k = smooth(min(phaseTime / 0.3, 1))
            position = mix(Self.standPosition, slidePosition(0), t: k) + SIMD3(0, sin(k * .pi) * 0.12, 0)
            pitch = slidePitch(0) * k
            yaw = PenguinTrack.headingAngle * k
            flap = (headFirst ? 0.5 : 1.0) * k
            if phaseTime >= 0.3 {
                phase = .sliding
                phaseTime = 0
                audio.play(.slide)
                if Double.random(in: 0...1) < 0.15 { audio.playFunny() }
            }
        case .sliding:
            let s = min(phaseTime / Self.slideDuration, 1)
            let t = 0.3 * s + 0.7 * s * s
            position = slidePosition(t)
            pitch = slidePitch(t)
            yaw = PenguinTrack.headingAngle
            // お尻で滑るときは両手を上げてバンザイ。
            flap = headFirst ? 1.1 : 1.3 + sin(time * 5) * 0.12
            roll = sin(time * 7) * 0.04
            if s >= 1 { launch(from: position) }
        case .flying:
            let tt = min(phaseTime, Self.flightDuration)
            position = flightStart + flightVelocity * tt + SIMD3(0, -0.5 * Self.gravity * tt * tt, 0)
            let k = tt / Self.flightDuration
            pitch = slidePitch(1) * (1 - smooth(min(k / 0.7, 1)))
            yaw = PenguinTrack.headingAngle * (1 - smooth(k)) + 2 * .pi * smooth(k)
            flap = sin(time * 30) * 0.9 + 0.4
            if phaseTime >= Self.flightDuration { land() }
        case .celebrate:
            let floe = world.floes[chosen]
            position = floe.top + SIMD3(0, PenguinModel.centerHeight, 0.13)
            position.y += abs(sin(phaseTime * 9)) * 0.14 * max(0, 1 - phaseTime / 1.6)
            flap = sin(time * 26) * 0.9 + 0.5
            yaw = sin(phaseTime * 6) * 0.25
            if phaseTime > 1.9 { beginReturn() }
        case .fall:
            let floe = world.floes[chosen]
            let water = SIMD3(floe.home.x + (floe.home.x >= 0 ? 0.3 : -0.3), -0.12, floe.home.z + 0.5)
            if phaseTime < 0.45 {
                let k = phaseTime / 0.45
                position = mix(fallStart, water, t: k) + SIMD3(0, sin(k * .pi) * 0.2, 0)
                roll = (floe.home.x >= 0 ? -1 : 1) * k * 1.6
                flap = sin(time * 34) * 1.0
            } else {
                if !splashed {
                    splashed = true
                    world.burst(world.splashTemplate, at: SIMD3(water.x, 0.02, water.z))
                    audio.play(.splash)
                }
                position = water + SIMD3(0, sin(phaseTime * 5) * 0.025, 0)
                flap = sin(time * 14) * 0.6 + 0.4
                roll = sin(phaseTime * 7) * 0.2
            }
            if phaseTime > 2.0 { beginReturn() }
        case .returning:
            if phaseTime < 0.25 {
                position = penguinPosition
                scale = max(0.01, 1 - phaseTime / 0.25)
            } else {
                if !returnPopped {
                    returnPopped = true
                    audio.play(.pop)
                }
                let k = min((phaseTime - 0.25) / 0.35, 1)
                scale = max(0.01, k + sin(k * .pi) * 0.3)
            }
            if phaseTime >= 0.6 { nextQuestion(new: lastCorrect) }
        }

        // 着地の弾み（その場ジャンプ時は負の時間から跳ねる）
        var squashY: Float = 1
        if landTime < 0 {
            position.y += sin(-landTime / 0.45 * .pi) * 0.18
            flap = sin(time * 28) * 0.8
        } else if landTime < 0.6 {
            squashY = 1 - 0.22 * exp(-landTime * 7) * cos(landTime * 22)
        }

        penguinPosition = position
        model.root.simdPosition = position
        let q = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: roll, axis: SIMD3(0, 0, 1))
        model.root.simdOrientation = q
        let xz = 1 + (1 - squashY) * 0.5
        model.root.simdScale = SIMD3(xz, squashY, xz) * scale
        // まばたきと頭の動き（待つ間は見回し、正解では上を向いて喜ぶ）
        let blinkPhase = time - nextBlink
        if blinkPhase > 0.14 { nextBlink = time + .random(in: 2.2...4.5) }
        model.setBlink(blinkPhase > 0 && blinkPhase < 0.14 ? sin(blinkPhase / 0.14 * .pi) : 0)
        var headPitch: Float = 0, headYaw: Float = 0
        switch phase {
        case .idle, .waiting:
            headYaw = sin(time * 0.8) * 0.3
            headPitch = sin(time * 1.6) * 0.05
        case .celebrate:
            headPitch = -0.35 + sin(phaseTime * 12) * 0.1
        case .fall:
            headPitch = 0.2
        default:
            break
        }
        model.head.simdEulerAngles = SIMD3(headPitch, headYaw, 0)
        model.leftFlipper.simdEulerAngles = SIMD3(0, 0, -0.15 - flap)
        model.rightFlipper.simdEulerAngles = SIMD3(0, 0, 0.15 + flap)
        model.applyPose()
    }

    /// 滑るときの体の位置：腹ばいは体の中心が面から0.25m、お尻で座ると0.3m（足は前へ投げ出す）。
    private func slidePosition(_ t: Float) -> SIMD3<Float> {
        PenguinTrack.point(t) + PenguinTrack.up(t) * (headFirst ? 0.25 : 0.3)
    }

    /// 滑るときの前後の傾き：腹ばいは前へ倒れ、お尻で座るときは面に沿って少し後ろへ反る。
    private func slidePitch(_ t: Float) -> Float {
        (headFirst ? .pi / 2 : -0.2) + PenguinTrack.slope(t)
    }

    private func launch(from position: SIMD3<Float>) {
        let target = world.floes[chosen].top + SIMD3(0, PenguinModel.centerHeight, 0.13)
        let duration = Self.flightDuration
        flightStart = position
        flightVelocity = (target - position) / duration + SIMD3(0, 0.5 * Self.gravity * duration, 0)
        phase = .flying
        phaseTime = 0
        audio.play(.jump)
        if Double.random(in: 0...1) < 0.2 { audio.playFunny() }
    }

    private func land() {
        guard let question = hud.question else { return }
        landTime = 0
        phaseTime = 0
        audio.play(.land)
        let floe = world.floes[chosen]
        if chosen == question.answer {
            lastCorrect = true
            phase = .celebrate
            hud.stars += 1
            audio.play(.correct)
            audio.play(.sparkle, volume: 0.6)
            world.burst(world.sparkleTemplate, at: floe.top + SIMD3(0, 0.35, 0))
            audio.say(question.praise)
            let milestone = hud.stars % 5 == 0
            if milestone {
                audio.play(.fanfare)
                world.burst(world.sparkleTemplate, at: floe.top + SIMD3(0, 0.6, 0), scale: 2.5)
            } else if Double.random(in: 0...1) < 0.15 {
                audio.playFunny()
            }
            if let point = project(floe.top + SIMD3(0, 0.75, 0)) {
                addPop(milestone ? "すごい！ ×\(hud.stars)" : "+1", at: point, big: milestone)
            }
            hintIndex = nil
            world.setSign(chosen, text: question.choices[chosen], dots: question.dots[chosen], highlight: true)
            if Double.random(in: 0...1) < 0.35 {
                critters.play()
                nextCritter = time + .random(in: 25...45)
            }
        } else {
            lastCorrect = false
            phase = .fall
            fallStart = penguinPosition
            splashed = false
            hintIndex = question.answer
            audio.play(.wrong, volume: 0.9)
            audio.say(question.hint)
            world.setSign(question.answer, text: question.choices[question.answer], dots: question.dots[question.answer], highlight: true)
            if let point = project(floe.top + SIMD3(0, 0.75, 0)) { addPop("ばしゃーん！", at: point, big: false, star: false) }
        }
    }

    private func beginReturn() {
        phase = .returning
        phaseTime = 0
        returnPopped = false
    }

    private func addPop(_ text: String, at point: CGPoint, big: Bool, star: Bool = true) {
        let pop = PenguinPop(text: text, position: point, big: big, star: star)
        hud.pops.append(pop)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak hud = self.hud] in
            hud?.pops.removeAll { $0.id == pop.id }
        }
    }

    // MARK: - World animation

    private func updateWorld(_ dt: Float) {
        for (i, floe) in world.floes.enumerated() {
            let phaseOffset = Float(i) * 1.7
            var tilt = SIMD3<Float>(sin(time * 1.1 + phaseOffset) * 0.04, 0, cos(time * 0.9 + phaseOffset) * 0.04)
            if phase == .fall, i == chosen {
                let k = phaseTime < 0.3 ? phaseTime / 0.3 : max(0, 1 - (phaseTime - 0.3) / 1.2)
                tilt.z += (floe.home.x >= 0 ? -1 : 1) * 0.35 * smooth(k)
            }
            floe.root.simdPosition = floe.home + SIMD3(0, sin(time * 1.3 + phaseOffset) * 0.015 + swapOffset(i), 0)
            floe.root.simdEulerAngles = tilt
            let pulse: Float = hintIndex == i && (phase == .waiting || phase == .fall || phase == .returning) ? 1 + 0.1 * sin(time * 8) : 1
            let bounce: Float = i == chosen && selectTime < 1.2 ? 1 + 0.22 * exp(-selectTime * 5) * cos(selectTime * 16) : 1
            floe.board.simdScale = SIMD3(repeating: pulse * bounce)
            updateRing(floe, index: i)
        }
        for (i, chunk) in world.chunks.enumerated() {
            var p = chunk.simdPosition
            p.y = sin(time * 1.2 + Float(i) * 2.1) * 0.012
            chunk.simdPosition = p
        }
        world.waterMaterial.normal.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(160, 160, 1), SCNMatrix4MakeTranslation(time * 0.015, time * 0.02, 0))

        // 接地影：足元の面に沿わせ、高いほど薄く大きく。
        let feet = penguinPosition - SIMD3(0, PenguinModel.centerHeight, 0)
        if let ground = world.ground(below: penguinPosition), phase != .returning {
            let height = max(0, feet.y - ground.height)
            let lying = headFirst && (phase == .sliding || phase == .flop)
            world.contactShadow.isHidden = false
            world.contactShadow.simdPosition = SIMD3(penguinPosition.x, ground.height + 0.012, penguinPosition.z)
            world.contactShadow.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: ground.normal)
            let size = (lying ? 1.25 : 1) * (1 + height * 0.6)
            world.contactShadow.simdScale = SIMD3(size, 1, lying ? size * 1.4 : size)
            world.contactShadow.opacity = CGFloat(max(0, 1 - height / 1.2))
        } else {
            world.contactShadow.isHidden = true
        }
    }

    // MARK: - Camera, focus, shading

    private func updateCamera(_ dt: Float) {
        let title = hud.screen == .title
        let follow = Self.baseTarget + (penguinPosition - Self.baseTarget) * SIMD3(0.06, 0.05, 0.05)
        let goal = title ? Self.titleTarget : follow
        let ease = min(1, dt * 2.5)
        cameraTarget += (goal - cameraTarget) * ease
        let wide = Float(viewSize.width / max(viewSize.height, 1))
        cameraDistance += ((title ? Self.titleDistance : Self.distance * (wide > 0.8 ? 0.82 : 1)) - cameraDistance) * ease
        cameraElevation += ((title ? Self.titleElevation : Self.elevation) - cameraElevation) * ease
        orbit = hud.autoOrbit ? orbit + dt : orbit * max(0, 1 - dt * 2)
        cameraAzimuth += ((title ? 0.25 : 0) - cameraAzimuth) * ease
        let azimuth = (hud.autoOrbit ? sin(orbit * 0.25) * 0.32 : 0) + cameraAzimuth
        let offset = SIMD3(sin(azimuth) * cos(cameraElevation), sin(cameraElevation), cos(azimuth) * cos(cameraElevation)) * cameraDistance
        world.cameraNode.simdPosition = cameraTarget + offset
        world.cameraNode.simdLook(at: cameraTarget, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))

        // 被写界深度の焦点を主役に合わせる。選ぶ間は答えの看板がくっきり読めるよう浮き氷側へ寄せる。
        var subject = penguinPosition
        if !title, phase == .waiting || phase == .flop { subject = mix(penguinPosition, SIMD3(0, 0.4, 0.8), t: 0.75) }
        let target = simd_distance(world.cameraNode.simdPosition, subject)
        focusDistance += (target - focusDistance) * min(1, dt * 4)
        world.camera.focusDistance = CGFloat(focusDistance)

        // カメラと主役の間を遮る小物は半透明にする。
        let eye = world.cameraNode.simdPosition
        for occluder in world.occluders {
            let ray = penguinPosition - eye
            let along = simd_clamp(simd_dot(occluder.center - eye, ray) / simd_length_squared(ray), 0, 1)
            let closest = eye + ray * along
            let blocking = along < 0.97 && simd_distance(closest, occluder.center) < occluder.radius
            let target: Float = blocking ? 0.25 : 1
            let current = Float(occluder.node.opacity)
            occluder.node.opacity = CGFloat(current + (target - current) * min(1, dt * 6))
        }
    }

    private func updateShading() {
        let feet = penguinPosition + world.penguin.root.simdOrientation.act(SIMD3(0, -PenguinModel.centerHeight + 0.03, 0.04))
        let visible = phase != .returning || phaseTime > 0.25
        let body = NSValue(scnVector4: SCNVector4(penguinPosition.x, penguinPosition.y, penguinPosition.z, visible ? 0.28 : -10))
        let feetValue = NSValue(scnVector4: SCNVector4(feet.x, feet.y, feet.z, visible ? 0.09 : -10))
        for material in world.aoMaterials {
            material.setValue(body, forKey: "aoBody")
            material.setValue(feetValue, forKey: "aoFeet")
        }
    }

    private func smooth(_ x: Float) -> Float { x * x * (3 - 2 * x) }

    /// 選べる氷は水際の輪が順番に光り、選んだ氷・正解のヒントは琥珀色で光る。
    private func updateRing(_ floe: PenguinFloe, index: Int) {
        let selectable = hud.screen == .playing && phase == .waiting && swapTime == nil
        let jumping = phase == .flop || phase == .sliding || phase == .flying
        var alpha: Float = 0, scale: Float = 1, amber = false
        if hud.screen == .playing, jumping, index == chosen {
            amber = true
            alpha = 1
            scale = 1 + 0.08 * sin(time * 14)
        } else if selectable, index == hintIndex {
            amber = true
            alpha = 0.7 + 0.3 * sin(time * 6)
            scale = 1 + 0.06 * sin(time * 6)
        } else if selectable {
            let wave = sin(time * 3 - Float(index) * 1.2)
            alpha = 0.4 + 0.35 * (wave * 0.5 + 0.5)
            scale = 1 + 0.05 * wave
        }
        floe.ring.isHidden = alpha <= 0
        floe.ring.opacity = CGFloat(alpha)
        floe.ring.simdScale = SIMD3(scale, 1, scale)
        floe.ringMaterial.emission.contents = amber ? UIColor(red: 1, green: 0.72, blue: 0.2, alpha: 1) : UIColor(red: 0.75, green: 1, blue: 0.95, alpha: 1)
        floe.ringMaterial.emission.intensity = amber ? 1.6 : 1.1
    }

    /// 選んだ氷の看板の上で星がくるくる回る（ジャンプが終わるまで）。
    private func updateMarker() {
        let jumping = phase == .flop || phase == .sliding || phase == .flying
        world.marker.isHidden = !(hud.screen == .playing && jumping)
        guard !world.marker.isHidden else { return }
        world.marker.simdPosition = world.floes[chosen].board.simdWorldPosition + SIMD3(0, 0.62 + abs(sin(time * 5)) * 0.08, 0)
        world.markerStar.simdEulerAngles = SIMD3(0, time * 4, 0)
    }

    /// 問題切り替え時の浮き氷の上下。順番に沈み、看板を替えて、少し弾みながら浮かぶ。
    private func swapOffset(_ index: Int) -> Float {
        guard let swap = swapTime else { return 0 }
        let delay = Float(index) * 0.08, depth: Float = 1.4  // 看板の上端（氷の上1.12m）まで水に隠れる深さ
        if swap < 0.45 + delay { return -depth * smooth(max(0, swap - delay) / 0.45) }
        if swap < 0.7 + delay { return -depth }
        let k = min((swap - 0.7 - delay) / 0.6, 1) - 1
        return -depth * (1 - (1 + 2.70158 * k * k * k + 1.70158 * k * k))
    }

    private func advanceSwap(_ dt: Float) {
        guard let swap = swapTime else { return }
        let next = swap + dt
        if swap < 0.62, next >= 0.62 { applySigns() }
        if !swapSplashed, next >= 0.75 {
            swapSplashed = true
            for floe in world.floes { world.burst(world.splashTemplate, at: floe.home + SIMD3(0, 0.02, 0), scale: 0.35) }
            audio.play(.splash, volume: 0.35)
        }
        swapTime = next > 1.5 ? nil : next
    }
}
