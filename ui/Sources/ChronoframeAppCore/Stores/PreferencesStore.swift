#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import Combine

@MainActor
public final class PreferencesStore: ObservableObject {
    public static let minimumLogCapacity = 250
    public static let maximumLogCapacity = 10_000

    /// Bump this when a stored UserDefaults key is renamed, removed, or
    /// changes shape. Add a closure to `Self.migrations` keyed by the new
    /// target version that rewrites or seeds the affected keys. On next
    /// app launch, every pending migration runs in order before the
    /// individual `@Published` properties read their defaults — so the
    /// store always observes the post-migration layout.
    ///
    /// Bumping the version without adding a corresponding migration is
    /// harmless: the framework records the new version and moves on.
    public static let currentPreferencesSchemaVersion: Int = 1

    /// Migrations keyed by *target* version. Each closure may read or
    /// rewrite UserDefaults entries. v1 is the baseline — present-day key
    /// names are v1 — so the migration is a marker only. Future renames
    /// register e.g. `2: { defaults in defaults.set(defaults.string(forKey: "old"), forKey: "new"); defaults.removeObject(forKey: "old") }`.
    private nonisolated(unsafe) static let migrations: [Int: (UserDefaults) -> Void] = [
        1: { _ in },
    ]

    private static let schemaVersionDefaultsKey = "chronoframe.prefsSchemaVersion"

    /// Run every pending migration whose key is greater than the recorded
    /// version, in order. Records the new version after the last one
    /// succeeds. Public so tests can drive the framework against a fresh
    /// `UserDefaults(suiteName:)` instance.
    public static func runPendingMigrations(in defaults: UserDefaults) {
        let current = defaults.object(forKey: schemaVersionDefaultsKey) as? Int ?? 0
        let target = currentPreferencesSchemaVersion
        guard current < target else { return }
        for next in (current + 1)...target {
            migrations[next]?(defaults)
        }
        defaults.set(target, forKey: schemaVersionDefaultsKey)
    }

    /// Snapshot of the stored schema version. Returns 0 for fresh
    /// `UserDefaults` instances that have never been written to.
    public static func storedSchemaVersion(in defaults: UserDefaults) -> Int {
        defaults.object(forKey: schemaVersionDefaultsKey) as? Int ?? 0
    }

    private let defaults: UserDefaults

    @Published public var workerCount: Int {
        didSet { persist(workerCount, key: "workerCount") }
    }

    @Published public var verifyCopies: Bool {
        didSet { persist(verifyCopies, key: "verifyCopies") }
    }

    @Published public var parallelTransferEnabled: Bool {
        didSet { persist(parallelTransferEnabled, key: "parallelTransferEnabled") }
    }

    @Published public var logBufferCapacity: Int {
        didSet {
            let clamped = max(Self.minimumLogCapacity, min(Self.maximumLogCapacity, logBufferCapacity))
            if clamped != logBufferCapacity {
                logBufferCapacity = clamped
                return
            }
            persist(logBufferCapacity, key: "logBufferCapacity")
        }
    }

    @Published public var lastManualSourcePath: String {
        didSet { persist(lastManualSourcePath, key: "lastManualSourcePath") }
    }

    @Published public var lastManualDestinationPath: String {
        didSet { persist(lastManualDestinationPath, key: "lastManualDestinationPath") }
    }

    @Published public var lastDeduplicateDestinationPath: String {
        didSet { persist(lastDeduplicateDestinationPath, key: "lastDeduplicateDestinationPath") }
    }

    @Published public var lastSelectedProfileName: String {
        didSet { persist(lastSelectedProfileName, key: "lastSelectedProfileName") }
    }

    @Published public var folderStructure: FolderStructure {
        didSet { persist(folderStructure.rawValue, key: "folderStructure") }
    }

    @Published public var smartEventSuggestionsEnabled: Bool {
        didSet { persist(smartEventSuggestionsEnabled, key: "smartEventSuggestionsEnabled") }
    }

    @Published public var dedupeTimeWindowSeconds: Int {
        didSet { persist(dedupeTimeWindowSeconds, key: "dedupeTimeWindowSeconds") }
    }

    @Published public var dedupeBurstModeEnabled: Bool {
        didSet { persist(dedupeBurstModeEnabled, key: "dedupeBurstModeEnabled") }
    }

    @Published public var dedupeSimilarityPreset: DedupeSimilarityPreset {
        didSet { persist(dedupeSimilarityPreset.rawValue, key: "dedupeSimilarityPreset") }
    }

    @Published public var dedupeTreatRawJpegPairsAsUnit: Bool {
        didSet { persist(dedupeTreatRawJpegPairsAsUnit, key: "dedupeTreatRawJpegPairsAsUnit") }
    }

    @Published public var dedupeTreatLivePhotoPairsAsUnit: Bool {
        didSet { persist(dedupeTreatLivePhotoPairsAsUnit, key: "dedupeTreatLivePhotoPairsAsUnit") }
    }

    @Published public var dedupeIncludeExactDuplicates: Bool {
        didSet { persist(dedupeIncludeExactDuplicates, key: "dedupeIncludeExactDuplicates") }
    }

    @Published public var dedupePerceptualVideoMatchingEnabled: Bool {
        didSet { persist(dedupePerceptualVideoMatchingEnabled, key: "dedupePerceptualVideoMatchingEnabled") }
    }

    @Published public var dedupeAllowHardDelete: Bool {
        didSet {
            if dedupeAllowHardDelete {
                dedupeAllowHardDelete = false
                return
            }
            persist(false, key: "dedupeAllowHardDelete")
        }
    }

    // MARK: - Library Guardian (in-app + catch-up scheduling)

    /// When on, Chronoframe runs a read-only integrity scrub on the configured
    /// cadence while the app is open, catching up one missed run on launch/wake.
    @Published public var guardianAutoScrubEnabled: Bool {
        didSet { persist(guardianAutoScrubEnabled, key: "guardianAutoScrubEnabled") }
    }

    /// The scrub cadence, in seconds. Clamped to a sane minimum so a
    /// misconfiguration can't spin the scrubber. Default: weekly.
    @Published public var guardianScrubIntervalSeconds: Int {
        didSet {
            let clamped = max(Self.minimumGuardianScrubIntervalSeconds, guardianScrubIntervalSeconds)
            if clamped != guardianScrubIntervalSeconds {
                guardianScrubIntervalSeconds = clamped
                return
            }
            persist(guardianScrubIntervalSeconds, key: "guardianScrubIntervalSeconds")
        }
    }

    /// When on, a clean, complete scrub is followed by a verified mirror pass (only
    /// when the mirror volume is online). A corrupt or partial scrub is skipped.
    @Published public var guardianAutoMirrorEnabled: Bool {
        didSet { persist(guardianAutoMirrorEnabled, key: "guardianAutoMirrorEnabled") }
    }

    /// When on, a scrub that finds corruption posts a user notification.
    @Published public var guardianNotifyOnBitRot: Bool {
        didSet { persist(guardianNotifyOnBitRot, key: "guardianNotifyOnBitRot") }
    }

    public static let minimumGuardianScrubIntervalSeconds = 3_600
    public static let defaultGuardianScrubIntervalSeconds = 604_800

    public init(defaults: UserDefaults = .standard) {
        // Run any pending key migrations *before* the @Published properties
        // read their stored values, so the store always sees the current
        // schema layout. v1 is the baseline marker; future bumps register a
        // closure in `Self.migrations` that rewrites the affected keys.
        Self.runPendingMigrations(in: defaults)

        self.defaults = defaults
        self.workerCount = defaults.object(forKey: "workerCount") as? Int ?? 8
        self.verifyCopies = defaults.object(forKey: "verifyCopies") as? Bool ?? true
        self.parallelTransferEnabled = defaults.object(forKey: "parallelTransferEnabled") as? Bool ?? true
        self.logBufferCapacity = defaults.object(forKey: "logBufferCapacity") as? Int ?? 2_000
        self.lastManualSourcePath = defaults.string(forKey: "lastManualSourcePath") ?? ""
        self.lastManualDestinationPath = defaults.string(forKey: "lastManualDestinationPath") ?? ""
        self.lastDeduplicateDestinationPath = defaults.string(forKey: "lastDeduplicateDestinationPath") ?? ""
        self.lastSelectedProfileName = defaults.string(forKey: "lastSelectedProfileName") ?? ""
        let storedStructure = defaults.string(forKey: "folderStructure").flatMap(FolderStructure.init(rawValue:))
        self.folderStructure = storedStructure ?? .yyyyMMDD
        self.smartEventSuggestionsEnabled = defaults.object(forKey: "smartEventSuggestionsEnabled") as? Bool ?? false
        self.dedupeTimeWindowSeconds = defaults.object(forKey: "dedupeTimeWindowSeconds") as? Int ?? 30
        self.dedupeBurstModeEnabled = defaults.object(forKey: "dedupeBurstModeEnabled") as? Bool ?? true
        let storedPreset = defaults.string(forKey: "dedupeSimilarityPreset").flatMap(DedupeSimilarityPreset.init(rawValue:))
        self.dedupeSimilarityPreset = storedPreset ?? .balanced
        self.dedupeTreatRawJpegPairsAsUnit = defaults.object(forKey: "dedupeTreatRawJpegPairsAsUnit") as? Bool ?? true
        self.dedupeTreatLivePhotoPairsAsUnit = defaults.object(forKey: "dedupeTreatLivePhotoPairsAsUnit") as? Bool ?? true
        self.dedupeIncludeExactDuplicates = defaults.object(forKey: "dedupeIncludeExactDuplicates") as? Bool ?? true
        self.dedupePerceptualVideoMatchingEnabled = defaults.object(forKey: "dedupePerceptualVideoMatchingEnabled") as? Bool ?? false
        self.dedupeAllowHardDelete = false
        defaults.set(false, forKey: "dedupeAllowHardDelete")
        self.guardianAutoScrubEnabled = defaults.object(forKey: "guardianAutoScrubEnabled") as? Bool ?? false
        let storedInterval = defaults.object(forKey: "guardianScrubIntervalSeconds") as? Int
            ?? Self.defaultGuardianScrubIntervalSeconds
        self.guardianScrubIntervalSeconds = max(Self.minimumGuardianScrubIntervalSeconds, storedInterval)
        self.guardianAutoMirrorEnabled = defaults.object(forKey: "guardianAutoMirrorEnabled") as? Bool ?? false
        self.guardianNotifyOnBitRot = defaults.object(forKey: "guardianNotifyOnBitRot") as? Bool ?? true
    }

    public func makeDeduplicateConfiguration(destinationPath: String) -> DeduplicateConfiguration {
        DeduplicateConfiguration(
            destinationPath: destinationPath,
            timeWindowSeconds: dedupeTimeWindowSeconds,
            burstModeEnabled: dedupeBurstModeEnabled,
            similarityThreshold: dedupeSimilarityPreset.similarityThreshold,
            dhashHammingThreshold: dedupeSimilarityPreset.dhashHammingThreshold,
            treatRawJpegPairsAsUnit: dedupeTreatRawJpegPairsAsUnit,
            treatLivePhotoPairsAsUnit: dedupeTreatLivePhotoPairsAsUnit,
            enableExactDuplicateGroup: dedupeIncludeExactDuplicates,
            workerCount: workerCount,
            perceptualVideoMatchingEnabled: dedupePerceptualVideoMatchingEnabled
                && dedupeSimilarityPreset.allowsPerceptualVideoMatching,
            videoPerceptualMatchConfiguration: dedupeSimilarityPreset.videoPerceptualConfiguration
        )
    }

    public func bookmark(for key: String) -> FolderBookmark? {
        guard
            let data = defaults.data(forKey: bookmarkDefaultsKey(for: key)),
            let path = defaults.string(forKey: bookmarkPathDefaultsKey(for: key))
        else {
            return nil
        }

        return FolderBookmark(key: key, path: path, data: data)
    }

    public func storeBookmark(_ bookmark: FolderBookmark) {
        defaults.set(bookmark.data, forKey: bookmarkDefaultsKey(for: bookmark.key))
        defaults.set(bookmark.path, forKey: bookmarkPathDefaultsKey(for: bookmark.key))
    }

    public func removeBookmark(for key: String) {
        defaults.removeObject(forKey: bookmarkDefaultsKey(for: key))
        defaults.removeObject(forKey: bookmarkPathDefaultsKey(for: key))
    }

    /// All stored bookmark keys with the given prefix (e.g. "watched.").
    /// The watched-sources startup sweep uses this to drop bookmarks
    /// whose registry row was removed before a crash landed the
    /// bookmark deletion.
    public func bookmarkKeys(withPrefix prefix: String) -> [String] {
        defaults.dictionaryRepresentation().keys.compactMap { defaultsKey in
            guard defaultsKey.hasPrefix("bookmark.\(prefix)"),
                  defaultsKey.hasSuffix(".data")
            else {
                return nil
            }
            return String(defaultsKey.dropFirst("bookmark.".count).dropLast(".data".count))
        }
    }

    private func persist(_ value: some Any, key: String) {
        defaults.set(value, forKey: key)
    }

    private func bookmarkDefaultsKey(for key: String) -> String {
        "bookmark.\(key).data"
    }

    private func bookmarkPathDefaultsKey(for key: String) -> String {
        "bookmark.\(key).path"
    }
}
