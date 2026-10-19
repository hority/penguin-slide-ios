import SceneKit
import SwiftUI
import UIKit

/// SceneKit標準の描画（HDR・トーンマップ・ブルーム・被写界深度）でジオラマを表示する。
/// ゲームの更新はメインスレッドのCADisplayLinkで行う。
final class PenguinRenderView: UIView, UIGestureRecognizerDelegate {
    private let game: PenguinGame
    /// ドラッグを始めた指の位置（パンは少し動いてから始まるので、触れた位置を覚えておく）。
    private var touchStart = CGPoint.zero
    private let sceneView = SCNView(frame: .zero, options: nil)
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0

    init(game: PenguinGame) {
        self.game = game
        super.init(frame: .zero)
        backgroundColor = PenguinWorld.background
        sceneView.scene = game.world.scene
        sceneView.pointOfView = game.world.cameraNode
        sceneView.backgroundColor = PenguinWorld.background
        sceneView.antialiasingMode = .multisampling2X
        sceneView.rendersContinuously = true
        sceneView.isPlaying = true
        sceneView.preferredFramesPerSecond = 60
        sceneView.isUserInteractionEnabled = false
        addSubview(sceneView)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        // 好物をつまんで運ぶ。好物の上で触れたときだけ始まる（それ以外はタップとして扱う）。
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
        // CADisplayLink は対象を強く持つので、弱参照の中継を挟んで循環参照を避ける。
        let link = CADisplayLink(target: PenguinWeakTarget(self), selector: #selector(PenguinWeakTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        // バックグラウンドではGPUを使えないので、描画とゲームの更新を止める（使うと強制終了される）。
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(pause), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        displayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func pause() {
        displayLink?.isPaused = true
        sceneView.isPlaying = false
        sceneView.rendersContinuously = false
    }

    @objc private func resume() {
        lastTime = 0
        sceneView.rendersContinuously = true
        sceneView.isPlaying = true
        displayLink?.isPaused = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        sceneView.frame = bounds
        game.viewSize = bounds.size
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        game.tap(at: recognizer.location(in: self))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touchStart = touch.location(in: self)
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UIPanGestureRecognizer else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        return game.canGrab(at: touchStart)
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            game.dragBegan(at: touchStart)
            game.dragMoved(to: point)
        case .changed:
            game.dragMoved(to: point)
        case .ended, .cancelled, .failed:
            game.dragEnded(at: point)
        default:
            break
        }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(link.timestamp - lastTime, 0.1)
        lastTime = link.timestamp
        game.step(Float(dt))
    }
}

private final class PenguinWeakTarget: NSObject {
    weak var view: PenguinRenderView?
    init(_ view: PenguinRenderView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) {
        guard let view else { return link.invalidate() }
        view.tick(link)
    }
}

struct PenguinGameView: UIViewRepresentable {
    let game: PenguinGame

    func makeUIView(context: Context) -> PenguinRenderView { PenguinRenderView(game: game) }

    func updateUIView(_ view: PenguinRenderView, context: Context) {
        game.world.setDepthOfField(game.hud.depthOfField && !game.hud.feeding)
    }
}
