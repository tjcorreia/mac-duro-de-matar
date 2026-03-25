import AppKit
import Foundation

guard CommandLine.arguments.count >= 4 else {
    fputs("Uso: swift scripts/generate_qr.swift <input.png> <output.png> <label>\n", stderr)
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let label = CommandLine.arguments[3]

let inputURL = URL(fileURLWithPath: inputPath)
let outputURL = URL(fileURLWithPath: outputPath)

guard let baseImage = NSImage(contentsOf: inputURL) else {
    fputs("Falha a abrir o PNG base do QR code.\n", stderr)
    exit(1)
}

let size = baseImage.size
let composedImage = NSImage(size: size)

composedImage.lockFocus()

baseImage.draw(in: NSRect(origin: .zero, size: size))

let labelWidth: CGFloat = 76
let labelHeight: CGFloat = 24
let labelRect = NSRect(
    x: size.width - labelWidth - 10,
    y: size.height - labelHeight - 10,
    width: labelWidth,
    height: labelHeight
)

NSColor(calibratedWhite: 0.12, alpha: 0.92).setFill()
NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 14),
    .foregroundColor: NSColor.white
]

let text = NSAttributedString(string: label, attributes: attributes)
text.draw(at: NSPoint(x: labelRect.minX + 9, y: labelRect.minY + 4))

composedImage.unlockFocus()

guard
    let tiffData = composedImage.tiffRepresentation,
    let bitmapRep = NSBitmapImageRep(data: tiffData),
    let pngData = bitmapRep.representation(using: .png, properties: [:])
else {
    fputs("Falha a compor o PNG final do QR code.\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL)
    print("QR code criado em \(outputPath)")
} catch {
    fputs("Falha a escrever o PNG final: \(error.localizedDescription)\n", stderr)
    exit(1)
}
