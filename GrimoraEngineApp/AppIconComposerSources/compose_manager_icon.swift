// Composites the shared Grimora app icon with a "MANAGER" capsule near the bottom, producing the
// 1024px master used for the Grimora Engine (Manager) macOS app icon.
//
// Usage: swift compose_manager_icon.swift <base-1024.png> <output-1024.png>
import AppKit

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(Data("usage: compose_manager_icon.swift <base> <output>\n".utf8))
  exit(2)
}
let basePath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let baseImage = NSImage(contentsOfFile: basePath) else {
  FileHandle.standardError.write(Data("could not load base image at \(basePath)\n".utf8))
  exit(1)
}

let size = 1024
guard
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = NSRect(x: 0, y: 0, width: size, height: size)
baseImage.draw(in: canvas, from: .zero, operation: .copy, fraction: 1.0)

// Capsule banner near the bottom (AppKit origin is bottom-left).
let bannerHeight: CGFloat = 168
let bannerWidth: CGFloat = 760
let bannerY: CGFloat = 96
let bannerRect = NSRect(
  x: (CGFloat(size) - bannerWidth) / 2,
  y: bannerY,
  width: bannerWidth,
  height: bannerHeight
)
let capsule = NSBezierPath(roundedRect: bannerRect, xRadius: bannerHeight / 2, yRadius: bannerHeight / 2)

NSColor(calibratedWhite: 0.04, alpha: 0.55).setFill()
capsule.fill()
NSColor(calibratedWhite: 1.0, alpha: 0.22).setStroke()
capsule.lineWidth = 4
capsule.stroke()

// "MANAGER" text, rounded heavy, centered, letter-spaced.
let baseFont = NSFont.systemFont(ofSize: 104, weight: .heavy)
let descriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
let font = NSFont(descriptor: descriptor, size: 104) ?? baseFont

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let attributes: [NSAttributedString.Key: Any] = [
  .font: font,
  .foregroundColor: NSColor.white,
  .kern: 10.0,
  .paragraphStyle: paragraph,
]
let text = NSAttributedString(string: "MANAGER", attributes: attributes)
let textSize = text.size()
let textRect = NSRect(
  x: bannerRect.minX,
  y: bannerRect.midY - textSize.height / 2,
  width: bannerRect.width,
  height: textSize.height
)
text.draw(in: textRect)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
  exit(1)
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
