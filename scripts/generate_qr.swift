import CoreImage
import CoreImage.CIFilterBuiltins
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

let padding = 12
let labelHeight = 32
let canvasWidth = qrWidth
let canvasHeight = qrHeight + labelHeight + padding
var canvasPixels = [UInt8](repeating: 255, count: canvasWidth * canvasHeight * 4)

func setPixel(_ pixels: inout [UInt8], width: Int, x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
    guard x >= 0, y >= 0, x < width else { return }
    let index = (y * width + x) * 4
    guard index + 3 < pixels.count else { return }
    pixels[index] = r
    pixels[index + 1] = g
    pixels[index + 2] = b
    pixels[index + 3] = a
}

for y in 0..<qrHeight {
    for x in 0..<qrWidth {
        let src = (y * qrWidth + x) * 4
        let dstY = y + labelHeight + padding
        let dst = (dstY * canvasWidth + x) * 4
        canvasPixels[dst] = pixels[src]
        canvasPixels[dst + 1] = pixels[src + 1]
        canvasPixels[dst + 2] = pixels[src + 2]
        canvasPixels[dst + 3] = 255
    }
}

let labelBoxWidth = 76
let labelBoxHeight = 22
let labelBoxX = canvasWidth - labelBoxWidth - 10
let labelBoxY = 6

for y in labelBoxY..<(labelBoxY + labelBoxHeight) {
    for x in labelBoxX..<(labelBoxX + labelBoxWidth) {
        setPixel(&canvasPixels, width: canvasWidth, x: x, y: y, r: 20, g: 20, b: 20)
    }
}

let glyphs: [Character: [String]] = [
    "M": [
        "10001",
        "11011",
        "10101",
        "10001",
        "10001",
        "10001",
        "10001",
    ],
    "A": [
        "01110",
        "10001",
        "10001",
        "11111",
        "10001",
        "10001",
        "10001",
    ],
    "C": [
        "01111",
        "10000",
        "10000",
        "10000",
        "10000",
        "10000",
        "01111",
    ],
    "-": [
        "00000",
        "00000",
        "11111",
        "00000",
        "00000",
        "00000",
        "00000",
    ],
    "D": [
        "11110",
        "10001",
        "10001",
        "10001",
        "10001",
        "10001",
        "11110",
    ],
]

let scaleFactor = 2
var cursorX = labelBoxX + 8
let cursorY = labelBoxY + 4

for character in label {
    guard let glyph = glyphs[character] else {
        cursorX += 8
        continue
    }

    for (rowIndex, row) in glyph.enumerated() {
        for (colIndex, bit) in row.enumerated() where bit == "1" {
            for dy in 0..<scaleFactor {
                for dx in 0..<scaleFactor {
                    setPixel(
                        &canvasPixels,
                        width: canvasWidth,
                        x: cursorX + colIndex * scaleFactor + dx,
                        y: cursorY + rowIndex * scaleFactor + dy,
                        r: 255,
                        g: 255,
                        b: 255
                    )
                }
            }
        }
    }

    cursorX += 5 * scaleFactor + 2
}

guard let finalProvider = CGDataProvider(data: Data(canvasPixels) as CFData) else {
    fputs("Falha a criar o data provider final do QR code.\n", stderr)
    exit(1)
}

guard let finalImage = CGImage(
    width: canvasWidth,
    height: canvasHeight,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: canvasWidth * 4,
    space: colorSpace,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
    provider: finalProvider,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
) else {
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
