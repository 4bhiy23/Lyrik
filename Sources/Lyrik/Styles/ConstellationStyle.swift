import SwiftUI

/// A night sky drawn from the line being sung. Each word becomes a gold star with its label
/// as it is sung; a camera stays close, gliding from star to star and punching in on every
/// hit, while the sky drifts slightly in 3D. Only the current line is ever on screen: when
/// the next one starts, the old constellation dissolves and the new one ignites in place.
struct ConstellationStyleView: View {
    var ctx: StyleContext

    /// Warm gold used for stars, labels and links.
    static let gold = Color(red: 0.86, green: 0.70, blue: 0.47)

    var body: some View {
        let f = ctx.frame
        let line = f.index.flatMap { f.lines[$0].isBreak ? nil : $0 }
        let yaw = ctx.reduceMotion ? 0 : sin(ctx.now * 0.17) * 10
        let pitch = ctx.reduceMotion ? 0 : cos(ctx.now * 0.13) * 6

        ZStack {
            Starfield(now: ctx.now, drift: CGFloat(f.time) * ctx.base * 0.4, compact: ctx.compact)

            if let line {
                ConstellationLine(ctx: ctx, lineIndex: line)
                    .id(line)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.12)),
                        removal: .opacity.combined(with: .scale(scale: 0.9))))
            }
        }
        .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
        .animation(.easeInOut(duration: 0.55), value: line)
    }
}

/// One line's constellation. It always draws its own line (`lineIndex`), so while it is
/// fading out it keeps showing the words it had, fully lit.
private struct ConstellationLine: View {
    var ctx: StyleContext
    var lineIndex: Int

    var body: some View {
        let f = ctx.frame
        let line = f.lines[lineIndex]
        let sky = SkyLine.build(line: line, unit: ctx.base)
        let t = f.index == lineIndex ? f.time : max(f.time, (line.words.last?.end ?? line.end) + 0.5)
        let active = sky.nodes.last(where: { $0.start <= t })?.id
        let cam = camera(sky: sky, time: t, active: active)
        let ink = ctx.theme.textIsDefault ? ConstellationStyleView.gold : ctx.theme.text
        let accent = ctx.theme.accent

        Canvas { g, size in
            g.translateBy(x: size.width / 2, y: size.height / 2)
            g.scaleBy(x: cam.zoom, y: cam.zoom)
            g.translateBy(x: -cam.center.x, y: -cam.center.y)

            for link in sky.links {
                let a = sky.nodes[link.from].star, b = sky.nodes[link.to].star
                let reveal = CGFloat(Ease.outCubic((t - link.start) / 0.45))
                guard reveal > 0 else { continue }
                var path = Path()
                path.move(to: a)
                path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * reveal, y: a.y + (b.y - a.y) * reveal))
                g.stroke(path, with: .color(ink.opacity(0.38)), lineWidth: max(0.6, 1.2 / cam.zoom))
            }

            for node in sky.nodes {
                let since = t - node.start
                let sung = since >= 0
                let isActive = node.id == active
                let pop = sung ? Ease.outBack(since / 0.4) : 0

                let r = ctx.base * (isActive ? 0.26 : (sung ? 0.18 : 0.1)) * (0.6 + 0.4 * pop)
                if isActive {
                    let pulse = 1 + 0.3 * min(1, ctx.shake.energy) + 0.12 * sin(ctx.now * 7)
                    g.drawLayer { l in
                        l.addFilter(.blur(radius: r * 2.4))
                        l.fill(circle(node.star, r * 2.5 * pulse), with: .color(accent.opacity(0.9)))
                    }
                    g.fill(circle(node.star, r * 0.95), with: .color(accent))
                    g.fill(circle(node.star, r * 0.4), with: .color(.white.opacity(0.92)))
                    // A ring that bursts outward as the word lands.
                    if since < 0.5 {
                        let ring = r * (1.2 + CGFloat(since) * 9)
                        g.stroke(circle(node.star, ring), with: .color(accent.opacity(0.6 * (1 - since / 0.5))), lineWidth: max(0.8, r * 0.18))
                    }
                } else {
                    g.fill(sparkle(at: node.star, radius: r * 1.6), with: .color(ink.opacity(sung ? 0.95 : 0.3)))
                }

                guard sung else { continue }
                let size: CGFloat = isActive ? 1.15 : (node.isKeyWord ? 0.72 : 0.46)
                let weight: Font.Weight = isActive || node.isKeyWord ? .heavy : .bold
                let label = g.resolve(Text(node.text)
                    .font(ctx.theme.font(ctx.base * size, weight: weight))
                    .foregroundColor(ink.opacity((isActive ? 1 : 0.9) * min(1, 0.3 + pop))))
                if isActive {
                    g.drawLayer { l in
                        l.addFilter(.shadow(color: ink.opacity(0.6), radius: ctx.base * 0.35))
                        l.draw(label, at: node.label, anchor: node.labelAnchor)
                    }
                } else {
                    g.draw(label, at: node.label, anchor: node.labelAnchor)
                }
            }
        }
    }

    // MARK: Camera

    struct Camera { var center: CGPoint; var zoom: CGFloat }

    /// Stays close and follows the live word. It never pulls back between lines: a new line
    /// starts framed on its first star. Each hit adds a small zoom punch.
    private func camera(sky: SkyLine, time t: Double, active: Int?) -> Camera {
        guard !sky.nodes.isEmpty else { return Camera(center: .zero, zoom: 1) }
        let fit = min(ctx.size.width * 0.8 / max(1, sky.bounds.width), ctx.size.height * 0.6 / max(1, sky.bounds.height))
        let close: CGFloat = ctx.compact ? 1.25 : 1.6
        // Always a little tighter than "fit", so the camera has room to travel.
        let zoom = max(min(close, fit * 1.45), min(close, 0.9)) * (1 + 0.05 * CGFloat(min(1.5, ctx.shake.energy)))

        let first = sky.nodes[0]
        guard let active else { return Camera(center: first.star, zoom: zoom) }
        let node = sky.nodes[active]
        let from = active > 0 ? sky.nodes[active - 1].star : first.star
        let glide = CGFloat(Ease.inOut((t - node.start) / 0.5))
        let focus = CGPoint(x: from.x + (node.star.x - from.x) * glide, y: from.y + (node.star.y - from.y) * glide)
        // Lead slightly towards the word so its label sits near the centre.
        return Camera(center: CGPoint(x: focus.x + ctx.base * 0.9, y: focus.y), zoom: zoom)
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// Four-pointed star.
    private func sparkle(at c: CGPoint, radius r: CGFloat) -> Path {
        var p = Path()
        let inner = r * 0.22
        for k in 0..<8 {
            let angle = Double(k) * .pi / 4 - .pi / 2
            let len = k % 2 == 0 ? r : inner
            let pt = CGPoint(x: c.x + CGFloat(cos(angle)) * len, y: c.y + CGFloat(sin(angle)) * len)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Distant twinkling stars that slide slowly as the song plays.
private struct Starfield: View {
    var now: Double
    var drift: CGFloat
    var compact: Bool

    var body: some View {
        Canvas { g, size in
            var rng = SeededRandom(11)
            for _ in 0..<(compact ? 30 : 120) {
                let depth = 0.2 + rng.next() * 0.8
                var x = rng.next() * size.width - Double(drift) * depth * 0.15
                let y = rng.next() * size.height
                x = x.truncatingRemainder(dividingBy: size.width); if x < 0 { x += size.width }
                let twinkle = 0.1 + 0.25 * (0.5 + 0.5 * sin(now * (0.5 + rng.next()) + rng.next() * 6))
                let r = 0.4 + rng.next() * 0.9
                g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(twinkle)))
            }
        }
    }
}

// MARK: Layout

/// Deterministic placement of one line's words, centred on the origin.
struct SkyLine {
    struct Node {
        var id: Int
        var text: String
        var start: Double
        var star: CGPoint
        var label: CGPoint
        var labelAnchor: UnitPoint
        var isKeyWord: Bool
    }

    struct Link { var from: Int; var to: Int; var start: Double }

    var nodes: [Node] = []
    var links: [Link] = []
    var bounds: CGRect = .zero

    static func build(line: LyricLine, unit u: CGFloat) -> SkyLine {
        var sky = SkyLine()
        let words = line.words.filter { !$0.display.isEmpty }
        guard !words.isEmpty else { return sky }
        var rng = SeededRandom(line.id &* 7919 &+ 13)
        let keyIndex = words.indices.max(by: { words[$0].display.count < words[$1].display.count }) ?? 0

        var x: CGFloat = 0
        var raw: [Node] = []
        for (k, w) in words.enumerated() {
            let width = CGFloat(w.display.count) * u * 0.3 + u * 1.7
            let star = CGPoint(x: x, y: CGFloat(rng.next() - 0.5) * u * 3.8)
            let above = rng.next() > 0.45
            raw.append(Node(id: k, text: w.display, start: w.start, star: star,
                            label: CGPoint(x: star.x + u * 0.32, y: star.y + (above ? -u * 0.45 : u * 0.45)),
                            labelAnchor: above ? .bottomLeading : .topLeading, isKeyWord: k == keyIndex))
            if k > 0 {
                sky.links.append(Link(from: k - 1, to: k, start: w.start))
                if k > 1, rng.next() > 0.7 { sky.links.append(Link(from: k - 2, to: k, start: w.start + 0.15)) }
            }
            x += width
        }
        // Centre the constellation on the origin.
        let rect = raw.reduce(CGRect.null) { $0.union(CGRect(origin: $1.star, size: .zero)) }
        let shift = CGPoint(x: rect.midX, y: rect.midY)
        sky.nodes = raw.map { var n = $0
            n.star = CGPoint(x: n.star.x - shift.x, y: n.star.y - shift.y)
            n.label = CGPoint(x: n.label.x - shift.x, y: n.label.y - shift.y)
            return n
        }
        sky.bounds = rect.offsetBy(dx: -shift.x, dy: -shift.y).insetBy(dx: -u * 2, dy: -u * 1.5)
        return sky
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
