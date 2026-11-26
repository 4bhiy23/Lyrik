import SwiftUI

/// Everything a style needs for one rendered frame.
struct StyleContext {
    var frame: LyricFrame
    var theme: LyricTheme
    var size: CGSize
    var now: Double             // monotonic seconds, for ambient motion
    var compact: Bool           // gallery tile
    var title: String
    var artist: String
    var artwork: NSImage?
    var reduceMotion: Bool
    /// This frame's camera shake; styles may also use `shake.energy` to pulse.
    var shake: CameraShake = .still

    /// Base type size scaled to the canvas.
    var base: CGFloat {
        let s = min(size.width, size.height * 1.6)
        return max(9, s * (compact ? 0.052 : 0.045))
    }

    func words(of line: LyricLine?) -> [(Int, TimedWord)] {
        guard let line else { return [] }
        return Array(line.words.enumerated()).filter { !$0.element.display.isEmpty }
    }
}

/// Centered, wrapping row layout for words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.midX - row.width / 2
            }
            for item in row.items {
                let s = subviews[item].sizeThatFits(.unspecified)
                subviews[item].place(at: CGPoint(x: x, y: y + (row.height - s.height) / 2), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + s.width > maxWidth {
                rows.append(Row())
            }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + s.width
            r.height = max(r.height, s.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

/// A word that fills with the highlight color left-to-right as it is sung.
struct KaraokeWord: View {
    var text: String
    var progress: Double
    var font: Font
    var base: Color
    var fill: Color
    var lift: Bool = true

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(base)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(fill)
                    .mask {
                        Rectangle().scaleEffect(x: max(0.0001, progress), y: 1, anchor: .leading)
                    }
                    .shadow(color: fill.opacity(progress > 0 && progress < 1 ? 0.55 : 0), radius: 10)
            }
            .offset(y: lift ? -CGFloat(sin(min(1, progress) * .pi)) * 3 : 0)
            .fixedSize()
    }
}

/// Soft vignette behind the words so they read over any wallpaper.
struct LyricBackdrop: View {
    var color: Color
    var strength: Double
    var body: some View {
        ZStack {
            Color.black.opacity(0.25 * strength)
            RadialGradient(colors: [color.opacity(0.55 * strength), Color.black.opacity(0.55 * strength)],
                           center: .center, startRadius: 0, endRadius: 900)
        }
    }
}

/// Deterministic pseudo-random numbers so layouts stay put frame to frame.
struct SeededRandom {
    private var state: UInt64
    init(_ seed: Int) { state = UInt64(bitPattern: Int64(seed)) &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}

extension Double {
    func clamped(_ lo: Double = 0, _ hi: Double = 1) -> Double { Swift.min(hi, Swift.max(lo, self)) }
}

/// Ease curves for time-driven motion.
enum Ease {
    static func outCubic(_ t: Double) -> Double { let p = 1 - t.clamped(); return 1 - p * p * p }
    static func outBack(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1, x = t.clamped() - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }
    static func inOut(_ t: Double) -> Double { let x = t.clamped(); return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}
