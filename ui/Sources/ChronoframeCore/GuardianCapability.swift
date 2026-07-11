import Foundation

/// Master switch for Library Guardian.
///
/// Guardian is a large, safety-critical feature that lands as one phased pull
/// request. It stays **off** until every phase (manifest + scan, mirror, restore,
/// scheduling, UI) is complete, so the whole thing can merge dark behind a single
/// review surface without exposing a half-wired destination or scheduler. Flip
/// `isEnabled` to `true` in the final phase; the sidebar entry and the scheduler
/// both consult this single source of truth.
public enum GuardianCapability {
    public static let isEnabled = false
}
