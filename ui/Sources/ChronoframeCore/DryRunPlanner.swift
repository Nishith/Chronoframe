import Foundation

public struct DryRunPlanningResult: Equatable, Sendable {
    public var discoveredSourceCount: Int
    public var destinationIndexedCount: Int
    public var sourceHashedCount: Int
    public var copyPlan: CopyPlanResult
    public var phaseSequence: [String]
    public var completeStatus: String

    public init(
        discoveredSourceCount: Int,
        destinationIndexedCount: Int,
        sourceHashedCount: Int,
        copyPlan: CopyPlanResult,
        phaseSequence: [String] = Self.pythonReferencePhaseSequence,
        completeStatus: String = Self.dryRunFinishedStatus
    ) {
        self.discoveredSourceCount = discoveredSourceCount
        self.destinationIndexedCount = destinationIndexedCount
        self.sourceHashedCount = sourceHashedCount
        self.copyPlan = copyPlan
        self.phaseSequence = phaseSequence
        self.completeStatus = completeStatus
    }

    public var copyJobs: [CopyJobRecord] {
        copyPlan.copyJobs
    }

    public var counts: CopyPlanCounts {
        copyPlan.counts
    }

    public var warningMessages: [String] {
        copyPlan.warningMessages
    }

    public static let dryRunFinishedStatus = "dry_run_finished"

    public static let pythonReferencePhaseSequence = [
        "startup",
        "discovery:start",
        "discovery:complete",
        "dest_hash:start",
        "dest_hash:complete",
        "src_hash:start",
        "src_hash:complete",
        "classification:start",
        "classification:complete",
        "copy_plan_ready",
        "complete",
    ]
}

public struct DryRunPlanner: Sendable {
    public var fileHasher: FileIdentityHasher
    public var dateResolver: FileDateResolver

    public init(
        fileHasher: FileIdentityHasher = FileIdentityHasher(),
        dateResolver: FileDateResolver = FileDateResolver()
    ) {
        self.fileHasher = fileHasher
        self.dateResolver = dateResolver
    }

    public func plan(
        sourceRoot: URL,
        destinationRoot: URL,
        databaseURL: URL? = nil,
        fastDestination: Bool = false,
        namingRules: PlannerNamingRules = .pythonReference
    ) throws -> DryRunPlanningResult {
        let organizerDatabaseURL = databaseURL
            ?? destinationRoot.appendingPathComponent(EngineArtifactLayout.pythonReference.queueDatabaseFilename)
        let database = try OrganizerDatabase(url: organizerDatabaseURL)
        defer { database.close() }

        let sourcePaths = try MediaDiscovery.discoverMediaFiles(at: sourceRoot)
        let destinationIndex = try buildDestinationIndex(
            destinationRoot: destinationRoot,
            database: database,
            fastDestination: fastDestination,
            namingRules: namingRules
        )

        let sourceCacheByPath = try Dictionary(
            uniqueKeysWithValues: database
                .loadRawCacheRecords(namespace: .source)
                .compactMap { rawRecord in
                    rawRecord.typedRecord.map { (rawRecord.path, $0) }
                }
        )

        var sourceResults: [String: ProcessedFileIdentity] = [:]
        var sourceUpdates: [FileCacheRecord] = []

        for path in sourcePaths {
            let result = fileHasher.processFile(at: path, cachedRecord: sourceCacheByPath[path])
            sourceResults[path] = result

            if let identity = result.identity, result.wasHashed {
                sourceUpdates.append(
                    FileCacheRecord(
                        namespace: .source,
                        path: path,
                        identity: identity,
                        size: result.size,
                        modificationTime: result.modificationTime
                    )
                )
            }
        }

        try database.saveCacheRecords(sourceUpdates)

        var counts = CopyPlanCounts()
        var sourceSeen: [FileIdentity: String] = [:]
        var primaryByDate: [String: [(sourcePath: String, identity: FileIdentity)]] = [:]
        var duplicates: [(sourcePath: String, identity: FileIdentity, dateBucket: String)] = []

        for path in sourcePaths {
            guard let identity = sourceResults[path]?.identity else {
                counts.hashErrorCount += 1
                continue
            }

            if destinationIndex.snapshot.pathsByIdentity[identity] != nil {
                counts.alreadyInDestinationCount += 1
                continue
            }

            let dateBucket = DateClassification.bucket(
                for: dateResolver.resolveDate(for: path),
                namingRules: namingRules
            )

            if sourceSeen[identity] != nil {
                duplicates.append((sourcePath: path, identity: identity, dateBucket: dateBucket))
                counts.duplicateCount += 1
                continue
            }

            sourceSeen[identity] = path
            primaryByDate[dateBucket, default: []].append((sourcePath: path, identity: identity))
            counts.newCount += 1
        }

        var primarySequences = destinationIndex.snapshot.sequenceState.primaryByDate
        var duplicateSequences = destinationIndex.snapshot.sequenceState.duplicatesByDate
        var overflowDates: [String] = []
        var transfers: [PlannedTransfer] = []

        for dateBucket in primaryByDate.keys.sorted() {
            let groupedFiles = primaryByDate[dateBucket] ?? []
            let startSequence = (primarySequences[dateBucket] ?? 0) + 1

            for (offset, item) in groupedFiles.enumerated() {
                let sequence = startSequence + offset
                if sequence > PlanningPathBuilder.maxSequence(for: namingRules.sequenceWidth),
                   !overflowDates.contains(dateBucket) {
                    overflowDates.append(dateBucket)
                }

                transfers.append(
                    PlannedTransfer(
                        sourcePath: item.sourcePath,
                        destinationPath: PlanningPathBuilder.buildDestinationPath(
                            for: item.sourcePath,
                            destinationRoot: destinationRoot.path,
                            dateBucket: dateBucket,
                            sequence: sequence,
                            duplicateDirectoryName: nil,
                            namingRules: namingRules
                        ),
                        identity: item.identity,
                        dateBucket: dateBucket,
                        isDuplicate: false
                    )
                )
            }

            if !groupedFiles.isEmpty {
                primarySequences[dateBucket] = startSequence + groupedFiles.count - 1
            }
        }

        for duplicate in duplicates {
            let sequence = (duplicateSequences[duplicate.dateBucket] ?? 0) + 1
            duplicateSequences[duplicate.dateBucket] = sequence

            transfers.append(
                PlannedTransfer(
                    sourcePath: duplicate.sourcePath,
                    destinationPath: PlanningPathBuilder.buildDestinationPath(
                        for: duplicate.sourcePath,
                        destinationRoot: destinationRoot.path,
                        dateBucket: duplicate.dateBucket,
                        sequence: sequence,
                        duplicateDirectoryName: namingRules.duplicateDirectoryName,
                        namingRules: namingRules
                    ),
                    identity: duplicate.identity,
                    dateBucket: duplicate.dateBucket,
                    isDuplicate: true
                )
            )
        }

        let warningMessages = overflowDates.isEmpty
            ? []
            : [
                "Sequence overflow on dates (>\(PlanningPathBuilder.maxSequence(for: namingRules.sequenceWidth)) files/day): \(overflowDates.joined(separator: ", "))",
            ]

        return DryRunPlanningResult(
            discoveredSourceCount: sourcePaths.count,
            destinationIndexedCount: destinationIndex.indexedFileCount,
            sourceHashedCount: sourcePaths.count,
            copyPlan: CopyPlanResult(
                transfers: transfers,
                counts: counts,
                warningMessages: warningMessages,
                sequenceState: SequenceCounterState(
                    primaryByDate: primarySequences,
                    duplicatesByDate: duplicateSequences
                )
            )
        )
    }

    private func buildDestinationIndex(
        destinationRoot: URL,
        database: OrganizerDatabase,
        fastDestination: Bool,
        namingRules: PlannerNamingRules
    ) throws -> DestinationIndexBuildResult {
        if fastDestination {
            let cachedRows = try database.loadRawCacheRecords(namespace: .destination)
            return DestinationIndexBuildResult(
                indexedFileCount: cachedRows.count,
                snapshot: DestinationIndexSnapshot.fromRawCacheRecords(cachedRows, namingRules: namingRules)
            )
        }

        let destinationPaths = try MediaDiscovery.discoverMediaFiles(at: destinationRoot)
        let cachedRowsByPath = try Dictionary(
            uniqueKeysWithValues: database
                .loadRawCacheRecords(namespace: .destination)
                .compactMap { rawRecord in
                    rawRecord.typedRecord.map { (rawRecord.path, $0) }
                }
        )

        var indexedPaths: [(path: String, identity: FileIdentity?)] = []
        var destinationUpdates: [FileCacheRecord] = []

        for path in destinationPaths {
            let result = fileHasher.processFile(at: path, cachedRecord: cachedRowsByPath[path])
            indexedPaths.append((path: path, identity: result.identity))

            if let identity = result.identity, result.wasHashed {
                destinationUpdates.append(
                    FileCacheRecord(
                        namespace: .destination,
                        path: path,
                        identity: identity,
                        size: result.size,
                        modificationTime: result.modificationTime
                    )
                )
            }
        }

        try database.saveCacheRecords(destinationUpdates)

        return DestinationIndexBuildResult(
            indexedFileCount: destinationPaths.count,
            snapshot: DestinationIndexSnapshot.fromIndexedPaths(indexedPaths, namingRules: namingRules)
        )
    }
}

private struct DestinationIndexBuildResult {
    var indexedFileCount: Int
    var snapshot: DestinationIndexSnapshot
}
