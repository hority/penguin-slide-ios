import CoreText
import SwiftUI

enum PenguinFonts {
    /// 文字の形を正しく覚えられるよう、教育向けのUD（ユニバーサルデザイン）書体に統一する。
    static let name = "BIZUDPGothic-Bold"

    /// 同梱フォント（BIZ UDPゴシック、SIL OFL）を登録する。見つからなければシステムフォントで表示される。
    static func register() {
        guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Color {
    static let penguinAmber = Color(red: 0.94, green: 0.69, blue: 0.24)
    static let penguinMint = Color(red: 0.56, green: 0.91, blue: 0.77)
    static let penguinInk = Color(red: 0.08, green: 0.13, blue: 0.25)
    static let penguinInkSoft = Color(red: 0.18, green: 0.36, blue: 0.3)
}

extension Font {
    static func penguin(_ size: CGFloat) -> Font { .custom(PenguinFonts.name, size: size) }
}

/// 白いカード。3歳でも読みやすいよう、白地に濃い文字で高コントラストにする。
struct PenguinCard: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(Color.white.opacity(0.95)))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

/// 下に影の付いた、押せる丸ボタン。
struct PenguinRoundButton: ButtonStyle {
    var color: Color
    var size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        ZStack {
            Circle().fill(color.mix(with: .black, by: 0.35)).offset(y: pressed ? 3 : 7)
            Circle()
                .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.25), color], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5))
                .offset(y: pressed ? 4 : 0)
            configuration.label
                .foregroundStyle(Color.penguinInk)
                .offset(y: pressed ? 4 : 0)
        }
        .frame(width: size, height: size + 7)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

struct PenguinRootView: View {
    let game: PenguinGame
    @State private var showSettings = false

    var body: some View {
        let hud = game.hud
        ZStack {
            PenguinGameView(game: game).ignoresSafeArea()
            ForEach(hud.pops) { pop in PenguinPopView(pop: pop) }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if hud.screen == .title {
                PenguinTitleView(game: game, showSettings: $showSettings)
                    .modifier(PenguinLargeScreenScale())
            } else {
                PenguinPlayHUD(game: game)
                    .modifier(PenguinLargeScreenScale())
                if let step = hud.tutorial, step != .back {
                    PenguinTutorialView(step: step, food: hud.character.food, from: hud.tutorialFrom, to: hud.tutorialTo)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { game.audio.start() }
        .sheet(isPresented: $showSettings) { PenguinSettingsView(game: game) }
    }
}

/// iPadなど大きな画面では、iPhone向けの大きさで作ったボタンやカードをまとめて拡大する
/// （iPhoneの大きさで並べてから拡大するので配置は崩れない。3Dの画面とその上の文字はそのまま）。
private struct PenguinLargeScreenScale: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let scale = min(1.6, max(1, min(geometry.size.width / 430, geometry.size.height / 900)))
            content
                .frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct PenguinTitleView: View {
    let game: PenguinGame
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            // タイトルロゴ（画像生成、背景は透明）。カードには載せず、中央に大きく置く。
            Group {
                if let logo = PenguinArt.image("title") {
                    Image(uiImage: logo).resizable().interpolation(.high).scaledToFit()
                } else {
                    Text("ペンギン すべりだい").font(.penguin(34)).foregroundStyle(Color.penguinInk)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 200)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .accessibilityLabel("ペンギン すべりだい")
            // 設定はおうちのひと向け。子どもが触りにくい右上の小さなボタンにする。
            .overlay(alignment: .topTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(PenguinRoundButton(color: .white, size: 34))
                .accessibilityLabel("おうちのひと向けの設定")
            }

            Spacer()

            // 上の空いた部分には、カメラが寄ったキャラが大きく映る。
            VStack(spacing: 10) {
                Text("だれと あそぶ？").font(.penguin(20)).foregroundStyle(Color.penguinInk)
                // 8キャラを4列にして、小さいiPhoneでも全員を選べるようにする。
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(66), spacing: 12), count: 4), spacing: 12) {
                    ForEach(PenguinCharacter.allCases) { character in
                        let selected = game.hud.character == character
                        Button { game.selectCharacter(character) } label: {
                            PenguinArt.view(character.illustration, size: 50)
                                .frame(width: 66, height: 66)
                                .background(Circle().fill(selected ? Color.penguinAmber.opacity(0.35) : Color.white))
                                .overlay(Circle().strokeBorder(selected ? Color.penguinAmber : Color.penguinInk.opacity(0.15), lineWidth: selected ? 4 : 2))
                                .scaleEffect(selected ? 1.08 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(character.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .animation(.spring(duration: 0.3), value: game.hud.character)
                Text("どれで あそぶ？").font(.penguin(20)).foregroundStyle(Color.penguinInk)
                    .padding(.top, 4)
                // 3つと2つの2段（いちばん小さいiPhoneの幅にも収まる大きさ）。まぜこぜは色を変えて目立たせる。
                VStack(spacing: 8) {
                    ForEach([[PenguinMode.math, .hiragana, .katakana], [.alphabet, .mix]], id: \.self) { row in
                        HStack(spacing: 10) {
                            ForEach(row) { mode in
                                Button { game.start(mode) } label: {
                                    VStack(spacing: 2) {
                                        Text(mode.badge).font(.penguin(mode == .math ? 28 : 24))
                                        Text(mode.title).font(.penguin(15))
                                    }
                                }
                                .buttonStyle(PenguinRoundButton(color: modeColor(mode), size: 96))
                                .accessibilityLabel(mode.title)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .modifier(PenguinCard(radius: 26))
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

private func modeColor(_ mode: PenguinMode) -> Color {
    switch mode {
    case .math, .katakana: .penguinAmber
    case .hiragana, .alphabet: .penguinMint
    case .mix: Color(red: 1, green: 0.66, blue: 0.76)
    }
}

/// 起動時の読み込み画面（起動画面と同じ空の色）。モデルの読み込みとシェーダーの準備が終わるまで出す。
struct PenguinLoadingView: View {
    @State private var hop = false

    var body: some View {
        let character = UserDefaults.standard.string(forKey: "penguin.character").flatMap(PenguinCharacter.init(rawValue:)) ?? .penguin
        VStack(spacing: 14) {
            if let logo = PenguinArt.image("title") {
                Image(uiImage: logo).resizable().interpolation(.high).scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 200)
                    .padding(.horizontal, 16)
            }
            PenguinArt.view(character.illustration, size: 96)
                .offset(y: hop ? -14 : 0)
                .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: hop)
            Text("じゅんびちゅう…").font(.penguin(20)).foregroundStyle(Color.penguinInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("LaunchBackground").ignoresSafeArea())
        .onAppear { hop = true }
    }
}

private struct PenguinPlayHUD: View {
    let game: PenguinGame

    var body: some View {
        let hud = game.hud
        // 操作は上部だけに置く（画面下端はホームインジケータ、下半分は浮き氷をタップする場所）。
        // 集めた数は島の置き場に好物として並ぶので、数字の表示は置かない。
        HStack(alignment: .top, spacing: 10) {
            if hud.feeding {
                // 顔のアップから戻る：すべりだいの絵のボタン。
                Button { game.endFeeding() } label: {
                    PenguinArt.view("slide", size: 62)
                }
                .buttonStyle(PenguinRoundButton(color: .penguinMint, size: 84))
                .accessibilityLabel("すべりだいに もどる")
                .overlay(alignment: .bottomTrailing) {
                    if hud.tutorial == .back {
                        PenguinTutorialView(step: .back, food: hud.character.food, from: CGPoint(x: 42, y: 42), to: nil)
                            .frame(width: 84, height: 84)
                            .allowsHitTesting(false)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Button { game.goHome() } label: {
                    Image(systemName: "house.fill").font(.system(size: 26, weight: .bold))
                }
                .buttonStyle(PenguinRoundButton(color: .penguinMint, size: 64))
                .accessibilityLabel("もどる")
            }

            // 問題が変わると、新しいカードが右からスライドインし、前のカードは左へ抜ける。
            ZStack {
                if let question = hud.question, !hud.feeding {
                    // 大きさは問題によらず固定。右の丸ボタンで問題をもう一度読む。
                    VStack(spacing: 2) {
                        HStack(spacing: 10) {
                            if !question.big.isEmpty {
                                Text(question.big)
                                    .font(.penguin(question.big.count > 2 ? 30 : 52))
                                    .foregroundStyle(Color.penguinInk)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            PenguinQuestionArt(question: question) { game.audio.play(.pop, volume: 0.5) }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // もういちど聞くボタン（問題文の読み上げ）。
                            Button { game.repeatQuestion() } label: {
                                Image(systemName: "speaker.wave.2.fill").font(.system(size: 20, weight: .bold))
                            }
                            .buttonStyle(PenguinRoundButton(color: .penguinAmber, size: 48))
                            .accessibilityLabel("もういちど きく")
                        }
                        .frame(height: 64)
                        Text(question.prompt)
                            .font(.penguin(20))
                            .foregroundStyle(Color.penguinInk)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 104)
                    .modifier(PenguinCard())
                    .id(question.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.5, bounce: 0.3), value: hud.question?.id)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.35), value: hud.feeding)
    }
}

/// 同梱イラスト（OpenAIの画像生成で作成、ci/generate-illustrations.py）。
enum PenguinArt {
    private static var cache: [String: UIImage] = [:]

    static func image(_ name: String) -> UIImage? {
        if let image = cache[name] { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Illustrations"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[name] = image
        return image
    }

    @ViewBuilder static func view(_ name: String, size: CGFloat) -> some View {
        if let image = image(name) {
            Image(uiImage: image).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
        }
    }
}

/// 問題の絵。かずのときは数だけ並べ、たし算は2組を「＋」でつなぐ。与えられた枠に収まる大きさで描く。
/// 子どもは指で数えたがるので、絵をタップするとぴょこっと跳ねる（読み上げはしない）。
private struct PenguinQuestionArt: View {
    let question: PenguinQuestion
    let onTap: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let counts = question.counts
            let plusWidth: CGFloat = 22 * CGFloat(max(0, counts.count - 1))
            // 1段に並べる数（1〜5）を、絵がいちばん大きくなるように選ぶ。
            let layout = (1...5).map { perRow -> (perRow: Int, size: CGFloat) in
                let columns = counts.map { min(perRow, $0) }.reduce(0, +)
                let rows = counts.map { ($0 + perRow - 1) / perRow }.max() ?? 1
                return (perRow, min(62, (geometry.size.width - plusWidth) / CGFloat(max(columns, 1)), geometry.size.height / CGFloat(max(rows, 1))))
            }.max { $0.size < $1.size } ?? (perRow: 5, size: 20)
            HStack(spacing: 0) {
                ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                    if index > 0 { Text("＋").font(.penguin(18)).foregroundStyle(Color.penguinInk).frame(width: 22) }
                    VStack(spacing: 0) {
                        ForEach(0..<((count + layout.perRow - 1) / layout.perRow), id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<min(layout.perRow, count - row * layout.perRow), id: \.self) { _ in
                                    PenguinHoppingArt(name: question.illustration, size: layout.size, onTap: onTap)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct PenguinHoppingArt: View {
    let name: String
    let size: CGFloat
    let onTap: () -> Void
    @State private var hops = 0

    var body: some View {
        PenguinArt.view(name, size: size)
            .keyframeAnimator(initialValue: CGFloat(0), trigger: hops) { view, lift in
                view.offset(y: -lift).scaleEffect(x: 1 - lift / size * 0.15, y: 1 + lift / size * 0.2, anchor: .bottom)
            } keyframes: { _ in
                SpringKeyframe(size * 0.35, duration: 0.12)
                SpringKeyframe(0, duration: 0.3, spring: .bouncy)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                hops += 1
                onTap()
            }
    }
}

/// 3Dの上に出る文字：濃い影と、アクセント色の淡いグロー。
private struct PenguinPopView: View {
    let pop: PenguinPop
    @State private var rise = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon = pop.icon { PenguinArt.view(icon, size: pop.big ? 52 : 42) }
            Text(pop.text)
        }
            .font(.penguin(pop.big ? 44 : 36))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.85), radius: 0, x: 0, y: 3)
            .shadow(color: Color.penguinAmber.opacity(0.65), radius: 12)
            .fixedSize()
            .scaleEffect(rise ? 1 : 0.5)
            .opacity(rise ? 0 : 1)
            .position(x: pop.position.x, y: pop.position.y - (rise ? 70 : 0))
            .onAppear {
                withAnimation(.easeOut(duration: 1.4)) { rise = true }
            }
    }
}

/// はじめての説明：指のイラスト（ci/generate-illustrations.py の finger）でタップや運び方を見せる。
/// 指先が絵の上端の中央にあるので、指先が from（や to）に来るように置く。
private struct PenguinTutorialView: View {
    let step: PenguinTutorial
    let food: PenguinFood
    let from: CGPoint?
    let to: CGPoint?
    private static let finger: CGFloat = 76

    var caption: String {
        switch step {
        case .tapAnswer: "こたえの こおりを タッチ"
        case .feed: "\(food.name)を おくちへ はこんでね"
        case .back: ""
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let from {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        if let to {
                            // 置き場から口へ運ぶ：つまむ → 運ぶ → 離す、をくり返す。
                            let cycle = t.truncatingRemainder(dividingBy: 2.2) / 2.2
                            let k = min(max((cycle - 0.15) / 0.6, 0), 1)
                            let eased = k * k * (3 - 2 * k)
                            let point = CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
                            let visible = cycle < 0.9
                            ZStack {
                                PenguinArt.view(food.asset, size: 40).position(x: point.x, y: point.y - 6)
                                fingerView(at: point, pressed: true)
                            }
                            .opacity(visible ? 1 : 0)
                        } else {
                            // タップ：指が少し沈んで、指先から輪が広がる。
                            let cycle = t.truncatingRemainder(dividingBy: 1.2) / 1.2
                            let ring = min(max((cycle - 0.25) / 0.6, 0), 1)
                            ZStack {
                                Circle().strokeBorder(Color.white, lineWidth: 4)
                                    .frame(width: 20 + 50 * ring, height: 20 + 50 * ring)
                                    .opacity(cycle > 0.25 ? 1 - ring : 0)
                                    .position(from)
                                fingerView(at: from, pressed: cycle > 0.15 && cycle < 0.45)
                            }
                        }
                    }
                }
                if !caption.isEmpty, from != nil {
                    Text(caption)
                        .font(.penguin(22))
                        .foregroundStyle(Color.penguinInk)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .modifier(PenguinCard(radius: 18))
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 110)
                }
            }
        }
    }

    private func fingerView(at point: CGPoint, pressed: Bool) -> some View {
        PenguinArt.view("finger", size: Self.finger)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
            .scaleEffect(pressed ? 0.9 : 1, anchor: .top)
            .position(x: point.x + 2, y: point.y + Self.finger / 2 + (pressed ? 2 : 10))
    }
}

private struct PenguinSettingsView: View {
    let game: PenguinGame
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var hud = game.hud
        NavigationStack {
            Form {
                Section("あそび") {
                    Toggle("おと・よみあげ", isOn: Binding(get: { hud.soundOn }, set: { game.setSound($0) }))
                    Toggle("カメラの回り込み", isOn: $hud.autoOrbit)
                }
                Section {
                    Toggle("ミニチュア風のぼかし", isOn: $hud.depthOfField)
                } header: {
                    Text("見た目")
                } footer: {
                    Text("動きが重いときはオフにしてください。")
                }
            }
            .navigationTitle("おうちのひと向け")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("とじる") { dismiss() } } }
        }
    }
}
