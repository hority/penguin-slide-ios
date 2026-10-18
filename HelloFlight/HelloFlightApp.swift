import SwiftUI

@main
struct HelloFlightApp: App {
    private let game: PenguinGame

    init() {
        PenguinFonts.register()
        game = PenguinGame()
    }

    var body: some Scene {
        WindowGroup {
            PenguinRootView(game: game)
        }
    }
}
