import Foundation

/// Read-access authorization state for the Apple Photos library,
/// decoupled from PhotoKit so domain logic, view models, and tests never
/// need to import `Photos`. `PhotosLibraryAccessService` maps
/// `PHAuthorizationStatus` onto these cases at the OS boundary.
///
/// Chronoframe only ever *reads* the Photos library, but macOS has no
/// read-only authorization level — reading requires the `.readWrite`
/// level (Chronoframe requests it and never writes). `.limited` grants
/// read access to a user-chosen subset, which Chronoframe honors by
/// importing only the assets it can see.
public enum PhotosAuthorizationStatus: String, Equatable, Sendable, CaseIterable {
    /// The user has not been asked yet; the system prompt can still run.
    case notDetermined
    /// Access was explicitly declined in this app's Privacy settings.
    case denied
    /// Access is blocked by a system policy (parental controls, MDM);
    /// the user cannot grant it from within the app.
    case restricted
    /// Full read access to the whole library.
    case authorized
    /// Read access to a user-selected subset of the library.
    case limited

    /// True when Chronoframe can enumerate and export at least some
    /// assets. `.limited` counts — it simply sees fewer assets.
    public var allowsReading: Bool {
        switch self {
        case .authorized, .limited:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        }
    }

    /// True when presenting the system permission prompt could still
    /// change the outcome. Only `.notDetermined` qualifies; `.denied`
    /// and `.restricted` require the user to leave the app.
    public var canPromptForAccess: Bool {
        self == .notDetermined
    }

    /// True when changing this state requires leaving the app (System
    /// Settings) or is not user-changeable at all — the in-app prompt
    /// will not help.
    public var isBlocked: Bool {
        switch self {
        case .denied, .restricted:
            return true
        case .notDetermined, .authorized, .limited:
            return false
        }
    }
}
