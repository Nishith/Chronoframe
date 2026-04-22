import AppKit
import Foundation

@MainActor
enum AboutPanel {
    static func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: options())
    }

    private static func options() -> [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: "Chronoframe",
            .applicationVersion: versionString,
            .version: buildString,
            .credits: creditsAttributedString,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyrightString,
        ]
    }

    private static var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private static var copyrightString: String {
        "© 2026 Nishith Nand. All rights reserved."
    }

    private static var creditsAttributedString: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        paragraph.lineSpacing = 1

        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let header: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]

        let out = NSMutableAttributedString()
        func appendHeader(_ text: String) {
            out.append(NSAttributedString(string: text + "\n", attributes: header))
        }
        func appendBody(_ text: String) {
            out.append(NSAttributedString(string: text + "\n\n", attributes: body))
        }

        appendHeader("License")
        appendBody(
            "Chronoframe is commercial software. This copy of Chronoframe is licensed, not sold, to you for use only under the terms of the Licensed Application End User License Agreement (the \"Standard EULA\") entered into between you and the store operator from which you obtained Chronoframe. Copies obtained through the Mac App Store or the App Store are distributed under Apple's Standard EULA, available at https://www.apple.com/legal/internet-services/itunes/dev/stdeula/. By installing or using Chronoframe, you agree to the Standard EULA."
        )

        appendHeader("Permitted Use")
        appendBody(
            "Subject to the Standard EULA, you are granted a non-transferable license to install and use Chronoframe on Apple-branded devices that you own or control, for your personal, non-commercial use, or for internal use within a single business entity that has acquired a license for each user. Chronoframe may not be rented, leased, sold, sublicensed, redistributed, reverse-engineered, or modified except as expressly permitted by the Standard EULA or applicable law."
        )

        appendHeader("Disclaimer of Warranty")
        appendBody(
            "Chronoframe is provided \"as is\" and \"as available,\" without warranty of any kind, express or implied, to the fullest extent permitted by applicable law. Chronoframe copies files; it does not move or delete originals. However, no warranty is given that any particular run will complete without error. You remain responsible for maintaining adequate backups of your data before and after using Chronoframe."
        )

        appendHeader("Third-Party Components")
        appendBody(
            "Chronoframe incorporates Apple's SwiftUI and Foundation frameworks and the SQLite library (public domain). Their use is governed by their respective licenses."
        )

        appendHeader("Trademarks")
        let trademarks = "Chronoframe and the Chronoframe logo are trademarks of Nishith Nand. Apple, the Apple logo, macOS, and App Store are trademarks of Apple Inc., registered in the U.S. and other countries and regions. All other trademarks are the property of their respective owners."
        out.append(NSAttributedString(string: trademarks, attributes: body))

        return out
    }
}
