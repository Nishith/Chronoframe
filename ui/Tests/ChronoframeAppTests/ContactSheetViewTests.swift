import AppKit
import SwiftUI
import XCTest
@testable import ChronoframeApp

@MainActor
final class ContactSheetViewTests: XCTestCase {
    func testThumbnailCellClipsWideImagesToCellBounds() throws {
        let cellSize: CGFloat = 80
        let thumbnail = Self.makeImage(
            size: NSSize(width: 320, height: 80),
            color: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
        )
        let rendered = try render(
            HStack(spacing: 0) {
                ContactSheetThumbnailCell(thumbnail: thumbnail, cellSize: cellSize)
                Color.clear.frame(width: cellSize, height: cellSize)
            }
            .frame(width: cellSize * 2, height: cellSize, alignment: .leading)
            .background(Color.black),
            size: NSSize(width: cellSize * 2, height: cellSize)
        )

        let thumbnailProbe = try XCTUnwrap(
            rendered.colorAt(x: Int(Double(rendered.pixelsWide) * 0.25), y: Int(Double(rendered.pixelsHigh) * 0.5))
        )
        XCTAssertGreaterThan(thumbnailProbe.redComponent, 0.90)

        let spilloverProbe = try XCTUnwrap(
            rendered.colorAt(x: Int(Double(rendered.pixelsWide) * 0.75), y: Int(Double(rendered.pixelsHigh) * 0.5))
        )
        XCTAssertLessThan(spilloverProbe.redComponent, 0.10)
        XCTAssertLessThan(spilloverProbe.greenComponent, 0.10)
        XCTAssertLessThan(spilloverProbe.blueComponent, 0.10)
    }

    func testThumbnailCellKeepsStableSquareLayout() {
        let cellSize: CGFloat = 80
        let thumbnail = Self.makeImage(
            size: NSSize(width: 80, height: 80),
            color: NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1)
        )
        let hostingView = NSHostingView(
            rootView: ContactSheetThumbnailCell(thumbnail: thumbnail, cellSize: cellSize)
        )

        XCTAssertEqual(hostingView.fittingSize.width, cellSize, accuracy: 0.5)
        XCTAssertEqual(hostingView.fittingSize.height, cellSize, accuracy: 0.5)
    }

    func testThumbnailPipelineSkipsFailedCandidatesAndKeepsSuccessfulOrder() async {
        let urls = (0..<8).map { URL(fileURLWithPath: "/tmp/frame-\($0).jpg") }

        let imageData = await ContactSheetThumbnailPipeline.loadThumbnailData(
            from: urls,
            count: 3,
            size: CGSize(width: 80, height: 80),
            scale: 2
        ) { url, _, _ in
            let rawIndex = url
                .deletingPathExtension()
                .lastPathComponent
                .replacingOccurrences(of: "frame-", with: "")
            guard let index = UInt8(rawIndex), !index.isMultiple(of: 2) else {
                return nil
            }
            return Data([index])
        }

        XCTAssertEqual(imageData.compactMap(\.first), [1, 3, 5])
        XCTAssertEqual(ContactSheetThumbnailPipeline.candidateLimit(for: 12), 48)
    }

    /// Wide-layout doctrine: the tile grid is the media surface that grows
    /// with its column. The plan must clamp at both ends — a floor so the
    /// sheet reads as a grid even before width measurement, and a ceiling so
    /// source enumeration cost is fixed no matter how wide the window gets.
    func testContactSheetLayoutScalesTileCountWithColumnWidth() {
        // Pre-measurement (zero width) falls back to the minimum grid.
        XCTAssertEqual(
            ContactSheetLayout.tileCount(forColumnWidth: 0, cellSize: 92),
            ContactSheetLayout.minimumTiles
        )
        // A narrow evidence column (~470pt → 4 columns × 2 rows = 8) still
        // shows the floor.
        XCTAssertEqual(
            ContactSheetLayout.tileCount(forColumnWidth: 470, cellSize: 92),
            ContactSheetLayout.minimumTiles
        )
        // The full evidence cap (1,400pt → 14 columns) shows two full rows.
        XCTAssertEqual(ContactSheetLayout.tileCount(forColumnWidth: 1_400, cellSize: 92), 28)
        // Absurd widths clamp at the enumeration bound.
        XCTAssertEqual(
            ContactSheetLayout.tileCount(forColumnWidth: 5_000, cellSize: 92),
            ContactSheetLayout.maximumTiles
        )

        // Monotonic: more width never shows fewer frames, and the displayed
        // count never exceeds what the loader fetched.
        var previous = 0
        for width in stride(from: CGFloat(0), through: 3_000, by: 50) {
            let count = ContactSheetLayout.tileCount(forColumnWidth: width, cellSize: 92)
            XCTAssertGreaterThanOrEqual(count, previous)
            XCTAssertLessThanOrEqual(count, ContactSheetLayout.maximumTiles)
            previous = count
        }
    }

    /// The collapsed empty state must distinguish "this folder has no media"
    /// from "media exists but previews failed" — the second points at a real
    /// problem (permissions, unsupported formats) and must not be hidden
    /// behind the generic line.
    func testEmptyResultMessageDistinguishesNoMediaFromPreviewFailure() {
        XCTAssertEqual(
            ContactSheetLayout.emptyResultMessage(foundMediaCount: 0),
            "No photos or videos in this folder yet. Frames appear here as soon as Chronoframe can see them."
        )
        XCTAssertEqual(
            ContactSheetLayout.emptyResultMessage(foundMediaCount: 1),
            "Found 1 media file, but previews couldn't be created for them."
        )
        XCTAssertEqual(
            ContactSheetLayout.emptyResultMessage(foundMediaCount: 12),
            "Found 12 media files, but previews couldn't be created for them."
        )
    }

    private func render<V: View>(_ view: V, size: NSSize) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        let bounds = hostingView.bounds
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: bounds))
        hostingView.cacheDisplay(in: bounds, to: bitmap)
        return bitmap
    }

    private static func makeImage(size: NSSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
}
