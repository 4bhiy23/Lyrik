import SwiftUI

// MARK: Branches

struct BranchesStyleView: View {
    var ctx: StyleContext

    var body: some View {
        let f = ctx.frame
        let words = ctx.words(of: f.current)
        let seed = f.index ?? 0
        Canvas { g, size in
            guard !words.isEmpty else { return }
            var rng = SeededRandom(seed * 17 + 3)
            let n = words.count
            let left = size.width * 0.1, right = size.width * 0.9
            // A wavy trunk through node points.
            var nodes: [CGPoint] = []
            for k in 0..<n {
                let x = n == 1 ? size.width / 2 : left + (right - left) * CGFloat(k) / CGFloat(n - 1)
                let y = size.height * 0.55 + CGFloat(sin(Double(k) * 1.3 + Double(seed)) * 0.09 + (rng.next() - 0.5) * 0.06) * size.height
                nodes.append(CGPoint(x: x, y: y))
            }
            var trunk = Path()
            trunk.move(to: CGPoint(x: 0, y: nodes[0].y))
            var prev = CGPoint(x: 0, y: nodes[0].y)
            for p in nodes + [CGPoint(x: size.width, y: nodes[n - 1].y)] {
                let c = CGPoint(x: (prev.x + p.x) / 2, y: prev.y)
                let c2 = CGPoint(x: (prev.x + p.x) / 2, y: p.y)
                trunk.addCurve(to: p, control1: c, control2: c2)
                prev = p
            }
            // Ghost of the whole path, then the sung part.
            g.stroke(trunk, with: .color(ctx.theme.secondary.opacity(0.18)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let drawn = trunk.trimmedPath(from: 0, to: min(1, 0.06 + f.lineProgress * 0.94))
            g.stroke(drawn, with: .linearGradient(Gradient(colors: [ctx.theme.accent.opacity(0.3), ctx.theme.highlight]),
                                                  startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                     style: StrokeStyle(lineWidth: ctx.compact ? 2 : 3.5, lineCap: .round))

            let font = ctx.theme.font(ctx.base * 0.95, weight: .bold)
            for (k, (i, w)) in words.enumerated() {
                let p = f.progress(ofWord: i)
                let pt = nodes[k]
                let lit = p > 0
                // Twig up or down from each node.
                let up = k % 2 == 0
                let twigLen = size.height * (0.12 + 0.05 * CGFloat(k % 3))
                let tip = CGPoint(x: pt.x + (up ? 14 : -14), y: pt.y + (up ? -twigLen : twigLen))
                if lit {
                    var twig = Path()
                    twig.move(to: pt)
                    twig.addQuadCurve(to: tip, control: CGPoint(x: pt.x, y: (pt.y + tip.y) / 2))
                    g.stroke(twig.trimmedPath(from: 0, to: Ease.outCubic(p * 3)), with: .color(ctx.theme.highlight.opacity(0.6)), lineWidth: 1.5)
                }
                let r: CGFloat = (ctx.compact ? 3 : 6) * (lit ? 1 : 0.6)
                if lit {
                    g.drawLayer { l in
                        l.addFilter(.blur(radius: 8))
                        l.fill(Path(ellipseIn: CGRect(x: pt.x - r * 2, y: pt.y - r * 2, width: r * 4, height: r * 4)), with: .color(ctx.theme.accent))
                    }
                }
                g.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                       with: .color(lit ? .white : ctx.theme.secondary.opacity(0.4)))
                let label = g.resolve(Text(w.display).font(font).foregroundColor(lit ? ctx.theme.highlight : ctx.theme.secondary.opacity(0.3)))
                g.draw(label, at: CGPoint(x: tip.x, y: tip.y + (up ? -ctx.base * 0.5 : ctx.base * 0.5)), anchor: .center)
            }
        }
    }
}

// MARK: Wall

struct WallStyleView: View {
    var ctx: StyleContext

    var body: some View {
        let f = ctx.frame
        let size = ctx.base * 1.5
        let drift = ctx.reduceMotion ? 0 : sin(ctx.now * 0.18)
        let tilt = ctx.reduceMotion ? 0 : cos(ctx.now * 0.13)
        VStack(spacing: size * 0.5) {
            // Earlier lines stay on the wall, faded.
            VStack(spacing: size * 0.2) {
                ForEach(Array(recentLines(f).enumerated()), id: \.element.id) { k, line in
                    Text(line.text)
                        .font(ctx.theme.font(size * 0.5, weight: .heavy))
                        .foregroundStyle(ctx.theme.secondary.opacity(0.12 + 0.07 * Double(k)))
                        .lineLimit(1)
                }
            }

            FlowLayout(spacing: size * 0.3, lineSpacing: size * 0.1) {
                ForEach(ctx.words(of: f.current), id: \.0) { i, w in
                    let since = f.time - w.start
                    let landed = since >= 0
                    let t = Ease.outBack(since / 0.35)
                    Text(w.display)
                        .font(ctx.theme.font(size, weight: .black))
                        .foregroundStyle(ctx.theme.highlight)
                        .opacity(landed ? min(1, since / 0.12) : 0)
                        .scaleEffect(landed ? 1.8 - 0.8 * t : 1.8)
                        .blur(radius: landed ? max(0, 6 * (1 - t)) : 6)
                        .fixedSize()
                }
            }
            .padding(.horizontal, ctx.size.width * 0.1)
            .id(f.index ?? -1)
            .transition(.opacity)

            Spacer().frame(height: size * 1.2)
        }
        .frame(width: ctx.size.width, height: ctx.size.height)
        .rotation3DEffect(.degrees(drift * 14), axis: (x: 0.2, y: 1, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(tilt * 6), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .animation(.easeOut(duration: 0.4), value: f.index)
    }

    private func recentLines(_ f: LyricFrame) -> [LyricLine] {
        guard let i = f.index, i > 0 else { return [] }
        return f.lines[max(0, i - 3)..<i].filter { !$0.isBreak }
    }
}

// MARK: Messages

struct MessagesStyleView: View {
    var ctx: StyleContext

    var body: some View {
        let f = ctx.frame
        let size = max(10, ctx.base * 0.72)
        let end = f.index ?? -1
        let start = max(0, end - (ctx.compact ? 3 : 6))
        let upcoming = f.next
        let typing = upcoming.map { f.time > $0.start - 1.3 && f.time < $0.start } ?? false
        let width = min(ctx.size.width * 0.9, size * 30)

        VStack(spacing: size * 0.4) {
            if !ctx.compact {
                VStack(spacing: size * 0.25) {
                    avatar(size * 2.8)
                    Text(ctx.artist.isEmpty ? "Now Playing" : ctx.artist)
                        .font(.system(size: size * 0.8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.bottom, size * 0.6)
            }
            VStack(spacing: size * 0.35) {
                if end >= 0 {
                    ForEach(start...end, id: \.self) { i in
                        let line = f.lines[i]
                        if !line.isBreak {
                            bubble(line.text, outgoing: i % 3 == 2, size: size, current: i == end)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.85, anchor: .bottom)),
                                                        removal: .opacity))
                        }
                    }
                }
                if typing, let upcoming {
                    typingBubble(size: size, outgoing: upcoming.id % 3 == 2)
                        .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .frame(width: width)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: f.index)
        .animation(.easeOut(duration: 0.2), value: typing)
    }

    @ViewBuilder private func avatar(_ d: CGFloat) -> some View {
        if let art = ctx.artwork {
            Image(nsImage: art).resizable().scaledToFill().frame(width: d, height: d).clipShape(Circle())
        } else {
            Circle().fill(LinearGradient(colors: [Color(white: 0.6), Color(white: 0.4)], startPoint: .top, endPoint: .bottom))
                .frame(width: d, height: d)
                .overlay(Image(systemName: "music.note").font(.system(size: d * 0.4, weight: .semibold)).foregroundStyle(.white))
        }
    }

    private func bubble(_ text: String, outgoing: Bool, size: CGFloat, current: Bool) -> some View {
        HStack {
            if outgoing { Spacer(minLength: size * 4) }
            Text(text)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(outgoing ? Color.white : Color.white.opacity(0.95))
                .padding(.horizontal, size * 0.75)
                .padding(.vertical, size * 0.45)
                .background(
                    RoundedRectangle(cornerRadius: size * 1.05, style: .continuous)
                        .fill(outgoing ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(white: 0.23))
                )
                .opacity(current ? 1 : 0.8)
            if !outgoing { Spacer(minLength: size * 4) }
        }
    }

    private func typingBubble(size: CGFloat, outgoing: Bool) -> some View {
        HStack {
            if outgoing { Spacer() }
            HStack(spacing: size * 0.25) {
                ForEach(0..<3) { k in
                    Circle()
                        .fill(Color.white.opacity(0.4 + 0.5 * (0.5 + 0.5 * sin(ctx.now * 6 - Double(k)))))
                        .frame(width: size * 0.45, height: size * 0.45)
                }
            }
            .padding(.horizontal, size * 0.7)
            .padding(.vertical, size * 0.55)
            .background(Capsule().fill(outgoing ? Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.7) : Color(white: 0.23)))
            if !outgoing { Spacer() }
        }
    }
}

// MARK: Notifications

struct NotificationsStyleView: View {
    var ctx: StyleContext

    var body: some View {
        let f = ctx.frame
        let size = max(9, ctx.base * 0.62)
        let end = f.index ?? -1
        let sung = end >= 0 ? f.lines[max(0, end - 3)...end].filter { !$0.isBreak } : []
        let width = min(ctx.size.width * 0.9, size * 32)

        ZStack(alignment: .top) {
            ForEach(Array(sung.reversed().enumerated()), id: \.element.id) { depth, line in
                card(line, size: size, width: width, ago: f.time - line.start)
                    .offset(y: CGFloat(depth) * size * 0.9)
                    .scaleEffect(1 - CGFloat(depth) * 0.05, anchor: .top)
                    .opacity(depth == 0 ? 1 : max(0, 0.75 - Double(depth) * 0.22))
                    .zIndex(Double(10 - depth))
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 1.08, anchor: .top)),
                                            removal: .opacity))
            }
        }
        .frame(width: width, height: size * 9, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: f.index)
    }

    private func card(_ line: LyricLine, size: CGFloat, width: CGFloat, ago: Double) -> some View {
        HStack(alignment: .top, spacing: size * 0.8) {
            Group {
                if let art = ctx.artwork {
                    Image(nsImage: art).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: "music.note").foregroundStyle(.white).font(.system(size: size * 1.2, weight: .bold)))
                }
            }
            .frame(width: size * 2.6, height: size * 2.6)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.6, style: .continuous))

            VStack(alignment: .leading, spacing: size * 0.15) {
                HStack {
                    Text(ctx.title.isEmpty ? "Now Playing" : ctx.title)
                        .font(.system(size: size, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(ago < 3 ? "now" : "\(Int(ago))s ago")
                        .font(.system(size: size * 0.85))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(line.text)
                    .font(.system(size: size, weight: .regular))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
        }
        .padding(size * 0.9)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: size * 1.6, style: .continuous)
                .fill(Color(white: 0.16).opacity(0.82))
                .overlay(RoundedRectangle(cornerRadius: size * 1.6, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}
