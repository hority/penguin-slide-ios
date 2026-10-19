import Foundation

enum PenguinMode: String, CaseIterable, Identifiable {
    case math, hiragana, katakana, alphabet
    var id: String { rawValue }

    var title: String {
        switch self {
        case .math: "かず"
        case .hiragana: "ひらがな"
        case .katakana: "カタカナ"
        case .alphabet: "えいご"
        }
    }

    var badge: String {
        switch self {
        case .math: "123"
        case .hiragana: "あいう"
        case .katakana: "アイウ"
        case .alphabet: "ABC"
        }
    }
}

struct PenguinSpeech {
    var text: String
    var language: String
    static func ja(_ text: String) -> PenguinSpeech { PenguinSpeech(text: text, language: "ja-JP") }
    static func en(_ text: String) -> PenguinSpeech { PenguinSpeech(text: text, language: "en-US") }
}

struct PenguinQuestion {
    /// 問題ごとに変わる識別子（カードの切り替えアニメーション用）。
    let id = UUID()
    var big: String
    /// 問題に添える絵（Illustrations内のファイル名）と、並べる数。かずのたし算は [2, 1] のように2組。
    var illustration: String
    var counts: [Int]
    var prompt: String
    var choices: [String]
    var answer: Int
    var dots: [Int]
    var ask: [PenguinSpeech]
    var praise: [PenguinSpeech]
    var hint: [PenguinSpeech]
}

/// 3歳向けの問題。正解数に応じて少しずつ範囲を広げる。
enum PenguinQuiz {
    private static let hiragana: [(String, String, String)] = [
        ("あ", "あり", "ant"), ("い", "いちご", "strawberry"), ("う", "うさぎ", "rabbit"), ("え", "えび", "shrimp"), ("お", "おにぎり", "riceball"),
        ("か", "かに", "crab"), ("き", "きりん", "giraffe"), ("く", "くま", "bear"), ("け", "けーき", "cake"), ("こ", "こあら", "koala"),
        ("さ", "さる", "monkey"), ("し", "しか", "deer"), ("す", "すいか", "watermelon"), ("た", "たこ", "octopus"), ("ち", "ちょうちょ", "butterfly"),
        ("つ", "つき", "moon"), ("て", "て", "hand"), ("と", "とまと", "tomato"), ("な", "なす", "eggplant"), ("に", "にんじん", "carrot"),
        ("ね", "ねこ", "cat"), ("は", "はな", "tulip"), ("ひ", "ひよこ", "chick"), ("ふ", "ふね", "boat"), ("へ", "へび", "snake"),
        ("ほ", "ほし", "star"), ("み", "みかん", "orange"), ("む", "むし", "caterpillar"), ("め", "めがね", "glasses"), ("も", "もも", "peach"),
        ("や", "やま", "mountain"), ("ゆ", "ゆきだるま", "snowman"), ("ら", "らいおん", "lion"), ("り", "りんご", "apple"), ("れ", "れもん", "lemon"),
        ("ろ", "ろけっと", "rocket"), ("わ", "わに", "crocodile"),
    ]
    private static let katakana: [(String, String, String)] = [
        ("ア", "アイス", "icecream"), ("イ", "イルカ", "dolphin"), ("ウ", "ウマ", "horse"), ("エ", "エビ", "shrimp"), ("オ", "オバケ", "ghost"),
        ("カ", "カメ", "turtle"), ("キ", "キウイ", "kiwi"), ("ク", "クジラ", "whale"), ("ケ", "ケーキ", "cake"), ("コ", "コアラ", "koala"),
        ("サ", "サル", "monkey"), ("シ", "シマウマ", "zebra"), ("ス", "スイカ", "watermelon"), ("タ", "タコ", "octopus"), ("テ", "テレビ", "tv"),
        ("ト", "トマト", "tomato"), ("ナ", "ナス", "eggplant"), ("ニ", "ニンジン", "carrot"), ("ネ", "ネコ", "cat"), ("ハ", "ハチ", "bee"),
        ("ヒ", "ヒヨコ", "chick"), ("ヘ", "ヘビ", "snake"), ("ホ", "ホシ", "star"), ("ミ", "ミカン", "orange"), ("メ", "メロン", "melon"),
        ("モ", "モモ", "peach"), ("ヤ", "ヤギ", "goat"), ("ラ", "ライオン", "lion"), ("リ", "リンゴ", "apple"), ("レ", "レモン", "lemon"),
        ("ロ", "ロケット", "rocket"), ("ワ", "ワニ", "crocodile"),
    ]
    private static let alphabet: [(String, String, String)] = [
        ("A", "Apple", "apple"), ("B", "Bear", "bear"), ("C", "Cat", "cat"), ("D", "Dog", "dog"), ("E", "Egg", "egg"),
        ("F", "Fish", "fish"), ("G", "Grapes", "grapes"), ("H", "Hat", "hat"), ("I", "Ice cream", "icecream"), ("J", "Juice", "juice"),
        ("K", "Kite", "kite"), ("L", "Lion", "lion"), ("M", "Moon", "moon"), ("N", "Nose", "nose"), ("O", "Orange", "orange"),
        ("P", "Penguin", "penguin"), ("Q", "Queen", "queen"), ("R", "Rabbit", "rabbit"), ("S", "Sun", "sun"), ("T", "Tiger", "tiger"),
        ("U", "Umbrella", "umbrella"), ("V", "Violin", "violin"), ("W", "Whale", "whale"), ("Y", "Yo-yo", "yoyo"), ("Z", "Zebra", "zebra"),
    ]

    static func make(_ mode: PenguinMode, stars: Int, food: PenguinFood, avoiding previous: String?) -> PenguinQuestion {
        switch mode {
        case .math: return math(stars: stars, food: food, avoiding: previous)
        case .hiragana: return letters(hiragana, pool: stars < 6 ? 10 : hiragana.count, english: false, avoiding: previous)
        case .katakana: return letters(katakana, pool: stars < 6 ? 10 : katakana.count, english: false, avoiding: previous)
        case .alphabet: return letters(alphabet, pool: stars < 6 ? 8 : alphabet.count, english: true, avoiding: previous)
        }
    }

    /// 数えるのも、たし算も、いま遊んでいるキャラの好物。
    private static func math(stars: Int, food: PenguinFood, avoiding previous: String?) -> PenguinQuestion {
        let maximum = stars < 4 ? 3 : (stars < 10 ? 5 : 9)
        let addition = stars >= 6 && Double.random(in: 0...1) < 0.4
        var answer = 0, a = 0, b = 0
        repeat {
            if addition {
                answer = Int.random(in: 2...min(maximum, 5))
                a = Int.random(in: 1..<answer)
                b = answer - a
            } else {
                answer = Int.random(in: 1...maximum)
            }
        } while String(answer) == previous && maximum > 1
        var options = Set([answer])
        let range = 1...max(maximum, 3)
        while options.count < 3 { options.insert(Int.random(in: range)) }
        let choices = options.shuffled()
        let dots = stars < 10 ? choices : [0, 0, 0]
        if addition {
            return PenguinQuestion(
                big: "", illustration: food.asset, counts: [a, b], prompt: "\(a) ＋ \(b) は？",
                choices: choices.map(String.init), answer: choices.firstIndex(of: answer) ?? 0, dots: dots,
                ask: [.ja("\(a)\(food.counter)と、\(b)\(food.counter)。あわせて、\(food.howMany) かな？")],
                praise: [.ja("せいかい！ あわせて \(answer)！")],
                hint: [.ja("あれれ？ \(answer) は こっちだよ")])
        }
        return PenguinQuestion(
            big: "", illustration: food.asset, counts: [answer], prompt: "\(food.name) \(food.howMany)？",
            choices: choices.map(String.init), answer: choices.firstIndex(of: answer) ?? 0, dots: dots,
            ask: [.ja("\(food.name)、\(food.howMany) \(food.counter == "ひき" ? "いる" : "ある")かな？")],
            praise: [.ja("せいかい！ \(answer)！")],
            hint: [.ja("あれれ？ \(answer) は こっちだよ")])
    }

    private static func letters(_ list: [(String, String, String)], pool: Int, english: Bool, avoiding previous: String?) -> PenguinQuestion {
        let candidates = Array(list.prefix(pool))
        var target = candidates.randomElement()!
        while target.0 == previous { target = candidates.randomElement()! }
        var choices = [target.0]
        while choices.count < 3 {
            let other = candidates.randomElement()!.0
            if !choices.contains(other) { choices.append(other) }
        }
        choices.shuffle()
        let (letter, word, illustration) = target
        let ask: [PenguinSpeech] = english
            ? [.en("Find the letter \(letter)."), .en("\(letter), \(word).")]
            : [.ja("\(word) の、「\(letter)」は どれ？")]
        let praise: [PenguinSpeech] = english
            ? [.ja("せいかい！"), .en("\(letter)! \(word)!")]
            : [.ja("せいかい！ \(word) の \(letter)！")]
        return PenguinQuestion(
            big: letter, illustration: illustration, counts: [1], prompt: english ? "\(word) の \(letter) は どれ？" : "\(word) の「\(letter)」は どれ？",
            choices: choices, answer: choices.firstIndex(of: letter) ?? 0, dots: [0, 0, 0],
            ask: ask, praise: praise, hint: [.ja("あれれ？ こっちだよ")] + (english ? [.en(letter)] : [.ja(letter)]))
    }
}

/// あそぶキャラ。タイトル画面で選び、次回も同じキャラで始める。
enum PenguinCharacter: String, CaseIterable, Identifiable {
    case penguin, octopus, ghost, unicorn
    var id: String { rawValue }

    var name: String {
        switch self {
        case .penguin: "ペンギン"
        case .octopus: "タコ"
        case .ghost: "オバケ"
        case .unicorn: "ユニコーン"
        }
    }

    /// 選択ボタンに使う同梱イラスト。
    var illustration: String { rawValue }
}
