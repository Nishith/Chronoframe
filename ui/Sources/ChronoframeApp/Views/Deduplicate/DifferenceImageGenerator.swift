import CoreImage
import AppKit
import Foundation

enum DifferenceImageGenerator {
    /// Asynchronous entry point. Runs the Core Image pipeline on a
    /// detached background task so multi-megapixel inputs don't block
    /// the main thread while the spinner is supposed to be visible.
    static func generate(
        leftURL: URL,
        rightURL: URL,
        boostFactor: Double = 3.0
    ) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            generateBlocking(leftURL: leftURL, rightURL: rightURL, boostFactor: boostFactor)
        }.value
    }

    /// Synchronous body — package-internal for direct testing without a
    /// concurrency layer. Production code should call `generate(...)`.
    static func generateBlocking(leftURL: URL, rightURL: URL, boostFactor: Double = 3.0) -> NSImage? {
        guard let leftCI = CIImage(contentsOf: leftURL),
              let rightCI = CIImage(contentsOf: rightURL) else {
            return nil
        }

        let targetExtent = leftCI.extent
        let rightScaled: CIImage
        if rightCI.extent.size != targetExtent.size {
            let sx = targetExtent.width / rightCI.extent.width
            let sy = targetExtent.height / rightCI.extent.height
            rightScaled = rightCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        } else {
            rightScaled = rightCI
        }

        guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else { return nil }
        diffFilter.setValue(leftCI, forKey: kCIInputImageKey)
        diffFilter.setValue(rightScaled, forKey: kCIInputBackgroundImageKey)
        guard let diffOutput = diffFilter.outputImage else { return nil }

        guard let exposureFilter = CIFilter(name: "CIExposureAdjust") else { return nil }
        exposureFilter.setValue(diffOutput, forKey: kCIInputImageKey)
        exposureFilter.setValue(boostFactor, forKey: kCIInputEVKey)
        guard let boosted = exposureFilter.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        let renderExtent = boosted.extent
        guard let cgImage = context.createCGImage(boosted, from: renderExtent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
