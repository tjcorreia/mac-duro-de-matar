import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 4 else {
    fputs("Uso: swift scripts/generate_qr.swift <url> <output.png> <label>\n", stderr)
    exit(1)
}

let urlString = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let label = CommandLine.arguments[3]

guard let data = urlString.data(using: .utf8) else {
    fputs("Nao foi possivel converter a URL para dados.\n", stderr)
    exit(1)
}

let context = CIContext()
let filter = CIFilter.qrCodeGenerator()
filter.message = data
filter.correctionLevel = "M"

guard let outputImage = filter.outputImage else {
    fputs("Falha a gerar a imagem base do QR code.\n", stderr)
    exit(1)
}

let colorFilter = CIFilter.falseColor()
colorFilter.inputImage = outputImage
colorFilter.color0 = CIColor(red: 0, green: 0, blue: 0)
colorFilter.color1 = CIColor(red: 1, green: 1, blue: 1)

guard let coloredImage = colorFilter.outputImage else {
    fputs("Falha a aplicar cor ao QR code.\n", stderr)
    exit(1)
}

let scale = CGAffineTransform(scaleX: 18, y: 18)
let scaledImage = coloredImage.transformed(by: scale)
let extent = scaledImage.extent.integral
let colorSpace = CGColorSpaceCreateDeviceRGB()
let qrWidth = Int(extent.width)
let qrHeight = Int(extent.height)

guard qrWidth > 0, qrHeight > 0 else {
    fputs("O QR code gerado tem dimensoes invalidas.\n", stderr)
    exit(1)
}

var pixels = [UInt8](repeating: 0, count: qrWidth * qrHeight * 4)
context.render(
    scaledImage,
    toBitmap: &pixels,
    rowBytes: qrWidth * 4,
    bounds: extent,
    format: .RGBA8,
    colorSpace: colorSpace
)

guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
    fputs("Falha a criar o data provider do QR code.\n", stderr)
    exit(1)
}

guard let qrCGImage = CGImage(
    width: qrWidth,
    height: qrHeight,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: qrWidth * 4,
    space: colorSpace,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
    provider: provider,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
) else {
    fputs("Falha a criar a imagem raster do QR code.\n", stderr)
    exit(1)
}

let labelFontSize: CGFloat = 20
let padding: CGFloat = 12
let labelHeight: CGFloat = 28
let canvasWidth = CGFloat(qrWidth)
let canvasHeight = CGFloat(qrHeight) + labelHeight + padding
let bytesPerRow = Int(canvasWidth) * 4

guard let bitmapContext = CGContext(
    data: nil,
    width: Int(canvasWidth),
    height: Int(canvasHeight),
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Falha a criar o contexto final do QR code.\n", stderr)
    exit(1)
}

bitmapContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
bitmapContext.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
bitmapContext.draw(qrCGImage, in: CGRect(x: 0, y: labelHeight + padding, width: canvasWidth, height: CGFloat(qrHeight)))

let labelRect = CGRect(x: canvasWidth - 84, y: 6, width: 72, height: labelHeight - 4)
bitmapContext.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.92))
let labelPath = CGPath(
    roundedRect: labelRect,
    cornerWidth: 6,
    cornerHeight: 6,
    transform: nil
)
bitmapContext.addPath(labelPath)
bitmapContext.fillPath()

let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(rawValue: kCTFontAttributeName as String):
        CTFontCreateWithName("Helvetica-Bold" as CFString, labelFontSize, nil),
    NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String):
        CGColor(red: 1, green: 1, blue: 1, alpha: 1)
]

let attributedString = NSAttributedString(string: label, attributes: attributes)
let line = CTLineCreateWithAttributedString(attributedString)
let bounds = CTLineGetBoundsWithOptions(line, [])
let textX = labelRect.midX - bounds.width / 2
let textY = labelRect.midY - bounds.height / 2

bitmapContext.textPosition = CGPoint(x: textX, y: textY)
CTLineDraw(line, bitmapContext)

guard let finalImage = bitmapContext.makeImage() else {
    fputs("Falha a criar a imagem final do QR code.\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fputs("Falha a criar o destino PNG.\n", stderr)
        exit(1)
    }

    CGImageDestinationAddImage(destination, finalImage, nil)

    guard CGImageDestinationFinalize(destination) else {
        fputs("Falha a escrever o PNG final.\n", stderr)
        exit(1)
    }

    print("QR code criado em \(outputPath)")
} catch {
    fputs("Falha a preparar o ficheiro PNG: \(error.localizedDescription)\n", stderr)
    exit(1)
}
