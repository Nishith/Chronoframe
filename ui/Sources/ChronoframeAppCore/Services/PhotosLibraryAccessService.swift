#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
#if canImport(Photos)
import Photos
#endif

/// Read-only gateway to the Apple Photos library authorization state.
///
/// A protocol seam so higher layers and tests never touch `PHPhotoLibrary`
/// directly (there is no real library in CI). The concrete implementation
/// requests the `.readWrite` access level because macOS exposes no
/// read-only level — but Chronoframe never invokes a mutating PhotoKit
/// API. Photos import only ever reads and exports; see the planned
/// read-only safety invariant for Apple Photos import.
public protocol PhotosLibraryAccessing: Sendable {
    /// The current authorization state, read without presenting any UI.
    func currentAuthorization() -> PhotosAuthorizationStatus
    /// Presents the system permission prompt when the state is
    /// `.notDetermined`, then returns the resulting state. Safe to call
    /// in any state — already-decided states return unchanged.
    func requestReadAccess() async -> PhotosAuthorizationStatus
}

#if canImport(Photos)
public final class PhotosLibraryAccessService: PhotosLibraryAccessing {
    public init() {}

    public func currentAuthorization() -> PhotosAuthorizationStatus {
        PhotosAuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestReadAccess() async -> PhotosAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return PhotosAuthorizationStatus(status)
    }
}

extension PhotosAuthorizationStatus {
    /// Maps PhotoKit's authorization status onto the OS-independent
    /// domain enum. An unrecognized future case fails closed to
    /// `.denied` so an unknown state never grants read access.
    public init(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .limited: self = .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }
}
#else
/// Fallback for platforms without PhotoKit. The shipping macOS app always
/// has Photos; this only keeps `ChronoframeAppCore` buildable elsewhere
/// and reports no access.
public final class PhotosLibraryAccessService: PhotosLibraryAccessing {
    public init() {}
    public func currentAuthorization() -> PhotosAuthorizationStatus { .denied }
    public func requestReadAccess() async -> PhotosAuthorizationStatus { .denied }
}
#endif
