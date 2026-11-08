import Darwin
import Foundation

/// Path comparison that survives symlinks in the existing part of a path and
/// does not require the path to exist. Case-insensitive on purpose: a false
/// "inside" only refuses, a false "outside" could write into a library.
enum NASPathContainment {
    static func canonicalPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var trailing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            trailing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath().path
        for component in trailing {
            resolved += (resolved.hasSuffix("/") ? "" : "/") + component
        }
        return resolved
    }

    static func isInside(_ child: URL, of parent: URL) -> Bool {
        let childPath = canonicalPath(child).lowercased()
        let parentPath = canonicalPath(parent).lowercased()
        if childPath == parentPath { return true }
        let prefix = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"
        return childPath.hasPrefix(prefix)
    }
}

public struct NASParityReport: Codable, Sendable, Equatable {
    public var parity: Bool
    public var differences: [String]
    public var summary: NASScanSummary
    public var ledger: NASByteLedger
    /// NAS-NFR-09 allowed clean bytes: H + max(1% of H, 8 MiB).
    public var budgetBytes: Int64
    public var withinBudget: Bool
    public var scannerGroupCount: Int
    public var exhaustiveGroupCount: Int
    public var wallSeconds: Double
    /// `getrusage(RUSAGE_SELF).ru_maxrss`, in bytes on macOS.
    public var ruMaxrss: Int64

    public init(
        parity: Bool,
        differences: [String],
        summary: NASScanSummary,
        ledger: NASByteLedger,
        budgetBytes: Int64,
        withinBudget: Bool,
        scannerGroupCount: Int,
        exhaustiveGroupCount: Int,
        wallSeconds: Double,
        ruMaxrss: Int64
    ) {
        self.parity = parity
        self.differences = differences
        self.summary = summary
        self.ledger = ledger
        self.budgetBytes = budgetBytes
        self.withinBudget = withinBudget
        self.scannerGroupCount = scannerGroupCount
        self.exhaustiveGroupCount = exhaustiveGroupCount
        self.wallSeconds = wallSeconds
        self.ruMaxrss = ruMaxrss
    }
}

public enum NASParityError: LocalizedError, Sendable, Equatable {
    case scanDidNotFinish

    public var errorDescription: String? {
        switch self {
        case .scanDidNotFinish:
            return "The assessment ended without a summary, so parity could not be checked. Nothing in the library was changed."
        }
    }
}

/// Compares `NASAssessmentScanner`'s exact groups with an exhaustive pass that
/// hashes every supported media file with `FileIdentityHasher` (C-14 `assess-parity`).
public struct NASParityCheck: Sendable {
    private static let maximumReportedDifferences = 50

    private let fileSystem: NASScanFileSystem
    private let hasher: FileIdentityHasher

    public init(fileSystem: NASScanFileSystem = .live, hasher: FileIdentityHasher = FileIdentityHasher()) {
        self.fileSystem = fileSystem
        self.hasher = hasher
    }

    /// - Parameter exhaustiveGroupsOverride: replaces the exhaustive pass with a
    ///   caller-supplied set of groups (for example a corpus manifest's expected groups).
    public func run(
        rootURL: URL,
        stateDirectory: URL,
        exhaustiveGroupsOverride: [[String]]? = nil
    ) async throws -> NASParityReport {
        // Refuse before anything is created: state inside the root would write into the library.
        guard !NASPathContainment.isInside(stateDirectory, of: rootURL) else {
            throw NASAssessmentError.stateInsideLibrary(statePath: stateDirectory.path, rootPath: rootURL.path)
        }

        let started = ProcessInfo.processInfo.systemUptime
        let store = try NASAssessmentStore(
            url: stateDirectory.appendingPathComponent("assessment.sqlite"),
            libraryUUID: "nas-parity"
        )
        defer { store.close() }

        let scanner = NASAssessmentScanner(store: store, fileSystem: fileSystem)
        let configuration = NASAssessmentConfiguration(
            rootURL: rootURL,
            stateURL: stateDirectory.appendingPathComponent("assessment.sqlite")
        )
        var finished: NASScanSummary?
        for try await event in scanner.run(configuration, isCancelled: { false }) {
            if case let .finished(summary) = event { finished = summary }
        }
        guard let summary = finished else { throw NASParityError.scanDidNotFinish }

        let scannerGroups = Set(try store.exactGroups(generation: summary.generation).map { group in
            group.memberRelativePaths.map(Self.normalized).sorted()
        })
        // Unresolved candidates are the scanner's own reported gaps; they are not parity differences.
        let unresolved = Set(try store.issues(generation: summary.generation)
            .filter { $0.category == .unresolvedCandidate }
            .map { Self.normalized($0.relativePath) })

        var differences: [String] = []
        var exhaustive: Set<[String]>
        if let override = exhaustiveGroupsOverride {
            exhaustive = Set(override.map { $0.map(Self.normalized).sorted() })
        } else {
            let walk = exhaustiveGroups(rootURL: rootURL, ignoring: unresolved)
            exhaustive = walk.groups
            differences.append(contentsOf: walk.problems)
        }

        differences.append(contentsOf: Self.compare(scanner: scannerGroups, exhaustive: exhaustive))

        let ledger = summary.ledger
        return NASParityReport(
            parity: differences.isEmpty,
            differences: differences,
            summary: summary,
            ledger: ledger,
            budgetBytes: ledger.cleanReadBudget,
            withinBudget: ledger.isWithinBudget,
            scannerGroupCount: scannerGroups.count,
            exhaustiveGroupCount: exhaustive.count,
            wallSeconds: ProcessInfo.processInfo.systemUptime - started,
            ruMaxrss: Self.peakResidentBytes()
        )
    }

    // MARK: Comparison

    /// Differences between two sets of sorted relative-path arrays, capped for readability.
    static func compare(scanner: Set<[String]>, exhaustive: Set<[String]>) -> [String] {
        var lines: [String] = []
        for group in scanner.subtracting(exhaustive).sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            lines.append("Only in the assessment: \(group.joined(separator: " | "))")
        }
        for group in exhaustive.subtracting(scanner).sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            lines.append("Only in the exhaustive pass: \(group.joined(separator: " | "))")
        }
        if lines.count > maximumReportedDifferences {
            let extra = lines.count - maximumReportedDifferences
            lines = Array(lines.prefix(maximumReportedDifferences)) + ["... and \(extra) more differences"]
        }
        return lines
    }

    private static func normalized(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    private static func peakResidentBytes() -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return Int64(usage.ru_maxrss)
    }

    // MARK: Exhaustive pass

    /// Hashes every supported media file with `FileIdentityHasher` under the same
    /// inclusion rules as the scanner (dot names, links, system containers,
    /// packages and nested mounts are skipped; empty files are never grouped).
    private func exhaustiveGroups(rootURL: URL, ignoring unresolved: Set<String>) -> (groups: Set<[String]>, problems: [String]) {
        let rootPath = rootURL.standardizedFileURL.path
        var problems: [String] = []
        guard let rootEntry = fileSystem.entry(rootPath) else {
            return ([], ["Exhaustive pass could not read the root"])
        }

        var byDigest: [String: [String]] = [:]
        var stack: [(path: String, relative: String)] = [(rootPath, "")]
        while let directory = stack.popLast() {
            let names: [String]
            do {
                names = try fileSystem.listDirectory(directory.path)
            } catch {
                problems.append("Exhaustive pass could not list a folder: \(Self.normalized(directory.relative))")
                continue
            }
            for name in names.sorted() {
                if MediaLibraryRules.shouldSkipDiscoveredFile(named: name) { continue }
                let childPath = directory.path + "/" + name
                let childRelative = directory.relative.isEmpty ? name : directory.relative + "/" + name
                guard let entry = fileSystem.entry(childPath) else {
                    problems.append("Exhaustive pass could not read: \(Self.normalized(childRelative))")
                    continue
                }
                if entry.isSymbolicLink { continue }
                if entry.isDirectory {
                    if NASSystemContainerRules.isExcludedSystemContainer(name: name) { continue }
                    if entry.isPackage { continue }
                    if entry.deviceID != rootEntry.deviceID { continue }
                    stack.append((childPath, childRelative))
                    continue
                }
                guard entry.isRegularFile,
                      MediaLibraryRules.isSupportedMediaFile(path: name),
                      entry.size > 0
                else { continue }
                let relative = Self.normalized(childRelative)
                if unresolved.contains(relative) { continue }
                do {
                    let identity = try hasher.hashIdentity(at: URL(fileURLWithPath: childPath), knownSize: entry.size)
                    byDigest[identity.rawValue, default: []].append(relative)
                } catch {
                    problems.append("Exhaustive pass could not hash: \(relative)")
                }
            }
        }

        let groups = byDigest.values.filter { $0.count >= 2 }.map { $0.sorted() }
        return (Set(groups), problems)
    }
}
