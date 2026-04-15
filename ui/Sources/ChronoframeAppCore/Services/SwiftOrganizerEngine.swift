#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

@MainActor
public final class SwiftOrganizerEngine: OrganizerEngine {
    private let profilesRepository: any ProfilesRepositorying
    private let planner: DryRunPlanner
    private var activeTask: Task<Void, Never>?

    public init(
        profilesRepository: any ProfilesRepositorying = ProfilesRepository(),
        planner: DryRunPlanner = DryRunPlanner()
    ) {
        self.profilesRepository = profilesRepository
        self.planner = planner
    }

    public func preflight(_ configuration: RunConfiguration) async throws -> RunPreflight {
        let resolvedConfiguration = try resolvedConfiguration(for: configuration)
        let pendingJobs = pendingJobCount(destinationRoot: resolvedConfiguration.destinationPath)

        return RunPreflight(
            configuration: resolvedConfiguration,
            resolvedSourcePath: resolvedConfiguration.sourcePath,
            resolvedDestinationPath: resolvedConfiguration.destinationPath,
            pendingJobCount: pendingJobs,
            profilesFilePath: profilesRepository.profilesFileURL().path,
            missingDependencies: []
        )
    }

    public func start(_ configuration: RunConfiguration) throws -> AsyncThrowingStream<RunEvent, Error> {
        let resolvedConfiguration = try resolvedConfiguration(for: configuration)
        guard resolvedConfiguration.mode == .preview else {
            throw OrganizerEngineError.failedToLaunch("The native Swift engine currently supports preview runs only.")
        }

        return AsyncThrowingStream { continuation in
            let planner = self.planner
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let result = try planner.plan(
                        sourceRoot: URL(fileURLWithPath: resolvedConfiguration.sourcePath, isDirectory: true),
                        destinationRoot: URL(fileURLWithPath: resolvedConfiguration.destinationPath, isDirectory: true),
                        fastDestination: resolvedConfiguration.useFastDestinationScan
                    )

                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }

                    let artifacts = try Self.writeDryRunArtifacts(
                        result: result,
                        destinationRoot: resolvedConfiguration.destinationPath
                    )
                    let metrics = RunMetrics(
                        discoveredCount: result.discoveredSourceCount,
                        plannedCount: result.copyJobs.count,
                        alreadyInDestinationCount: result.counts.alreadyInDestinationCount,
                        duplicateCount: result.counts.duplicateCount,
                        hashErrorCount: result.counts.hashErrorCount
                    )

                    continuation.yield(.startup)
                    continuation.yield(.phaseStarted(phase: .discovery, total: result.discoveredSourceCount))
                    continuation.yield(.phaseCompleted(phase: .discovery, result: RunPhaseResult(found: result.discoveredSourceCount)))
                    continuation.yield(.phaseStarted(phase: .destinationIndexing, total: result.destinationIndexedCount))
                    continuation.yield(.phaseCompleted(phase: .destinationIndexing, result: RunPhaseResult()))
                    continuation.yield(.phaseStarted(phase: .sourceHashing, total: result.sourceHashedCount))
                    continuation.yield(.phaseCompleted(phase: .sourceHashing, result: RunPhaseResult()))
                    continuation.yield(.phaseStarted(phase: .classification, total: result.counts.newCount))
                    continuation.yield(
                        .phaseCompleted(
                            phase: .classification,
                            result: RunPhaseResult(
                                newCount: result.counts.newCount,
                                alreadyInDestinationCount: result.counts.alreadyInDestinationCount,
                                duplicateCount: result.counts.duplicateCount,
                                hashErrorCount: result.counts.hashErrorCount
                            )
                        )
                    )

                    for warning in result.warningMessages {
                        continuation.yield(.issue(RunIssue(severity: .warning, message: warning)))
                    }

                    continuation.yield(.copyPlanReady(count: result.copyJobs.count))
                    continuation.yield(
                        .complete(
                            RunSummary(
                                status: .dryRunFinished,
                                title: "Preview complete",
                                metrics: metrics,
                                artifacts: artifacts
                            )
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                Task { @MainActor in
                    self.activeTask = nil
                }
            }

            self.activeTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func resume(_ configuration: RunConfiguration) throws -> AsyncThrowingStream<RunEvent, Error> {
        try start(configuration)
    }

    public func cancelCurrentRun() {
        activeTask?.cancel()
        activeTask = nil
    }

    private func resolvedConfiguration(for configuration: RunConfiguration) throws -> RunConfiguration {
        let profiles = try profilesRepository.loadProfiles()
        let resolvedConfiguration: RunConfiguration

        if let profileName = configuration.profileName, !profileName.isEmpty {
            guard let profile = profiles.first(where: { $0.name == profileName }) else {
                throw OrganizerEngineError.profileNotFound(profileName)
            }

            resolvedConfiguration = RunConfiguration(
                mode: configuration.mode,
                sourcePath: profile.sourcePath,
                destinationPath: profile.destinationPath,
                profileName: profileName,
                useFastDestinationScan: configuration.useFastDestinationScan,
                verifyCopies: configuration.verifyCopies,
                workerCount: configuration.workerCount
            )
        } else {
            resolvedConfiguration = configuration
        }

        guard FileManager.default.fileExists(atPath: resolvedConfiguration.sourcePath) else {
            throw OrganizerEngineError.sourceDoesNotExist(resolvedConfiguration.sourcePath)
        }

        guard !resolvedConfiguration.destinationPath.isEmpty else {
            throw OrganizerEngineError.destinationMissing
        }

        return resolvedConfiguration
    }

    private func pendingJobCount(destinationRoot: String) -> Int {
        let dbURL = URL(fileURLWithPath: destinationRoot).appendingPathComponent(".organize_cache.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return 0 }

        do {
            let database = try OrganizerDatabase(url: dbURL, readOnly: true)
            defer { database.close() }
            return try database.pendingJobCount()
        } catch {
            return 0
        }
    }

    nonisolated private static func writeDryRunArtifacts(
        result: DryRunPlanningResult,
        destinationRoot: String
    ) throws -> RunArtifactPaths {
        let destinationURL = URL(fileURLWithPath: destinationRoot, isDirectory: true)
        let logsDirectoryURL = destinationURL.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)

        let timestamp = Self.timestampFormatter.string(from: Date())
        let reportURL = logsDirectoryURL.appendingPathComponent("dry_run_report_\(timestamp).csv")
        let logURL = destinationURL.appendingPathComponent(".organize_log.txt")

        try writeReport(result.copyJobs, to: reportURL)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try Data().write(to: logURL)
        }

        return RunArtifactPaths(
            destinationRoot: destinationRoot,
            reportPath: reportURL.path,
            logFilePath: logURL.path,
            logsDirectoryPath: logsDirectoryURL.path
        )
    }

    nonisolated private static func writeReport(_ jobs: [CopyJobRecord], to reportURL: URL) throws {
        var lines = ["Source,Destination,Hash,Status"]
        lines.append(
            contentsOf: jobs.map {
                [
                    csvField($0.sourcePath),
                    csvField($0.destinationPath),
                    csvField($0.identity.rawValue),
                    csvField($0.status.rawValue),
                ]
                .joined(separator: ",")
            }
        )
        try (lines.joined(separator: "\n") + "\n").write(to: reportURL, atomically: true, encoding: .utf8)
    }

    nonisolated private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    nonisolated private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
