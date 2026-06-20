#if canImport(AppKit)
import AppKit
import Foundation

@MainActor
public final class DockProgressRenderer {
    public static func update(progress: Double, isRunning: Bool) {
        // Skip during tests to prevent headless WindowServer issues
        guard NSClassFromString("XCTestCase") == nil else { return }
        
        let dockTile = NSApp.dockTile
        if isRunning {
            let size = dockTile.size
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
            
            // Set the app icon as the base image
            let appIcon = NSImage(named: NSImage.applicationIconName) ?? NSImage()
            
            let canvas = NSImage(size: size)
            canvas.lockFocus()
            
            // Draw app icon
            appIcon.draw(in: NSRect(origin: .zero, size: size))
            
            // Draw progress track (background pill/bar near the bottom of the dock icon)
            let margin: CGFloat = 12
            let barHeight: CGFloat = 8
            let barWidth = size.width - (margin * 2)
            let barRect = NSRect(x: margin, y: margin, width: barWidth, height: barHeight)
            
            let trackPath = NSBezierPath(roundedRect: barRect, xRadius: 4, yRadius: 4)
            NSColor.windowBackgroundColor.withAlphaComponent(0.85).setFill()
            trackPath.fill()
            
            // Draw progress fill
            let fillWidth = barWidth * CGFloat(max(0, min(1, progress)))
            if fillWidth > 0 {
                let fillRect = NSRect(x: margin, y: margin, width: fillWidth, height: barHeight)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 4, yRadius: 4)
                
                // Chronoframe Brand amber color: RGB 245, 158, 11 (Hex #F59E0B)
                NSColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 1.0).setFill()
                fillPath.fill()
            }
            
            canvas.unlockFocus()
            imageView.image = canvas
            dockTile.contentView = imageView
            dockTile.display()
        } else {
            // Restore default dock icon
            dockTile.contentView = nil
            dockTile.display()
        }
    }
}
#endif
