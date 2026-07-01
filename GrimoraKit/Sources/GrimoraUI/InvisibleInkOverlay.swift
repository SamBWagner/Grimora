import SwiftUI

/// The invisible-ink / "dossier" treatment: a detective's foil scrawl — rows of illegible cursive
/// notes plus a few doodles (magnifier, circled word, arrow) — that sit nearly invisible on the
/// card and only catch the light where a moving reveal-sweep crosses them. Procedural handwriting
/// can't be a pixel shader, so this is a SwiftUI layer: the scrawl `Shape` drawn dim everywhere
/// (baseline) with a brighter copy masked to a drifting diagonal band. Composited additively.
struct InvisibleInkOverlay: View {
    var cornerRadius: CGFloat
    /// Master strength (1.0 detail / lower for grids).
    var intensity: Double

    private static let rows = 8
    private static let strokeWidth: CGFloat = 1.3
    private static let reveal = 0.20
    private static let baseline = 0.08
    private static let sweepSpeed = 0.65
    private static let ink = Color(red: 0.94, green: 0.91, blue: 0.83)

    var body: some View {
        TimelineView(.animation) { timeline in
            let position = sweepPosition(timeline.date)
            scrawl
                .stroke(Self.ink.opacity(Self.baseline * intensity), lineWidth: Self.strokeWidth)
                .overlay {
                    scrawl
                        .stroke(Self.ink.opacity(Self.reveal * intensity), lineWidth: Self.strokeWidth)
                        .mask(revealBand(position))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var scrawl: DossierScrawlShape { DossierScrawlShape(rows: Self.rows) }

    private func sweepPosition(_ date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate * Self.sweepSpeed * 0.45
        return t - floor(t)
    }

    private func revealBand(_ position: Double) -> LinearGradient {
        let lo = max(0.0, position - 0.16)
        let hi = min(1.0, position + 0.16)
        let mid = min(max(position, lo), hi)
        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: lo),
                .init(color: .white, location: mid),
                .init(color: .clear, location: hi)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The deterministic dossier scrawl geometry: rows of wavy "cursive" strokes broken into word-like
/// segments, plus a magnifier, a circled word, and an arrow doodle. Illegible by design.
struct DossierScrawlShape: Shape {
    var rows: Int

    func path(in rect: CGRect) -> Path {
        func hsh(_ v: CGFloat) -> CGFloat { let s = sin(v * 127.1) * 43758.5453; return s - floor(s) }
        var path = Path()
        let w = rect.width, h = rect.height
        let count = max(1, rows)
        for i in 0..<count {
            let fi = CGFloat(i)
            let ry = 22 + (h - 44) * (fi + 0.6) / (CGFloat(count) + 0.2)
            let amp = 2.2 + 2.4 * hsh(fi * 3.1)
            var x = 16 + 12 * hsh(fi * 1.1)
            while x < w - 18 {
                let x0 = x
                let x1 = min(w - 18, x + 16 + 44 * hsh(fi * 3.3 + x))
                var xx = x0
                var started = false
                while xx <= x1 {
                    let yy = ry + amp * sin(xx * 0.45 + fi * 1.7) + amp * 0.6 * sin(xx * 1.1 + fi)
                    let point = CGPoint(x: xx, y: yy)
                    if started { path.addLine(to: point) } else { path.move(to: point); started = true }
                    xx += 3
                }
                x = x1 + 5 + 15 * hsh(fi * 5.1 + x)
            }
        }
        // Magnifier doodle.
        let mx = w * 0.66, my = h * 0.36, mr: CGFloat = 13
        path.addEllipse(in: CGRect(x: mx - mr, y: my - mr, width: mr * 2, height: mr * 2))
        path.move(to: CGPoint(x: mx + 9, y: my + 9)); path.addLine(to: CGPoint(x: mx + 20, y: my + 20))
        // Circled word.
        path.addEllipse(in: CGRect(x: w * 0.4 - 30, y: h * 0.72 - 12, width: 60, height: 24))
        // Arrow.
        let ax = w * 0.16, ay = h * 0.5
        path.move(to: CGPoint(x: ax, y: ay)); path.addLine(to: CGPoint(x: ax + 9, y: ay + 9))
        path.addLine(to: CGPoint(x: ax + 3, y: ay + 8))
        path.move(to: CGPoint(x: ax + 9, y: ay + 9)); path.addLine(to: CGPoint(x: ax + 8, y: ay + 2))
        return path
    }
}
