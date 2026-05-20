import AppKit
import CoreGraphics
import Foundation
import ImageIO

private struct RGBA {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(hex: String, alpha: CGFloat = 1) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        red = CGFloat((value >> 16) & 0xff) / 255
        green = CGFloat((value >> 8) & 0xff) / 255
        blue = CGFloat(value & 0xff) / 255
        self.alpha = alpha
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct AppIconEntry: Decodable {
    let filename: String?
    let size: String
    let scale: String
}

private struct AppIconContents: Decodable {
    let images: [AppIconEntry]
}

private let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let sourceRoot = repoRoot.appendingPathComponent("GrimoraApp/AppIconComposerSources/upright-v6-clean-system")
private let exportURL = sourceRoot.appendingPathComponent("Grimora-iOS-Default-1024x1024@1x.png")
private let appIconSetURL = repoRoot.appendingPathComponent("GrimoraApp/Assets.xcassets/AppIcon.appiconset")
private let launchLogoURL = repoRoot.appendingPathComponent("GrimoraApp/Assets.xcassets/GrimoraLaunchLogo.imageset/GrimoraLaunchLogo.png")
private let moduleLogoURL = repoRoot.appendingPathComponent("GrimoraKit/Sources/GrimoraUI/Resources/Assets.xcassets/GrimoraLogo.imageset/GrimoraLogo.png")
private let visionBackURL = repoRoot.appendingPathComponent("GrimoraApp/Assets.xcassets/AppIconVision.solidimagestack/Back.solidimagestacklayer/Content.imageset/GrimoraVisionIconBack.png")
private let visionMiddleURL = repoRoot.appendingPathComponent("GrimoraApp/Assets.xcassets/AppIconVision.solidimagestack/Middle.solidimagestacklayer/Content.imageset/GrimoraVisionIcon.png")
private let visionFrontURL = repoRoot.appendingPathComponent("GrimoraApp/Assets.xcassets/AppIconVision.solidimagestack/Front.solidimagestacklayer/Content.imageset/GrimoraVisionIconFront.png")

private func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        fatalError("Could not load image: \(url.path)")
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG: \(url.path)")
    }

    do {
        try data.write(to: url, options: .atomic)
    } catch {
        fatalError("Could not write PNG \(url.path): \(error)")
    }
}

private func drawImage(
    width: Int,
    height: Int,
    opaqueBackground: RGBA?,
    _ draw: (CGContext, CGRect) -> Void
) -> CGImage {
    let bitmapInfo: UInt32
    if opaqueBackground == nil {
        bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    } else {
        bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    }

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Could not create image context")
    }

    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.clear(rect)
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    if let opaqueBackground {
        context.setFillColor(opaqueBackground.cgColor)
        context.fill(rect)
    }

    draw(context, rect)

    guard let image = context.makeImage() else {
        fatalError("Could not create output image")
    }
    return image
}

private func pixelSize(size: String, scale: String) -> Int {
    guard let base = Double(size.split(separator: "x").first ?? ""),
          let multiplier = Double(scale.replacingOccurrences(of: "x", with: ""))
    else {
        fatalError("Could not parse app icon size=\(size), scale=\(scale)")
    }
    return Int((base * multiplier).rounded())
}

private func resize(_ image: CGImage, to pixelSize: Int, opaqueBackground: RGBA?) -> CGImage {
    drawImage(width: pixelSize, height: pixelSize, opaqueBackground: opaqueBackground) { context, rect in
        context.draw(image, in: rect)
    }
}

private let composerExport = loadImage(exportURL)
private let iconBackground = RGBA(hex: "#422853")

private let contentsData = try Data(contentsOf: appIconSetURL.appendingPathComponent("Contents.json"))
private let contents = try JSONDecoder().decode(AppIconContents.self, from: contentsData)
private var writtenIconFiles = Set<String>()

for entry in contents.images {
    guard let filename = entry.filename, !writtenIconFiles.contains(filename) else { continue }
    let pixels = pixelSize(size: entry.size, scale: entry.scale)
    let resized = resize(composerExport, to: pixels, opaqueBackground: iconBackground)
    writePNG(resized, to: appIconSetURL.appendingPathComponent(filename))
    writtenIconFiles.insert(filename)
}

writePNG(resize(composerExport, to: 1024, opaqueBackground: iconBackground), to: launchLogoURL)
writePNG(resize(composerExport, to: 1024, opaqueBackground: iconBackground), to: moduleLogoURL)

private let portal = loadImage(sourceRoot.appendingPathComponent("grimora-icon-01-portal.png"))
private let book = loadImage(sourceRoot.appendingPathComponent("grimora-icon-03-book.png"))

private let visionBack = drawImage(width: 1024, height: 1024, opaqueBackground: iconBackground) { context, rect in
    context.draw(portal, in: rect)
}
writePNG(visionBack, to: visionBackURL)
let emptyVisionMiddle = drawImage(width: 1024, height: 1024, opaqueBackground: nil) { _, _ in }
writePNG(emptyVisionMiddle, to: visionMiddleURL)
writePNG(resize(book, to: 1024, opaqueBackground: nil), to: visionFrontURL)

print("Installed Composer export into AppIcon.appiconset, launch/logo images, and layered AppIconVision assets.")
