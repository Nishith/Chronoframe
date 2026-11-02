// Recovers the app icon's alpha channel from artwork that was flattened
// onto an opaque white background.
//
//     swift ui/Tools/RestoreIconAlpha.swift <flattened-1024.png> <output-dir>
//     cp <output-dir>/icon_*.png ui/Resources/Assets.xcassets/AppIcon.appiconset/
//     cp <output-dir>/app-icon-1024.png <output-dir>/app-icon-512.png \
//        <output-dir>/favicon-32x32.png site/
//
// Background: the icon artwork reaching this repo has at times been
// flattened, leaving the squircle's corners as white pixels instead of
// transparent ones. macOS does not mask legacy .appiconset artwork on 14
// and 15, so the Dock draws that as a white tile with the rounded shape
// floating inside it. This tool puts the transparency back.
//
// It works because the white only ever touches the four corner regions —
// the squircle body separates it from the light artwork inside — so a
// flood fill inward from the corners isolates the background exactly.
// Pixels along the curve are partial blends of white and the dark edge, so
// they are un-composited against white rather than hard-cut, which keeps
// the curve's antialiasing. Every smaller size is resampled from the
// recovered master.
//
// This is a repair tool, not a source of truth. Artwork exported with its
// alpha channel intact needs none of this, and re-exporting from the
// design source is always preferable — the recovery cannot undo whatever
// lossy compression the flattened PNG already baked in.
//
// site/apple-touch-icon.png is deliberately not emitted: iOS applies its
// own mask and renders transparency there as black, so that one file is
// correct flattened.

import AppKit
import CoreGraphics
import Foundation

/// Output filename(s) each rendered pixel size maps to. The catalog points
/// several slots at the same pixel size, and the site reuses three of them.
let outputs: [Int: [String]] = [
    1024: ["icon_512x512@2x.png", "app-icon-1024.png"],
    512: ["icon_256x256@2x.png", "icon_512x512.png", "app-icon-512.png"],
    256: ["icon_128x128@2x.png", "icon_256x256.png"],
    128: ["icon_128x128.png"],
    64: ["icon_32x32@2x.png"],
    32: ["icon_16x16@2x.png", "icon_32x32.png", "favicon-32x32.png"],
    16: ["icon_16x16.png"],
]

let args = CommandLine.arguments
guard args.count >= 3 else {
    let exe = (args.first as NSString?)?.lastPathComponent ?? "RestoreIconAlpha"
    FileHandle.standardError.write(Data("usage: \(exe) <flattened-1024.png> <output-dir>\n".utf8))
    exit(64)
}
let inputURL = URL(fileURLWithPath: args[1])
let outputDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("could not read \(inputURL.path)\n".utf8))
    exit(1)
}

let w = image.width, h = image.height
guard w == h, w >= 1024 else {
    FileHandle.standardError.write(Data("expected a square master of at least 1024px, got \(w)x\(h)\n".utf8))
    exit(1)
}

let space = CGColorSpaceCreateDeviceRGB()
var px = [UInt8](repeating: 0, count: w * h * 4)
px.withUnsafeMutableBytes { buf in
    let ctx = CGContext(
        data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: w * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
}

// 1. Flood fill the white background inward from each corner.
let whiteCutoff: UInt8 = 250
var isBackground = [Bool](repeating: false, count: w * h)
var stack: [Int] = []

func isNearWhite(_ i: Int) -> Bool {
    let o = i * 4
    return px[o] >= whiteCutoff && px[o + 1] >= whiteCutoff && px[o + 2] >= whiteCutoff
}

for corner in [0, w - 1, (h - 1) * w, h * w - 1] where isNearWhite(corner) {
    isBackground[corner] = true
    stack.append(corner)
}
guard !stack.isEmpty else {
    FileHandle.standardError.write(Data("no white corners found — artwork already has its alpha\n".utf8))
    exit(1)
}
while let i = stack.popLast() {
    let x = i % w, y = i / w
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = x + dx, ny = y + dy
        guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
        let n = ny * w + nx
        guard !isBackground[n], isNearWhite(n) else { continue }
        isBackground[n] = true
        stack.append(n)
    }
}

// 2. Un-composite the antialiased band where the curve meets the background.
//    C = a*F + (1-a)*W, with W = white and F taken from solidly interior
//    neighbours, so a = ((W-C).(W-F)) / |W-F|^2.
let band = 3
var out = [UInt8](repeating: 0, count: w * h * 4)
var featheredPixels = 0

func nearBackground(_ x: Int, _ y: Int) -> Bool {
    for dy in -band...band {
        for dx in -band...band {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
            if isBackground[ny * w + nx] { return true }
        }
    }
    return false
}

func keepOpaque(_ o: Int) {
    out[o] = px[o]; out[o + 1] = px[o + 1]; out[o + 2] = px[o + 2]; out[o + 3] = 255
}

for y in 0..<h {
    for x in 0..<w {
        let i = y * w + x, o = i * 4
        if isBackground[i] { continue }
        if !nearBackground(x, y) {
            keepOpaque(o)
            continue
        }
        // Foreground estimate: mean of neighbours that are neither
        // background nor themselves in the band.
        var sum = [Double](repeating: 0, count: 3)
        var count = 0.0
        for dy in -band...band {
            for dx in -band...band {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                let n = ny * w + nx
                guard !isBackground[n], !nearBackground(nx, ny) else { continue }
                let no = n * 4
                sum[0] += Double(px[no]); sum[1] += Double(px[no + 1]); sum[2] += Double(px[no + 2])
                count += 1
            }
        }
        guard count > 0 else {
            keepOpaque(o)
            continue
        }
        let f = sum.map { $0 / count }
        let c = [Double(px[o]), Double(px[o + 1]), Double(px[o + 2])]
        var dot = 0.0, norm = 0.0
        for k in 0..<3 {
            let wc = 255.0 - c[k], wf = 255.0 - f[k]
            dot += wc * wf
            norm += wf * wf
        }
        let alpha = norm > 1.0 ? min(max(dot / norm, 0), 1) : 1.0
        if alpha < 0.999 { featheredPixels += 1 }
        // Store premultiplied, which is what compositing the recovered
        // foreground over the new transparency comes to.
        for k in 0..<3 {
            out[o + k] = UInt8(min(max((c[k] - (1 - alpha) * 255.0).rounded(), 0), 255))
        }
        out[o + 3] = UInt8((alpha * 255).rounded())
    }
}

FileHandle.standardError.write(Data(
    "cleared \(isBackground.filter { $0 }.count) background px, feathered \(featheredPixels) edge px\n".utf8))

// 3. Emit the master plus every downsample the catalog and site need.
func writePNG(_ cgImage: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "RestoreIconAlpha", code: 1)
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "RestoreIconAlpha", code: 2) }
}

let master: CGImage = out.withUnsafeMutableBytes { buf in
    let ctx = CGContext(
        data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: w * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return ctx.makeImage()!
}

for size in outputs.keys.sorted(by: >) {
    let scaled: CGImage
    if size == w {
        scaled = master
    } else {
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
        scaled = ctx.makeImage()!
    }
    for name in outputs[size]!.sorted() {
        try writePNG(scaled, to: outputDir.appendingPathComponent(name))
        FileHandle.standardError.write(Data("wrote \(name) (\(size)px)\n".utf8))
    }
}
