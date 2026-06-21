#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// Advises the user once, per destination, when a chosen library lives on a
/// network volume. Chronoframe's cross-process lock is `flock`-based and only
/// reliably enforces mutual exclusion on the same machine; on SMB/AFP mounts
/// two Macs pointed at the same folder could both run. Single-host use is the
/// supported model, so this surfaces a warning rather than enforcing anything.
///
/// The "already warned" set is persisted (keyed by standardized path) so the
/// user is reminded at most once per destination, not on every run. The type is
/// pure and injectable: tests provide a stub `isRemote` closure and a scratch
/// `UserDefaults` to exercise the warn-once logic without a real network mount.
public struct NetworkDestinationAdvisory {
    public static let warningMessage = "This destination is on a network drive. Chronoframe can't guarantee safe results if it runs from more than one Mac at the same time — keep it to a single machine."

    static let defaultsKey = "chronoframe.warnedRemoteDestinations"

    private let isRemote: @Sendable (URL) -> Bool
    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = .standard,
        isRemote: @escaping @Sendable (URL) -> Bool = { DestinationOperationLock.isRemoteVolume($0) }
    ) {
        self.defaults = defaults
        self.isRemote = isRemote
    }

    /// Returns the warning message the first time a remote `destinationRoot` is
    /// seen and records it so subsequent calls for the same path return nil.
    /// Returns nil for local destinations and for destinations already warned.
    public func warningIfNeeded(for destinationRoot: URL) -> String? {
        let key = destinationRoot.standardizedFileURL.path
        var warned = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
        guard !warned.contains(key) else { return nil }
        guard isRemote(destinationRoot) else { return nil }
        warned.insert(key)
        defaults.set(Array(warned), forKey: Self.defaultsKey)
        return Self.warningMessage
    }
}
