import AppKit
import NaturalLanguage

/// Finds an SF Symbol that pictures a lyric word ("rain" → cloud.rain.fill), or nil.
/// Sources, in order: a hand-written table, symbol names themselves, the system's own
/// symbol search keywords, and finally the nearest English neighbours of the word.
final class WordVisualResolver {
    static let shared = WordVisualResolver()

    private let lock = NSLock()
    private var memo: [String: String?] = [:]
    private var nameIndex: [String: String] = [:]          // "moon" → "moon.fill"
    private var keywordIndex: [String: [String]] = [:]     // "weather" → [...]
    private var embedding: NLEmbedding?
    private var loaded = false

    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "of", "to", "in", "on", "at", "by", "for", "with", "from", "up", "down",
        "is", "am", "are", "was", "were", "be", "been", "being", "do", "does", "did", "have", "has", "had", "i", "me", "my",
        "you", "your", "he", "she", "it", "we", "they", "them", "us", "his", "her", "its", "our", "their", "this", "that",
        "these", "those", "so", "no", "not", "yeah", "oh", "ooh", "ah", "na", "la", "just", "like", "all", "can", "will",
        "would", "could", "should", "what", "when", "where", "who", "how", "why", "there", "here", "then", "than", "too",
        "im", "dont", "cant", "wont", "aint", "gonna", "wanna", "gotta", "let", "get", "got", "go", "come", "know", "say",
        "one", "out", "over", "into", "off", "back", "now", "way", "make", "made", "take", "every", "some", "more",
    ]

    /// Words whose best picture is not obvious from symbol names.
    private static let curated: [String: String] = [
        "love": "heart.fill", "heart": "heart.fill", "hearts": "heart.fill", "kiss": "heart.circle.fill",
        "broken": "heart.slash.fill", "sun": "sun.max.fill", "sunshine": "sun.max.fill", "summer": "sun.max.fill",
        "rain": "cloud.rain.fill", "storm": "cloud.bolt.rain.fill", "thunder": "cloud.bolt.fill", "snow": "snowflake",
        "night": "moon.stars.fill", "moon": "moon.fill", "stars": "star.fill", "star": "star.fill", "sky": "cloud.fill",
        "fire": "flame.fill", "burn": "flame.fill", "burning": "flame.fill", "money": "dollarsign.circle.fill",
        "cash": "banknote.fill", "rich": "dollarsign.circle.fill", "gold": "medal.fill", "diamond": "diamond.fill",
        "car": "car.fill", "drive": "car.fill", "driving": "car.fill", "road": "road.lanes", "phone": "phone.fill",
        "call": "phone.fill", "music": "music.note", "song": "music.note", "sing": "music.mic", "singing": "music.mic",
        "dance": "figure.dance", "dancing": "figure.dance", "home": "house.fill", "house": "house.fill",
        "world": "globe.americas.fill", "earth": "globe.americas.fill", "time": "clock.fill", "clock": "clock.fill",
        "eyes": "eye.fill", "eye": "eye.fill", "see": "eye.fill", "look": "eye.fill", "hear": "ear.fill",
        "fly": "airplane", "flying": "airplane", "plane": "airplane", "ocean": "water.waves", "sea": "water.waves",
        "water": "drop.fill", "tears": "drop.fill", "cry": "drop.fill", "crying": "drop.fill", "party": "party.popper.fill",
        "king": "crown.fill", "queen": "crown.fill", "crown": "crown.fill", "key": "key.fill", "lock": "lock.fill",
        "light": "lightbulb.fill", "lights": "lightbulb.fill", "dark": "moon.fill", "city": "building.2.fill",
        "game": "gamecontroller.fill", "play": "play.fill", "coffee": "cup.and.saucer.fill", "wine": "wineglass.fill",
        "drink": "wineglass.fill", "gift": "gift.fill", "flower": "camera.macro", "flowers": "camera.macro",
        "smile": "face.smiling.fill", "happy": "face.smiling.fill", "run": "figure.run", "running": "figure.run",
        "walk": "figure.walk", "walking": "figure.walk", "door": "door.left.hand.open", "bed": "bed.double.fill",
        "sleep": "bed.double.fill", "dream": "moon.zzz.fill", "dreams": "moon.zzz.fill", "wind": "wind",
        "rainbow": "rainbow", "lightning": "bolt.fill", "electric": "bolt.fill", "paper": "doc.fill", "book": "book.fill",
        "camera": "camera.fill", "picture": "photo.fill", "photo": "photo.fill", "radio": "radio.fill", "tv": "tv.fill",
        "mountain": "mountain.2.fill", "tree": "tree.fill", "leaf": "leaf.fill", "bird": "bird.fill", "fish": "fish.fill",
        "dog": "dog.fill", "cat": "cat.fill", "hand": "hand.raised.fill", "hands": "hands.and.sparkles.fill",
        "voice": "waveform", "loud": "speaker.wave.3.fill", "quiet": "speaker.slash.fill", "silence": "speaker.slash.fill",
        "beach": "beach.umbrella.fill", "ship": "ferry.fill", "boat": "sailboat.fill", "train": "tram.fill",
        "bike": "bicycle", "school": "graduationcap.fill", "angel": "sparkles", "magic": "wand.and.stars",
        "ring": "circle.circle", "chain": "link", "war": "shield.fill", "gun": "scope", "heaven": "cloud.sun.fill",
        "cold": "thermometer.snowflake", "hot": "thermometer.sun.fill", "alone": "person.fill", "friends": "person.2.fill",
        "together": "person.2.fill", "baby": "figure.and.child.holdinghands", "mind": "brain.head.profile",
        "think": "brain.head.profile", "brain": "brain.fill", "message": "message.fill", "text": "text.bubble.fill",
    ]

    func symbol(for rawWord: String) -> String? {
        let word = rawWord.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isLetter }
        guard word.count >= 2, !Self.stopwords.contains(word) else { return nil }

        lock.lock()
        if let hit = memo[word] { lock.unlock(); return hit }
        lock.unlock()

        let result = resolve(word)
        lock.lock(); memo[word] = result; lock.unlock()
        return result
    }

    private func resolve(_ word: String) -> String? {
        if let c = Self.curated[word], exists(c) { return c }
        loadIfNeeded()
        let lemma = Self.lemma(word)
        for w in [word, lemma] {
            if let c = Self.curated[w], exists(c) { return c }
            if let n = nameIndex[w] { return n }
            if let list = keywordIndex[w], let pick = best(list) { return pick }
        }
        // Nearest neighbours in meaning, only accepting close ones.
        if let embedding {
            for (neighbour, distance) in embedding.neighbors(for: lemma, maximumCount: 6) where distance < 0.9 {
                if let c = Self.curated[neighbour], exists(c) { return c }
                if let n = nameIndex[neighbour] { return n }
            }
        }
        return nil
    }

    private func best(_ symbols: [String]) -> String? {
        // Prefer short, filled, unbadged symbols.
        let sorted = symbols.sorted { a, b in
            func score(_ s: String) -> Int {
                var v = s.split(separator: ".").count * 10
                if s.hasSuffix(".fill") { v -= 6 }
                if s.contains("badge") || s.contains("slash") || s.contains("rtl") { v += 30 }
                return v
            }
            return score(a) < score(b)
        }
        return sorted.prefix(4).first(where: exists)
    }

    private func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private func loadIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_search.plist")
        if let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] {
            for (symbol, keywords) in dict {
                for k in keywords { keywordIndex[k.lowercased(), default: []].append(symbol) }
                let parts = symbol.split(separator: ".")
                if parts.count <= 2, let first = parts.first {
                    let key = String(first)
                    let candidate = parts.count == 1 ? symbol : (parts[1] == "fill" ? symbol : nil)
                    if let candidate, nameIndex[key] == nil || candidate.hasSuffix(".fill") { nameIndex[key] = candidate }
                }
            }
        }
        embedding = NLEmbedding.wordEmbedding(for: .english)
        Log.write("word visuals: index \(keywordIndex.count) terms, \(nameIndex.count) names, embedding \(embedding == nil ? "missing" : "ready")")
    }

    private static func lemma(_ word: String) -> String {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        let (tag, _) = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
        return tag?.rawValue.lowercased() ?? word
    }

    /// Warm the index off the main thread so the first lookup is instant.
    func preload() {
        DispatchQueue.global(qos: .utility).async { self.loadIfNeeded() }
    }
}
