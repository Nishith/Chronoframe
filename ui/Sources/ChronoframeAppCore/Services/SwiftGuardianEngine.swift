#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Concrete Guardian engine (Phase 4)
//
// Wires the pure `ChronoframeCore` Guardian pieces together and owns the on-disk
// Guardian state under Application Support (never inside the library):
//
//   scan     → GuardianLibraryProbe → GuardianIntegrityClassifier
//              → GuardianManifestUpdater.scanUpserts (persisted)
//   accept   → GuardianManifestUpdater.accept (persisted)
//   mirror   → GuardianMirrorPlanner → GuardianMirrorExecutor
//   restore  → GuardianRestorePlanner → GuardianRestoreExecutor
//
// Not `@MainActor`: the methods do blocking I/O and hashing and run off the main
// actor. The manifest DB is opened and closed per call so no long-lived handle is
// held across UI interactions.
public struct SwiftGuardianEngine: GuardianEngine {
    private let probe: GuardianLibraryProbe
    private let classifier: GuardianIntegrityClassifier
    private let updater: GuardianManifestUpdater
    private let mirrorPlanner: GuardianMirrorPlanner
    private let mirrorExecutor: GuardianMirrorExecutor
    private let restorePlanner: GuardianRestorePlanner
    private let restoreExecutor: GuardianRestoreExecutor

    public init() {
        self.probe = GuardianLibraryProbe()
        self.classifier = GuardianIntegrityClassifier()
        self.updater = GuardianManifestUpdater()
        self.mirrorPlanner = GuardianMirrorPlanner()
        self.mirrorExecutor = GuardianMirrorExecutor()
        self.restorePlanner = GuardianRestorePlanner()
        self.restoreExecutor = GuardianRestoreExecutor()
    }

    public func scan(
        libraryURL: URL,
        libraryIdentity: GuardianLibraryIdentity,
        isCancelled: @escaping @Sendable () -> Bool
    ) async throws -> GuardianScanOutcome {
        try GuardianPaths.ensureStateDirectory(for: libraryIdentity)
        let store = try openStore(for: libraryIdentity)
        defer { store.close() }

        let manifest = try store.loadKeyed()
        let probed = try probe.probe(libraryRoot: libraryURL, isCancelled: isCancelled)
        let report = classifier.classify(
            libraryRoot: libraryURL.path,
            manifest: manifest,
            observations: probed.observations,
            partialScan: probed.partialScan
        )
        let upserts = updater.scanUpserts(report: report, manifest: manifest)
        if !upserts.isEmpty {
            try store.upsert(upserts)
        }
        return GuardianScanOutcome(report: report, libraryIdentity: libraryIdentity)
    }

    public func acceptTrust(
        relativePaths: Set<String>,
        report: GuardianIntegrityReport,
        libraryIdentity: GuardianLibraryIdentity
    ) async throws {
        try GuardianPaths.ensureStateDirectory(for: libraryIdentity)
        let store = try openStore(for: libraryIdentity)
        defer { store.close() }

        let manifest = try store.loadKeyed()
        let upserts = updater.accept(relativePaths: relativePaths, report: report, manifest: manifest)
        if !upserts.isEmpty {
            try store.upsert(upserts)
        }
    }

    public func acknowledgeDeletions(
        relativePaths: Set<String>,
        report: GuardianIntegrityReport,
        libraryIdentity: GuardianLibraryIdentity
    ) async throws {
        try GuardianPaths.ensureStateDirectory(for: libraryIdentity)
        let store = try openStore(for: libraryIdentity)
        defer { store.close() }

        let manifest = try store.loadKeyed()
        let upserts = updater.acknowledgeDeletions(relativePaths: relativePaths, report: report, manifest: manifest)
        if !upserts.isEmpty {
            try store.upsert(upserts)
        }
    }

    public func planMirror(
        context: GuardianMirrorContext,
        libraryReport: GuardianIntegrityReport
    ) async throws -> GuardianMirrorPlan {
        let mirrorProbe = try probe.probe(libraryRoot: context.mirrorURL)
        return mirrorPlanner.plan(
            libraryRoot: context.libraryURL.path,
            mirrorRoot: context.mirrorURL.path,
            libraryReport: libraryReport,
            mirrorObservations: mirrorProbe.observations
        )
    }

    public func runMirror(
        context: GuardianMirrorContext,
        plan: GuardianMirrorPlan
    ) async throws -> GuardianMirrorExecutionResult {
        try GuardianPaths.ensureStateDirectory(for: context.libraryIdentity)
        return try mirrorExecutor.execute(
            plan: plan,
            libraryRoot: context.libraryURL,
            mirrorRoot: context.mirrorURL,
            stateDirectory: GuardianPaths.stateDirectory(for: context.libraryIdentity)
        )
    }

    public func planRestore(
        libraryURL: URL,
        mirrorURL: URL,
        libraryReport: GuardianIntegrityReport
    ) async throws -> GuardianRestorePlan {
        let mirrorProbe = try probe.probe(libraryRoot: mirrorURL)
        return restorePlanner.plan(
            libraryRoot: libraryURL.path,
            mirrorRoot: mirrorURL.path,
            libraryReport: libraryReport,
            mirrorObservations: mirrorProbe.observations
        )
    }

    public func runRestore(context: GuardianRestoreContext) async throws -> GuardianRestoreExecutionResult {
        try GuardianPaths.ensureStateDirectory(for: context.libraryIdentity)
        return try restoreExecutor.execute(
            plan: context.plan,
            selectedPaths: context.selectedPaths,
            libraryRoot: context.libraryURL,
            mirrorRoot: context.mirrorURL,
            stateDirectory: GuardianPaths.stateDirectory(for: context.libraryIdentity)
        )
    }

    private func openStore(for identity: GuardianLibraryIdentity) throws -> GuardianManifestStore {
        try GuardianManifestStore(url: GuardianPaths.manifestURL(for: identity), libraryIdentity: identity)
    }
}
