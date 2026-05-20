import AppKit
import CoreGraphics
import Foundation

private let canvasSize = 1024
private let backgroundColor = Color(hex: "#422853")

private struct Color {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: String, alpha: CGFloat = 1) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(trimmed, radix: 16) ?? 0
        self.red = CGFloat((value >> 16) & 0xff) / 255
        self.green = CGFloat((value >> 8) & 0xff) / 255
        self.blue = CGFloat(value & 0xff) / 255
        self.alpha = alpha
    }

    func withAlpha(_ value: CGFloat) -> Color {
        Color(red, green, blue, value)
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct Point {
    let x: CGFloat
    let y: CGFloat
}

private let palette = (
    deepViolet: Color(hex: "#422853"),
    darkEggplant: Color(hex: "#24142D"),
    coverDark: Color(hex: "#3B2050"),
    coverMid: Color(hex: "#603482"),
    coverLight: Color(hex: "#8A62A8"),
    lavender: Color(hex: "#BB9CD1"),
    parchment: Color(hex: "#E6D9C2"),
    parchmentLight: Color(hex: "#FFF4D5"),
    parchmentShade: Color(hex: "#BAA77F"),
    gold: Color(hex: "#D1AD63"),
    tealDark: Color(hex: "#13717B"),
    tealMid: Color(hex: "#24C7C9"),
    tealLight: Color(hex: "#A9FFFA"),
    cyanGlow: Color(hex: "#D8FFFB"),
    stoneDark: Color(hex: "#8C8880"),
    stoneMid: Color(hex: "#D7D3C8"),
    stoneLight: Color(hex: "#F4F2EA")
)

private func imageContext(flipped: Bool = true, draw: (CGContext) -> Void) -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create CGContext")
    }

    context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    if flipped {
        context.translateBy(x: 0, y: CGFloat(canvasSize))
        context.scaleBy(x: 1, y: -1)
    }
    draw(context)

    guard let image = context.makeImage() else {
        fatalError("Could not create CGImage")
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    do {
        try data.write(to: url, options: .atomic)
    } catch {
        fatalError("Could not write \(url.path): \(error)")
    }
}

private func rgba(_ context: CGContext, _ color: Color) {
    context.setFillColor(color.cgColor)
    context.setStrokeColor(color.cgColor)
}

private func fillEllipse(_ context: CGContext, rect: CGRect, color: Color) {
    context.setFillColor(color.cgColor)
    context.fillEllipse(in: rect)
}

private func strokeEllipse(_ context: CGContext, rect: CGRect, color: Color, width: CGFloat) {
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(width)
    context.strokeEllipse(in: rect)
}

private func fillRoundedRect(_ context: CGContext, rect: CGRect, radius: CGFloat, color: Color) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.setFillColor(color.cgColor)
    context.addPath(path)
    context.fillPath()
}

private func strokeRoundedRect(_ context: CGContext, rect: CGRect, radius: CGFloat, color: Color, width: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(width)
    context.addPath(path)
    context.strokePath()
}

private func drawLinearGradient(
    _ context: CGContext,
    rect: CGRect,
    colors: [Color],
    locations: [CGFloat],
    start: CGPoint,
    end: CGPoint
) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: colors.map(\.cgColor) as CFArray,
        locations: locations
    )!
    context.saveGState()
    context.clip(to: rect)
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

private func drawPathLinearGradient(
    _ context: CGContext,
    path: CGPath,
    colors: [Color],
    locations: [CGFloat],
    start: CGPoint,
    end: CGPoint
) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: colors.map(\.cgColor) as CFArray,
        locations: locations
    )!
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

private func drawRadialGradient(
    _ context: CGContext,
    path: CGPath,
    center: CGPoint,
    startRadius: CGFloat,
    endRadius: CGFloat,
    colors: [Color],
    locations: [CGFloat]
) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: colors.map(\.cgColor) as CFArray,
        locations: locations
    )!
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: startRadius,
        endCenter: center,
        endRadius: endRadius,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()
}

private func drawShadowedPath(
    _ context: CGContext,
    path: CGPath,
    fill: Color,
    shadow: Color,
    offset: CGSize,
    blur: CGFloat
) {
    context.saveGState()
    context.setShadow(offset: offset, blur: blur, color: shadow.cgColor)
    context.setFillColor(fill.cgColor)
    context.addPath(path)
    context.fillPath()
    context.restoreGState()
}

private func strokePath(
    _ context: CGContext,
    path: CGPath,
    color: Color,
    width: CGFloat,
    cap: CGLineCap = .round,
    join: CGLineJoin = .round
) {
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(width)
    context.setLineCap(cap)
    context.setLineJoin(join)
    context.addPath(path)
    context.strokePath()
}

private func drawSpiral(
    _ context: CGContext,
    center: CGPoint,
    startRadius: CGFloat,
    endRadius: CGFloat,
    turns: CGFloat,
    phase: CGFloat,
    xScale: CGFloat,
    yScale: CGFloat,
    color: Color,
    width: CGFloat
) {
    let path = CGMutablePath()
    let steps = 260
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let ease = 1 - pow(1 - t, 1.7)
        let radius = startRadius + (endRadius - startRadius) * ease
        let theta = phase + turns * 2 * .pi * t
        let point = CGPoint(
            x: center.x + cos(theta) * radius * xScale,
            y: center.y + sin(theta) * radius * yScale
        )
        if i == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
    strokePath(context, path: path, color: color, width: width)
}

private func bookLeftPagePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 505, y: 287))
    path.addCurve(to: CGPoint(x: 325, y: 251), control1: CGPoint(x: 458, y: 254), control2: CGPoint(x: 382, y: 245))
    path.addCurve(to: CGPoint(x: 266, y: 305), control1: CGPoint(x: 295, y: 254), control2: CGPoint(x: 270, y: 273))
    path.addCurve(to: CGPoint(x: 287, y: 648), control1: CGPoint(x: 255, y: 415), control2: CGPoint(x: 260, y: 549))
    path.addCurve(to: CGPoint(x: 503, y: 714), control1: CGPoint(x: 344, y: 648), control2: CGPoint(x: 440, y: 666))
    path.closeSubpath()
    return path
}

private func bookRightPagePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 519, y: 287))
    path.addCurve(to: CGPoint(x: 699, y: 251), control1: CGPoint(x: 566, y: 254), control2: CGPoint(x: 642, y: 245))
    path.addCurve(to: CGPoint(x: 758, y: 305), control1: CGPoint(x: 729, y: 254), control2: CGPoint(x: 754, y: 273))
    path.addCurve(to: CGPoint(x: 737, y: 648), control1: CGPoint(x: 769, y: 415), control2: CGPoint(x: 764, y: 549))
    path.addCurve(to: CGPoint(x: 521, y: 714), control1: CGPoint(x: 680, y: 648), control2: CGPoint(x: 584, y: 666))
    path.closeSubpath()
    return path
}

private func bookLeftCoverPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 232, y: 291))
    path.addCurve(to: CGPoint(x: 468, y: 319), control1: CGPoint(x: 302, y: 264), control2: CGPoint(x: 404, y: 269))
    path.addCurve(to: CGPoint(x: 492, y: 722), control1: CGPoint(x: 474, y: 441), control2: CGPoint(x: 482, y: 597))
    path.addCurve(to: CGPoint(x: 180, y: 665), control1: CGPoint(x: 390, y: 674), control2: CGPoint(x: 283, y: 655))
    path.addCurve(to: CGPoint(x: 176, y: 343), control1: CGPoint(x: 166, y: 552), control2: CGPoint(x: 166, y: 427))
    path.addCurve(to: CGPoint(x: 232, y: 291), control1: CGPoint(x: 180, y: 314), control2: CGPoint(x: 199, y: 299))
    path.closeSubpath()
    return path
}

private func bookRightCoverPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 792, y: 291))
    path.addCurve(to: CGPoint(x: 556, y: 319), control1: CGPoint(x: 722, y: 264), control2: CGPoint(x: 620, y: 269))
    path.addCurve(to: CGPoint(x: 532, y: 722), control1: CGPoint(x: 550, y: 441), control2: CGPoint(x: 542, y: 597))
    path.addCurve(to: CGPoint(x: 844, y: 665), control1: CGPoint(x: 634, y: 674), control2: CGPoint(x: 741, y: 655))
    path.addCurve(to: CGPoint(x: 848, y: 343), control1: CGPoint(x: 858, y: 552), control2: CGPoint(x: 858, y: 427))
    path.addCurve(to: CGPoint(x: 792, y: 291), control1: CGPoint(x: 844, y: 314), control2: CGPoint(x: 825, y: 299))
    path.closeSubpath()
    return path
}

private func bookSpinePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 489, y: 291))
    path.addCurve(to: CGPoint(x: 512, y: 312), control1: CGPoint(x: 497, y: 298), control2: CGPoint(x: 505, y: 305))
    path.addCurve(to: CGPoint(x: 535, y: 291), control1: CGPoint(x: 519, y: 305), control2: CGPoint(x: 527, y: 298))
    path.addLine(to: CGPoint(x: 535, y: 721))
    path.addCurve(to: CGPoint(x: 512, y: 748), control1: CGPoint(x: 528, y: 734), control2: CGPoint(x: 521, y: 743))
    path.addCurve(to: CGPoint(x: 489, y: 721), control1: CGPoint(x: 503, y: 743), control2: CGPoint(x: 496, y: 734))
    path.closeSubpath()
    return path
}

private func drawSpark(
    _ context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    color: Color,
    lineWidth: CGFloat = 4
) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x, y: center.y - radius))
    path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
    path.move(to: CGPoint(x: center.x - radius, y: center.y))
    path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
    path.move(to: CGPoint(x: center.x - radius * 0.58, y: center.y - radius * 0.58))
    path.addLine(to: CGPoint(x: center.x + radius * 0.58, y: center.y + radius * 0.58))
    path.move(to: CGPoint(x: center.x + radius * 0.58, y: center.y - radius * 0.58))
    path.addLine(to: CGPoint(x: center.x - radius * 0.58, y: center.y + radius * 0.58))
    strokePath(context, path: path, color: color, width: lineWidth)
}

private func drawPortal() -> CGImage {
    imageContext { context in
        let center = CGPoint(x: 512, y: 476)
        let portalRect = CGRect(x: 178, y: 70, width: 668, height: 812)
        let portalPath = CGPath(ellipseIn: portalRect, transform: nil)

        drawRadialGradient(
            context,
            path: portalPath,
            center: center,
            startRadius: 18,
            endRadius: 415,
            colors: [
                palette.cyanGlow.withAlpha(0.98),
                palette.tealMid.withAlpha(0.96),
                palette.tealDark.withAlpha(0.96),
                Color(hex: "#2B8B99", alpha: 0.94)
            ],
            locations: [0.0, 0.30, 0.72, 1.0]
        )

        context.saveGState()
        context.addPath(portalPath)
        context.clip()

        for inset in stride(from: CGFloat(22), through: CGFloat(150), by: CGFloat(32)) {
            strokeEllipse(
                context,
                rect: portalRect.insetBy(dx: inset, dy: inset * 1.16),
                color: Color(hex: "#D8FFFB", alpha: 0.22),
                width: 3.5
            )
        }

        drawSpiral(
            context,
            center: center,
            startRadius: 44,
            endRadius: 352,
            turns: 1.12,
            phase: 0.22,
            xScale: 0.80,
            yScale: 1.12,
            color: palette.tealDark.withAlpha(0.42),
            width: 14
        )
        drawSpiral(
            context,
            center: center,
            startRadius: 60,
            endRadius: 340,
            turns: 1.22,
            phase: 2.30,
            xScale: 0.76,
            yScale: 1.08,
            color: palette.cyanGlow.withAlpha(0.38),
            width: 7
        )
        drawSpiral(
            context,
            center: center,
            startRadius: 66,
            endRadius: 324,
            turns: 1.32,
            phase: 4.38,
            xScale: 0.72,
            yScale: 1.05,
            color: Color(hex: "#FFFFFF", alpha: 0.26),
            width: 4
        )

        drawRadialGradient(
            context,
            path: CGPath(ellipseIn: CGRect(x: 380, y: 342, width: 264, height: 226), transform: nil),
            center: CGPoint(x: 512, y: 452),
            startRadius: 4,
            endRadius: 138,
            colors: [
                palette.cyanGlow.withAlpha(0.72),
                palette.tealLight.withAlpha(0.36),
                palette.tealMid.withAlpha(0.05)
            ],
            locations: [0.0, 0.55, 1.0]
        )

        let highlight = CGMutablePath()
        highlight.move(to: CGPoint(x: 300, y: 198))
        highlight.addCurve(to: CGPoint(x: 430, y: 126), control1: CGPoint(x: 330, y: 158), control2: CGPoint(x: 376, y: 130))
        highlight.addCurve(to: CGPoint(x: 523, y: 133), control1: CGPoint(x: 465, y: 124), control2: CGPoint(x: 497, y: 127))
        strokePath(context, path: highlight, color: Color(hex: "#FFFFFF", alpha: 0.42), width: 16)
        strokePath(context, path: highlight, color: Color(hex: "#FFFFFF", alpha: 0.18), width: 30)

        context.restoreGState()

        strokeEllipse(context, rect: portalRect.insetBy(dx: -1, dy: -1), color: palette.lavender.withAlpha(0.32), width: 5)
        strokeEllipse(context, rect: portalRect, color: palette.tealLight.withAlpha(0.58), width: 6)
        strokeEllipse(context, rect: portalRect.insetBy(dx: 10, dy: 12), color: palette.tealDark.withAlpha(0.44), width: 4)
    }
}

private func drawBook() -> CGImage {
    imageContext { context in
        context.translateBy(x: 512, y: 500)
        context.scaleBy(x: 1.12, y: 1.12)
        context.translateBy(x: -512, y: -500)

        let leftCover = CGMutablePath()
        leftCover.move(to: CGPoint(x: 186, y: 336))
        leftCover.addCurve(to: CGPoint(x: 496, y: 302), control1: CGPoint(x: 275, y: 286), control2: CGPoint(x: 405, y: 275))
        leftCover.addLine(to: CGPoint(x: 500, y: 690))
        leftCover.addCurve(to: CGPoint(x: 184, y: 682), control1: CGPoint(x: 394, y: 657), control2: CGPoint(x: 278, y: 656))
        leftCover.addCurve(to: CGPoint(x: 186, y: 336), control1: CGPoint(x: 166, y: 560), control2: CGPoint(x: 166, y: 430))
        leftCover.closeSubpath()

        let rightCover = CGMutablePath()
        rightCover.move(to: CGPoint(x: 838, y: 336))
        rightCover.addCurve(to: CGPoint(x: 528, y: 302), control1: CGPoint(x: 749, y: 286), control2: CGPoint(x: 619, y: 275))
        rightCover.addLine(to: CGPoint(x: 524, y: 690))
        rightCover.addCurve(to: CGPoint(x: 840, y: 682), control1: CGPoint(x: 630, y: 657), control2: CGPoint(x: 746, y: 656))
        rightCover.addCurve(to: CGPoint(x: 838, y: 336), control1: CGPoint(x: 858, y: 560), control2: CGPoint(x: 858, y: 430))
        rightCover.closeSubpath()

        drawShadowedPath(context, path: leftCover, fill: palette.coverDark, shadow: palette.darkEggplant.withAlpha(0.34), offset: CGSize(width: 0, height: 18), blur: 18)
        drawShadowedPath(context, path: rightCover, fill: palette.coverDark, shadow: palette.darkEggplant.withAlpha(0.34), offset: CGSize(width: 0, height: 18), blur: 18)
        drawPathLinearGradient(
            context,
            path: leftCover,
            colors: [palette.coverLight, palette.coverMid, palette.coverDark],
            locations: [0.0, 0.46, 1.0],
            start: CGPoint(x: 220, y: 300),
            end: CGPoint(x: 500, y: 690)
        )
        drawPathLinearGradient(
            context,
            path: rightCover,
            colors: [palette.coverLight, palette.coverMid, palette.coverDark],
            locations: [0.0, 0.46, 1.0],
            start: CGPoint(x: 804, y: 300),
            end: CGPoint(x: 524, y: 690)
        )
        strokePath(context, path: leftCover, color: palette.lavender.withAlpha(0.58), width: 5)
        strokePath(context, path: rightCover, color: palette.lavender.withAlpha(0.58), width: 5)

        let leftPageStack = CGMutablePath()
        leftPageStack.move(to: CGPoint(x: 286, y: 620))
        leftPageStack.addCurve(to: CGPoint(x: 503, y: 666), control1: CGPoint(x: 356, y: 610), control2: CGPoint(x: 438, y: 626))
        leftPageStack.addLine(to: CGPoint(x: 503, y: 708))
        leftPageStack.addCurve(to: CGPoint(x: 286, y: 656), control1: CGPoint(x: 438, y: 674), control2: CGPoint(x: 358, y: 648))
        leftPageStack.closeSubpath()

        let rightPageStack = CGMutablePath()
        rightPageStack.move(to: CGPoint(x: 738, y: 620))
        rightPageStack.addCurve(to: CGPoint(x: 521, y: 666), control1: CGPoint(x: 668, y: 610), control2: CGPoint(x: 586, y: 626))
        rightPageStack.addLine(to: CGPoint(x: 521, y: 708))
        rightPageStack.addCurve(to: CGPoint(x: 738, y: 656), control1: CGPoint(x: 586, y: 674), control2: CGPoint(x: 666, y: 648))
        rightPageStack.closeSubpath()

        drawPathLinearGradient(
            context,
            path: leftPageStack,
            colors: [palette.parchment, palette.parchmentShade, Color(hex: "#78694E", alpha: 0.78)],
            locations: [0.0, 0.62, 1.0],
            start: CGPoint(x: 384, y: 615),
            end: CGPoint(x: 440, y: 708)
        )
        drawPathLinearGradient(
            context,
            path: rightPageStack,
            colors: [palette.parchment, palette.parchmentShade, Color(hex: "#78694E", alpha: 0.78)],
            locations: [0.0, 0.62, 1.0],
            start: CGPoint(x: 640, y: 615),
            end: CGPoint(x: 584, y: 708)
        )

        let leftPage = CGMutablePath()
        leftPage.move(to: CGPoint(x: 499, y: 296))
        leftPage.addCurve(to: CGPoint(x: 318, y: 278), control1: CGPoint(x: 444, y: 265), control2: CGPoint(x: 374, y: 260))
        leftPage.addCurve(to: CGPoint(x: 267, y: 329), control1: CGPoint(x: 288, y: 288), control2: CGPoint(x: 270, y: 306))
        leftPage.addCurve(to: CGPoint(x: 292, y: 640), control1: CGPoint(x: 253, y: 432), control2: CGPoint(x: 258, y: 546))
        leftPage.addCurve(to: CGPoint(x: 500, y: 682), control1: CGPoint(x: 362, y: 625), control2: CGPoint(x: 438, y: 638))
        leftPage.closeSubpath()

        let rightPage = CGMutablePath()
        rightPage.move(to: CGPoint(x: 525, y: 296))
        rightPage.addCurve(to: CGPoint(x: 706, y: 278), control1: CGPoint(x: 580, y: 265), control2: CGPoint(x: 650, y: 260))
        rightPage.addCurve(to: CGPoint(x: 757, y: 329), control1: CGPoint(x: 736, y: 288), control2: CGPoint(x: 754, y: 306))
        rightPage.addCurve(to: CGPoint(x: 732, y: 640), control1: CGPoint(x: 771, y: 432), control2: CGPoint(x: 766, y: 546))
        rightPage.addCurve(to: CGPoint(x: 524, y: 682), control1: CGPoint(x: 662, y: 625), control2: CGPoint(x: 586, y: 638))
        rightPage.closeSubpath()

        drawPathLinearGradient(
            context,
            path: leftPage,
            colors: [palette.parchmentLight, palette.parchment, Color(hex: "#D7C59D")],
            locations: [0.0, 0.68, 1.0],
            start: CGPoint(x: 330, y: 270),
            end: CGPoint(x: 488, y: 680)
        )
        drawPathLinearGradient(
            context,
            path: rightPage,
            colors: [palette.parchmentLight, palette.parchment, Color(hex: "#D7C59D")],
            locations: [0.0, 0.68, 1.0],
            start: CGPoint(x: 694, y: 270),
            end: CGPoint(x: 536, y: 680)
        )

        let gutter = CGPath(roundedRect: CGRect(x: 500, y: 298, width: 24, height: 388), cornerWidth: 8, cornerHeight: 8, transform: nil)
        drawPathLinearGradient(
            context,
            path: gutter,
            colors: [
                palette.darkEggplant.withAlpha(0.96),
                palette.coverDark.withAlpha(0.98),
                palette.darkEggplant.withAlpha(0.96)
            ],
            locations: [0.0, 0.5, 1.0],
            start: CGPoint(x: 500, y: 492),
            end: CGPoint(x: 524, y: 492)
        )

        let leftGutterEdge = CGMutablePath()
        leftGutterEdge.move(to: CGPoint(x: 499, y: 304))
        leftGutterEdge.addCurve(to: CGPoint(x: 503, y: 680), control1: CGPoint(x: 501, y: 425), control2: CGPoint(x: 501, y: 565))
        strokePath(context, path: leftGutterEdge, color: palette.parchmentLight.withAlpha(0.72), width: 4)

        let rightGutterEdge = CGMutablePath()
        rightGutterEdge.move(to: CGPoint(x: 525, y: 304))
        rightGutterEdge.addCurve(to: CGPoint(x: 521, y: 680), control1: CGPoint(x: 523, y: 425), control2: CGPoint(x: 523, y: 565))
        strokePath(context, path: rightGutterEdge, color: palette.parchmentLight.withAlpha(0.72), width: 4)

        let bottomJoin = CGMutablePath()
        bottomJoin.move(to: CGPoint(x: 494, y: 678))
        bottomJoin.addLine(to: CGPoint(x: 512, y: 696))
        bottomJoin.addLine(to: CGPoint(x: 530, y: 678))
        strokePath(context, path: bottomJoin, color: palette.darkEggplant.withAlpha(0.62), width: 5)

        strokePath(context, path: leftPage, color: palette.parchmentLight.withAlpha(0.74), width: 5)
        strokePath(context, path: rightPage, color: palette.parchmentLight.withAlpha(0.74), width: 5)

        let leftOuterEdge = CGMutablePath()
        leftOuterEdge.move(to: CGPoint(x: 278, y: 332))
        leftOuterEdge.addCurve(to: CGPoint(x: 292, y: 629), control1: CGPoint(x: 263, y: 432), control2: CGPoint(x: 267, y: 548))
        strokePath(context, path: leftOuterEdge, color: palette.parchmentShade.withAlpha(0.42), width: 9)

        let rightOuterEdge = CGMutablePath()
        rightOuterEdge.move(to: CGPoint(x: 746, y: 332))
        rightOuterEdge.addCurve(to: CGPoint(x: 732, y: 629), control1: CGPoint(x: 761, y: 432), control2: CGPoint(x: 757, y: 548))
        strokePath(context, path: rightOuterEdge, color: palette.parchmentShade.withAlpha(0.42), width: 9)

        let pageLineColor = palette.parchmentShade.withAlpha(0.18)
        context.saveGState()
        context.addPath(leftPage)
        context.clip()
        for (y, inset) in [(374, 0), (422, 8), (470, 14), (518, 18)] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 324 + CGFloat(inset), y: CGFloat(y)))
            path.addCurve(to: CGPoint(x: 462, y: CGFloat(y + 11)), control1: CGPoint(x: 376, y: CGFloat(y - 8)), control2: CGPoint(x: 422, y: CGFloat(y - 2)))
            strokePath(context, path: path, color: pageLineColor, width: 3)
        }
        context.restoreGState()

        context.saveGState()
        context.addPath(rightPage)
        context.clip()
        for (y, inset) in [(374, 0), (422, 8), (470, 14), (518, 18)] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 562, y: CGFloat(y + 11)))
            path.addCurve(to: CGPoint(x: 700 - CGFloat(inset), y: CGFloat(y)), control1: CGPoint(x: 602, y: CGFloat(y - 2)), control2: CGPoint(x: 648, y: CGFloat(y - 8)))
            strokePath(context, path: path, color: pageLineColor, width: 3)
        }
        context.restoreGState()
    }
}

private func drawComposite(portal: CGImage, book: CGImage) -> CGImage {
    imageContext(flipped: false) { context in
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
        context.draw(portal, in: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
        context.draw(book, in: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    }
}

private func drawPreviewSheet(composite: CGImage) -> CGImage {
    let width = 1600
    let height = 520
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create preview CGContext")
    }

    context.setFillColor(Color(hex: "#1B1220").cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let sizes: [CGFloat] = [384, 256, 128, 64]
    var x: CGFloat = 58
    for size in sizes {
        let y = (CGFloat(height) - size) / 2
        fillRoundedRect(context, rect: CGRect(x: x - 18, y: y - 18, width: size + 36, height: size + 36), radius: 44, color: Color(hex: "#422853", alpha: 0.34))
        context.draw(composite, in: CGRect(x: x, y: y, width: size, height: size))
        x += size + 86
    }

    return context.makeImage()!
}

private func drawDetailCropSheet(composite: CGImage) -> CGImage {
    let width = 1500
    let height = 440
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create detail crop CGContext")
    }

    context.setFillColor(Color(hex: "#1B1220").cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let crops = [
        CGRect(x: 282, y: 734, width: 460, height: 150),
        CGRect(x: 450, y: 250, width: 124, height: 500),
        CGRect(x: 306, y: 600, width: 412, height: 150)
    ]
    let destinations = [
        CGRect(x: 40, y: 70, width: 420, height: 300),
        CGRect(x: 540, y: 30, width: 300, height: 380),
        CGRect(x: 920, y: 70, width: 540, height: 300)
    ]

    for (crop, destination) in zip(crops, destinations) {
        guard let cropped = composite.cropping(to: crop) else { continue }
        fillRoundedRect(context, rect: destination.insetBy(dx: -10, dy: -10), radius: 18, color: Color(hex: "#422853", alpha: 0.42))
        context.draw(cropped, in: destination)
    }

    return context.makeImage()!
}

let outputDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("upright-v6-clean-system")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let portal = drawPortal()
let book = drawBook()
let composite = drawComposite(portal: portal, book: book)
let previewSheet = drawPreviewSheet(composite: composite)
let detailCropSheet = drawDetailCropSheet(composite: composite)

writePNG(portal, to: outputDirectory.appendingPathComponent("grimora-icon-01-portal.png"))
writePNG(book, to: outputDirectory.appendingPathComponent("grimora-icon-03-book.png"))
writePNG(composite, to: outputDirectory.appendingPathComponent("grimora-icon-preview-composite.png"))
writePNG(previewSheet, to: outputDirectory.appendingPathComponent("grimora-icon-preview-sizes.png"))
writePNG(detailCropSheet, to: outputDirectory.appendingPathComponent("grimora-icon-preview-detail-crops.png"))

print("Rendered Grimora Icon Composer source layers to \(outputDirectory.path)")
