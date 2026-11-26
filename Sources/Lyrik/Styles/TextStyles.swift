import SwiftUI

// MARK: Stack

struct StackStyleView: View {
    var ctx: StyleContext

    var body: some View {
        let f = ctx.frame
        let size = ctx.base * 1.25
        VStack(spacing: size * 0.55) {
            Text(f.previous?.text ?? " ")
                .font(ctx.theme.font(size * 0.62, weight: .semibold))
                .foregroundStyle(ctx.theme.secondary.opacity(0.55))
                .blur(radius: ctx.compact ? 0.5 : 1.2)
                .lineLimit(2)

            FlowLayout(spacing: size * 0.28, lineSpacing: size * 0.12) {
                ForEach(ctx.words(of: f.current), id: \.0) { i, w in
                    KaraokeWord(text: w.display, progress: f.progress(ofWord: i), font: ctx.theme.font(size),
                                base: ctx.theme.secondary, fill: ctx.theme.highlight, lift: !ctx.reduceMotion)
                }
            }
            .id(f.index ?? -1)
            .transition(.asymmetric(insertion: .offset(y: size * 0.9).combined(with: .opacity),
                                    removal: .offset(y: -size * 0.9).combined(with: .opacity)))

            Text(f.next?.text ?? " ")
                .font(ctx.theme.font(size * 0.62, weight: .semibold))
                .foregroundStyle(ctx.theme.secondary.opacity(0.7))
                .lineLimit(2)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, ctx.size.width * 0.08)
        .animation(ctx.reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: f.index)
    }
}

// MARK: Visual (words with icons)

struct VisualStyleView: View {
    var ctx: StyleContext

    var body: some View {
        let f = ctx.frame
        let size = ctx.base * 1.3
        VStack(spacing: size * 0.4) {
            FlowLayout(spacing: size * 0.35, lineSpacing: size * 0.3) {
                let words = ctx.words(of: f.current)
                let symbols = Self.icons(for: words.map(\.1.display))
                ForEach(Array(words.enumerated()), id: \.element.0) { k, item in
                    let (i, w) = item
                    let p = f.progress(ofWord: i)
                    let reached = p > 0
                    HStack(spacing: size * 0.18) {
                        if let symbol = symbols[k] {
                            Image(systemName: symbol)
                                .font(.system(size: size * 0.85, weight: .semibold))
                                .foregroundStyle(ctx.theme.accent.gradient)
                                .symbolRenderingMode(.hierarchical)
                                .scaleEffect(reached ? 1 : 0.4)
                                .opacity(reached ? 1 : 0)
                                .symbolEffect(.bounce, value: reached)
                        }
                        Text(w.display)
                            .font(ctx.theme.font(size))
                            .foregroundStyle(reached ? ctx.theme.highlight : ctx.theme.secondary.opacity(0.6))
                    }
                    .scaleEffect(i == f.wordIndex ? 1.06 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: reached)
                    .fixedSize()
                }
            }
            .id(f.index ?? -1)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .padding(.horizontal, ctx.size.width * 0.07)
        }
        .animation(.easeOut(duration: 0.35), value: f.index)
    }

    /// One icon per idea: a symbol is not repeated within a line.
    static func icons(for words: [String]) -> [String?] {
        var used = Set<String>()
        return words.map { w in
            guard let s = WordVisualResolver.shared.symbol(for: w), !used.contains(s) else { return nil }
            used.insert(s)
            return s
        }
    }
}

// MARK: Fisheye

struct FisheyeStyleView: View {
    var ctx: StyleContext

    var body: some View {
        let f = ctx.frame
        let words = f.current?.words.filter { !$0.display.isEmpty } ?? []
        let wi = f.wordIndex.map { idx in
            // Map index in the raw words array to the filtered one.
            (f.current?.words.prefix(idx + 1).filter { !$0.display.isEmpty }.count ?? 1) - 1
        } ?? -1
        let size = ctx.base * 2.1
        let rowHeight = size * 1.25
        // The sung word sits in the lens centre; the spring below glides between words.
        let scroll = Double(max(0, wi))
        let lens = min(ctx.size.width * 0.7, rowHeight * 3.6)

        ZStack {
            // A domed lens: the word in the middle is magnified, its neighbours
            // shrink and crowd towards the rim, like type seen through glass.
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                let d = Double(i) - scroll
                let ad = abs(d)
                let magnify = 0.42 + 0.78 * exp(-ad * ad * 0.85)
                let y = (d >= 0 ? 1.0 : -1.0) * (1 - exp(-ad * 0.95)) * Double(lens) * 0.46
                Text(w.display)
                    .font(ctx.theme.font(size, weight: .heavy))
                    .foregroundStyle(i == wi ? ctx.theme.highlight : ctx.theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(width: lens * 0.92)
                    .scaleEffect(x: magnify * (1 - min(ad, 3) * 0.04), y: magnify)
                    .offset(y: CGFloat(y))
                    .opacity(max(0, 1 - ad * 0.36))
            }
            .animation(ctx.reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78), value: wi)
            .id(f.index ?? -1)
            .transition(.opacity)
        }
        .frame(width: lens, height: lens)
        .mask(RadialGradient(colors: [.black, .black, .black.opacity(0)], center: .center, startRadius: 0, endRadius: lens / 2))
        .overlay {
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                .shadow(color: ctx.theme.accent.opacity(0.35), radius: 24)
        }
        .background {
            Circle().fill(RadialGradient(colors: [ctx.theme.accent.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: lens / 2))
        }
        .animation(.easeOut(duration: 0.3), value: f.index)
    }
}

// MARK: Codestyle

struct CodestyleStyleView: View {
    var ctx: StyleContext

    private static let keywords = ["let", "var", "func", "return", "await", "print"]

    var body: some View {
        let f = ctx.frame
        let size = ctx.base * 0.78
        let mono = Font.system(size: size * ctx.theme.scale, weight: .medium, design: .monospaced)
        let start = max(0, (f.index ?? 0) - 4)
        let end = f.index ?? -1
        let keyword = Color(red: 0.99, green: 0.37, blue: 0.64)
        let string = Color(red: 0.99, green: 0.42, blue: 0.36)
        let comment = Color(white: 0.5)
        let cursorOn = ctx.reduceMotion || Int(ctx.now * 2) % 2 == 0

        VStack(alignment: .leading, spacing: size * 0.55) {
            if end >= 0 {
                ForEach(start...end, id: \.self) { i in
                    let line = f.lines[i]
                    let isCurrent = i == end
                    HStack(alignment: .firstTextBaseline, spacing: size * 0.9) {
                        Text(String(format: "%3d", i + 1))
                            .foregroundStyle(comment.opacity(isCurrent ? 0.9 : 0.5))
                        if line.isBreak {
                            Text("// ♪").foregroundStyle(comment)
                        } else {
                            let typed = isCurrent ? typedText(line, frame: f) : line.text
                            (Text(Self.keywords[i % Self.keywords.count] + " ").foregroundColor(keyword)
                             + Text("line\(i + 1)").foregroundColor(ctx.theme.text.opacity(isCurrent ? 1 : 0.6))
                             + Text(" = \"").foregroundColor(string.opacity(isCurrent ? 1 : 0.55))
                             + Text(typed).foregroundColor(isCurrent ? ctx.theme.highlight : string.opacity(0.55))
                             + Text(isCurrent ? "" : "\"").foregroundColor(string.opacity(0.55)))
                            .lineLimit(2)
                            if isCurrent {
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: size * 0.55, height: size * 1.15)
                                    .opacity(cursorOn ? 1 : 0)
                                    .offset(x: -size * 0.8)
                            }
                        }
                    }
                    .opacity(isCurrent ? 1 : 0.75)
                }
            } else {
                Text("// waiting for the first line").foregroundStyle(comment)
            }
        }
        .font(mono)
        .frame(maxWidth: ctx.size.width * 0.8, alignment: .leading)
        .padding(size * 1.2)
        .background(RoundedRectangle(cornerRadius: size * 0.8).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: size * 0.8).strokeBorder(Color.white.opacity(0.08)))
        .animation(.easeOut(duration: 0.2), value: f.index)
    }

    private func typedText(_ line: LyricLine, frame: LyricFrame) -> String {
        // Reveal characters as the words are sung.
        var out = ""
        for (i, w) in line.words.enumerated() {
            let p = frame.progress(ofWord: i)
            if p <= 0 { break }
            let chars = Array(w.text)
            let n = p >= 1 ? chars.count : max(1, Int(Double(chars.count) * p))
            out += String(chars.prefix(n))
        }
        return out
    }
}

// MARK: Flashbang

struct FlashbangStyleView: View {
    var ctx: StyleContext

    var body: some View {
        let f = ctx.frame
        let word = f.wordIndex.flatMap { f.current?.words[$0] }
        let since = word.map { max(0, f.time - $0.start) } ?? 99
        // A brief, soft flash: capped well below full white and quickly decaying.
        let flash = ctx.reduceMotion ? 0 : max(0, 0.32 - since * 1.4)
        let pop = Ease.outBack(since / 0.22)
        let speed = max(0, 1 - since / 0.18)
        let size = min(ctx.size.width / 5.2, ctx.size.height / 3.2) * ctx.theme.scale

        ZStack {
            ctx.theme.accent.opacity(flash)
            if let word {
                let label = Text(word.display.uppercased())
                    .font(ctx.theme.font(size, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .padding(.horizontal, ctx.size.width * 0.06)
                ZStack {
                    // Motion streak: fading ghosts trailing the word as it slams in.
                    if speed > 0.01 && !ctx.reduceMotion {
                        ForEach(1..<5) { k in
                            label
                                .foregroundStyle(ctx.theme.highlight.opacity(0.22 * speed / Double(k)))
                                .offset(x: -CGFloat(speed * Double(k) * 18))
                                .blur(radius: CGFloat(k) * 1.5)
                        }
                    }
                    label.foregroundStyle(ctx.theme.highlight)
                }
                .scaleEffect(0.7 + 0.3 * pop)
                .id(word.start)
            }
            VStack {
                Spacer()
                Text(f.current?.text ?? "")
                    .font(ctx.theme.font(ctx.base * 0.55, weight: .semibold))
                    .foregroundStyle(ctx.theme.secondary)
                    .lineLimit(1)
                    .padding(.bottom, ctx.size.height * 0.08)
            }
        }
    }
}
