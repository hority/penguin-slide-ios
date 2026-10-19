import SwiftUI

@main
struct HelloFlightApp: App {
    @State private var game: PenguinGame?

    init() {
        PenguinFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let game { PenguinRootView(game: game) }
                if game?.hud.ready != true { PenguinLoadingView().transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.4), value: game?.hud.ready == true)
            .statusBarHidden()
            .task {
                // 読み込み画面を先に描いてから、重い準備（ステージ・キャラのモデルとテクスチャ）を始める。
                try? await Task.sleep(nanoseconds: 50_000_000)
                game = PenguinGame()
            }
        }
    }
}
