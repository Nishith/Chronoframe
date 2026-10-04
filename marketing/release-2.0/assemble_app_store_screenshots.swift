import AppKit
import Foundation

private let canvasSize = NSSize(width: 2880, height: 1800)
private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let audit = root.appendingPathComponent(".tmp/marketing-capture/screenshot-audit", isDirectory: true)
private let output = root.appendingPathComponent("marketing/release-2.0/screenshots", isDirectory: true)

private enum Sanitization {
    case none
    case previewPaths
    case setupPaths
}

private struct CampaignFrame {
    let input: String
    let output: String
    let headline: String
    let sanitization: Sanitization
}

private let frames = [
    CampaignFrame(
        input: "03-preview-validation.png",
        output: "01-4000-timeline-app-store.png",
        headline: "4,000 scattered photos. One clean timeline.",
        sanitization: .previewPaths
    ),
    CampaignFrame(
        input: "01-setup-raw-approved.png",
        output: "02-setup-app-store.png",
        headline: "Choose your folders. Preview every copy.",
        sanitization: .setupPaths
    ),
    CampaignFrame(
        input: "02-deduplicate-raw-approved.png",
        output: "03-deduplicate-app-store.png",
        headline: "Find copies and look-alikes at a glance.",
        sanitization: .none
    ),
    CampaignFrame(
        input: "03-transfer-complete-raw-approved.png",
        output: "04-verified-transfer-app-store.png",
        headline: "Verified copies. Originals untouched.",
        sanitization: .none
    ),
    CampaignFrame(
        input: "04-user-control-raw-approved.png",
        output: "05-user-control-app-store.png",
        headline: "You decide what leaves.",
        sanitization: .none
    ),
    CampaignFrame(
        input: "05-run-history-raw-approved.png",
        output: "06-run-history-app-store.png",
        headline: "Receipts for safer undo.",
        sanitization: .none
    ),
    CampaignFrame(
        input: "06-photos-read-only-permission-raw-approved.png",
        output: "07-photos-read-only-app-store.png",
        headline: "Import from Photos without changing Photos.",
        sanitization: .none
    ),
]

private func makeBitmap(width: Int, height: Int) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not allocate bitmap")
    }
    bitmap.size = NSSize(width: width, height: height)
    return bitmap
}

private func withBitmapContext<T>(_ bitmap: NSBitmapImageRep, _ work: () throws -> T) rethrows -> T {
    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create bitmap context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    defer { NSGraphicsContext.restoreGraphicsState() }
    return try work()
}

private func topLeftRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, canvasHeight: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasHeight - y - height, width: width, height: height)
}

private func sanitizedPreview(_ original: NSBitmapImageRep) -> NSBitmapImageRep {
    let width = original.pixelsWide
    let height = original.pixelsHigh
    let result = makeBitmap(width: width, height: height)
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(original)

    withBitmapContext(result) {
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))

        struct Replacement {
            let mask: NSRect
            let samplePointTopLeft: NSPoint
            let text: String
            let textRect: NSRect
            let alignment: NSTextAlignment
        }

        // Coordinates are tied to the accepted 5120x2824 preview capture.
        // Only path values are replaced; all run counts and UI remain unchanged.
        let replacements = [
            Replacement(
                mask: topLeftRect(2890, 817, 995, 63, canvasHeight: CGFloat(height)),
                samplePointTopLeft: NSPoint(x: 2810, y: 850),
                text: "4,000-photo demo library",
                textRect: topLeftRect(2950, 827, 910, 45, canvasHeight: CGFloat(height)),
                alignment: .right
            ),
            Replacement(
                mask: topLeftRect(2890, 875, 995, 63, canvasHeight: CGFloat(height)),
                samplePointTopLeft: NSPoint(x: 2810, y: 905),
                text: "Chronoframe Verified Library",
                textRect: topLeftRect(2950, 885, 910, 45, canvasHeight: CGFloat(height)),
                alignment: .right
            ),
            Replacement(
                mask: topLeftRect(2815, 2266, 820, 66, canvasHeight: CGFloat(height)),
                samplePointTopLeft: NSPoint(x: 3000, y: 2298),
                text: "Chronoframe Verified Library",
                textRect: topLeftRect(2860, 2276, 740, 45, canvasHeight: CGFloat(height)),
                alignment: .left
            ),
        ]

        for replacement in replacements {
            let sampled = original.colorAt(
                x: Int(replacement.samplePointTopLeft.x),
                y: max(0, min(height - 1, Int(replacement.samplePointTopLeft.y)))
            ) ?? NSColor(calibratedWhite: 0.09, alpha: 1)
            sampled.setFill()
            replacement.mask.fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = replacement.alignment
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
                .paragraphStyle: paragraph,
            ]
            NSAttributedString(string: replacement.text, attributes: attributes)
                .draw(in: replacement.textRect)
        }
    }
    return result
}

private func sanitizedSetup(_ original: NSBitmapImageRep) -> NSBitmapImageRep {
    let width = original.pixelsWide
    let height = original.pixelsHigh
    let result = makeBitmap(width: width, height: height)
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(original)

    withBitmapContext(result) {
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))

        struct Replacement {
            let mask: NSRect
            let text: String
            let textRect: NSRect
        }

        // Coordinates are tied to the accepted 5120x2822 setup capture.
        // Replace only absolute paths; preserve every other UI pixel.
        let replacements = [
            Replacement(
                mask: topLeftRect(775, 870, 1265, 44, canvasHeight: CGFloat(height)),
                text: "Chronoframe Large Demo Source 2013–2026",
                textRect: topLeftRect(790, 875, 1220, 36, canvasHeight: CGFloat(height))
            ),
            Replacement(
                mask: topLeftRect(775, 1344, 900, 44, canvasHeight: CGFloat(height)),
                text: "Chronoframe Verified Library",
                textRect: topLeftRect(790, 1349, 850, 36, canvasHeight: CGFloat(height))
            ),
        ]

        for replacement in replacements {
            NSColor(deviceRed: 26 / 255, green: 33 / 255, blue: 34 / 255, alpha: 1).setFill()
            replacement.mask.fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 23, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 1),
                .paragraphStyle: paragraph,
            ]
            NSAttributedString(string: replacement.text, attributes: attributes)
                .draw(in: replacement.textRect)
        }
    }
    return result
}

private func drawHeadline(_ headline: String, bandHeight: CGFloat) {
    let maximumWidth: CGFloat = 2660
    let maximumHeight = max(90, bandHeight - 26)
    var fontSize: CGFloat = 104
    var attributes: [NSAttributedString.Key: Any] = [:]
    var measured = NSSize.zero

    while fontSize >= 72 {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributes = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.98, alpha: 1),
            .kern: -0.5,
            .paragraphStyle: paragraph,
        ]
        measured = NSAttributedString(string: headline, attributes: attributes).size()
        if measured.width <= maximumWidth && measured.height <= maximumHeight { break }
        fontSize -= 2
    }

    let yFromTop = max(8, (bandHeight - measured.height) / 2)
    let rect = topLeftRect(
        110,
        yFromTop,
        canvasSize.width - 220,
        measured.height + 8,
        canvasHeight: canvasSize.height
    )
    NSAttributedString(string: headline, attributes: attributes).draw(in: rect)
}

private func render(_ frame: CampaignFrame) throws -> URL {
    let inputURL = audit.appendingPathComponent(frame.input)
    let inputData = try Data(contentsOf: inputURL)
    guard let original = NSBitmapImageRep(data: inputData) else {
        throw NSError(domain: "CampaignAssembler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open \(inputURL.path)"])
    }
    let source: NSBitmapImageRep
    switch frame.sanitization {
    case .none:
        source = original
    case .previewPaths:
        source = sanitizedPreview(original)
    case .setupPaths:
        source = sanitizedSetup(original)
    }
    let sourceImage = NSImage(size: NSSize(width: source.pixelsWide, height: source.pixelsHigh))
    sourceImage.addRepresentation(source)

    let scale = canvasSize.width / CGFloat(source.pixelsWide)
    let renderedWidth = CGFloat(source.pixelsWide) * scale
    let renderedHeight = CGFloat(source.pixelsHigh) * scale
    let bandHeight = canvasSize.height - renderedHeight
    guard bandHeight >= 170 else {
        throw NSError(domain: "CampaignAssembler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Headline band is too short for \(frame.output)"])
    }

    let canvas = makeBitmap(width: Int(canvasSize.width), height: Int(canvasSize.height))
    try withBitmapContext(canvas) {
        let top = NSColor(calibratedRed: 0.070, green: 0.080, blue: 0.110, alpha: 1)
        let bottom = NSColor(calibratedRed: 0.028, green: 0.032, blue: 0.044, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(
            in: NSRect(origin: .zero, size: canvasSize),
            angle: -90
        )

        sourceImage.draw(
            in: NSRect(x: (canvasSize.width - renderedWidth) / 2, y: 0, width: renderedWidth, height: renderedHeight),
            from: NSRect(x: 0, y: 0, width: source.pixelsWide, height: source.pixelsHigh),
            operation: NSCompositingOperation.sourceOver,
            fraction: 1
        )
        drawHeadline(frame.headline, bandHeight: bandHeight)
    }

    let destination = output.appendingPathComponent(frame.output)
    guard let data = canvas.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CampaignAssembler", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode \(frame.output)"])
    }
    try data.write(to: destination, options: .atomic)
    return destination
}

private func makeContactSheet(urls: [URL]) throws -> URL {
    let columns = urls.count > 6 ? 4 : 3
    let rows = Int(ceil(Double(urls.count) / Double(columns)))
    let thumb = NSSize(width: 2880 / CGFloat(columns), height: 1800 / CGFloat(columns))
    let sheetSize = NSSize(width: thumb.width * CGFloat(columns), height: thumb.height * CGFloat(rows))
    let sheet = makeBitmap(width: Int(sheetSize.width), height: Int(sheetSize.height))

    try withBitmapContext(sheet) {
        NSColor.black.setFill()
        NSRect(origin: .zero, size: sheetSize).fill()
        for (index, url) in urls.enumerated() {
            guard let image = NSImage(contentsOf: url) else { continue }
            let column = index % columns
            let rowFromTop = index / columns
            let rect = NSRect(
                x: CGFloat(column) * thumb.width,
                y: sheetSize.height - CGFloat(rowFromTop + 1) * thumb.height,
                width: thumb.width,
                height: thumb.height
            )
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    let destination = output.appendingPathComponent("contact-sheet.png")
    guard let data = sheet.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CampaignAssembler", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not encode contact sheet"])
    }
    try data.write(to: destination, options: .atomic)
    return destination
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let rendered = try frames.map(render)
let contactSheet = try makeContactSheet(urls: rendered)
for url in rendered + [contactSheet] {
    print(url.path)
}
