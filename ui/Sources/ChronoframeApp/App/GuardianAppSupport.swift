#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation
import UserNotifications

/// App-target implementation of the AppCore `GuardianNotifying` seam. Posts a
/// local user notification when a scrub finds suspected bit rot. Kept in the App
/// target because AppCore must not depend on `ChronoframeApp`; the app already
/// owns the `UNUserNotificationCenter` delegate.
///
/// Stateless, so it is trivially `Sendable` and safe to hand to the off-main-actor
/// Guardian engine path.
struct GuardianUserNotifier: GuardianNotifying {
    func notifyBitRotDetected(libraryName: String, corruptCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Guardian found possible bit rot"
        let noun = corruptCount == 1 ? "file" : "files"
        content.body = "\(corruptCount) \(noun) in \(libraryName) no longer match the trusted copy. Your originals were not changed."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "guardian.bitrot.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
