import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

/// WP-06 / C-08: the remote copy policy in `TransferExecutor`. "Remote" is
/// simulated through the `remotePolicyProvider` seam, so every test runs on a
/// local temporary directory and never touches a network volume.
final class ChronoframeCoreNASRemoteCopyPolicyTests: XCTestCase {
    private static let remoteFileSystemID: UInt64 = 4242
    private static let remoteMountPoint = "/Volumes/ChronoframeTestShare"
    private static let noRetry = RetryPolicy(maxAttempts: 1, minimumBackoffSeconds: 0, maximumBackoffSeconds: 0, nonRetryableErrnos: [])

    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChronoframeCoreNASRemoteCopyPolicyTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Policy resolution

    func testResolveTreatsRemoteAndUnknownVolumesAsRemoteAndLocalAsLocal() {
        let destination = URL(fileURLWithPath: "/Volumes/Photos/Library", isDirectory: true)

        let local = NASRemoteCopyPolicy.resolve(
            destinationRoot: destination,
            classifier: NASVolumeClassifier { _ in
                NASStatfsSnapshot(fileSystemType: "apfs", mountedOn: "/", mountedFrom: "/dev/disk3s1", flags: UInt32(MNT_LOCAL), fileSystemID: 1)
            }
        )
        XCTAssertFalse(local.isRemote)
        XCTAssertEqual(local.volume.kind, .local)

        let remote = NASRemoteCopyPolicy.resolve(
            destinationRoot: destination,
            classifier: NASVolumeClassifier { _ in
                NASStatfsSnapshot(fileSystemType: "smbfs", mountedOn: "/Volumes/Photos", mountedFrom: "//user@nas.local/Photos", flags: 0, fileSystemID: 7)
            }
        )
        XCTAssertTrue(remote.isRemote)
        XCTAssertEqual(remote.volume.fileSystemID, 7)

        let unknown = NASRemoteCopyPolicy.resolve(
            destinationRoot: destination,
            classifier: NASVolumeClassifier { _ in nil }
        )
        XCTAssertTrue(unknown.isRemote, "an unclassifiable volume is treated as remote")
        XCTAssertEqual(unknown.volume.kind, .unknown)
    }

    func testLocalPlaceholderPolicyIsNotRemote() {
        XCTAssertFalse(NASRemoteCopyPolicy.local.isRemote)
        XCTAssertEqual(NASRemoteCopyPolicy.local.volume.kind, .local)
    }

    // MARK: - Verification forced (D-NAS-42)

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 3
    func testRemoteRunWithVerificationOffAbortsBeforeAnyJob() throws {
        let env = try makeEnvironment(jobCount: 3)
        defer { env.close() }
        let executor = makeRemoteExecutor()
        let issues = IssueRecorder()

        let result = try run(executor, env, verifyCopies: false, issues: issues)

        let expected = NASRemoteCopyError.verificationRequired(destinationPath: env.destinationRoot.path).errorDescription
        XCTAssertNotNil(expected)
        XCTAssertEqual(result.status, "ABORTED")
        XCTAssertEqual(result.abortReason, expected)
        XCTAssertEqual(result.copiedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.destinationRoot.appendingPathComponent("2024").path))
        XCTAssertEqual(try pendingJobCount(env), 3)
        let receipt = try readAuditPayload(in: env.destinationRoot)
        XCTAssertEqual(receipt["status"] as? String, "ABORTED")
        XCTAssertEqual(receipt["abortReason"] as? String, expected)
        XCTAssertEqual(receipt["attempted_jobs"] as? Int, 0)
        XCTAssertTrue(issues.all.contains { $0.severity == .error && $0.message == expected })
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 3
    func testRemoteRunWithVerificationOffAbortsParallelRunBeforeAnyJob() throws {
        let env = try makeEnvironment(jobCount: 3)
        defer { env.close() }
        let executor = makeRemoteExecutor()

        let result = try run(executor, env, verifyCopies: false, maxConcurrentCopies: 3)

        XCTAssertEqual(result.status, "ABORTED")
        XCTAssertEqual(
            result.abortReason,
            NASRemoteCopyError.verificationRequired(destinationPath: env.destinationRoot.path).errorDescription
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.destinationRoot.appendingPathComponent("2024").path))
        XCTAssertEqual(try pendingJobCount(env), 3)
    }

    // MARK: - Atomic no-replace rename (D-NAS-40)

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 4
    func testRemoteExclusiveRenameENOTSUPAbortsRunWithoutPlaceholder() throws {
        let env = try makeEnvironment(jobCount: 3)
        defer { env.close() }
        let renameCalls = Counter()
        var executor = makeRemoteExecutor()
        executor.exclusiveRename = { _, _ in
            renameCalls.increment()
            errno = ENOTSUP
            return -1
        }

        let result = try run(executor, env, verifyCopies: true)

        XCTAssertEqual(result.status, "ABORTED")
        XCTAssertEqual(
            result.abortReason,
            NASRemoteCopyError.atomicNoReplaceUnsupported(destinationPath: env.jobs[0].destinationPath).errorDescription
        )
        XCTAssertEqual(result.copiedCount, 0)
        XCTAssertEqual(renameCalls.value, 1, "later jobs must not be attempted after a run-fatal error")
        let directory = URL(fileURLWithPath: env.jobs[0].destinationPath).deletingLastPathComponent().path
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory),
            [],
            "no placeholder, no final file and no temporary file may remain"
        )
        XCTAssertEqual(try pendingJobCount(env), 3, "the interrupted job and the later jobs stay resumable")
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 4
    func testRemoteRenameNeverOverwritesForeignFinalPath() throws {
        let env = try makeEnvironment(jobCount: 1)
        defer { env.close() }
        let job = env.jobs[0]
        let foreignBytes = Data("foreign bytes created during the race".utf8)
        let raced = Counter()
        var executor = makeRemoteExecutor()
        executor.exclusiveRename = { source, destination in
            if raced.incrementAndGet() == 1 {
                // A foreign writer lands the final name between the collision
                // check and the rename.
                FileManager.default.createFile(atPath: destination, contents: foreignBytes)
            }
            return TransferExecutor.systemExclusiveRename(from: source, to: destination)
        }

        let result = try run(executor, env, verifyCopies: true)

        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(FileManager.default.contents(atPath: job.destinationPath), foreignBytes)
        let directory = URL(fileURLWithPath: job.destinationPath).deletingLastPathComponent()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let collision = try XCTUnwrap(names.first { $0.contains("_collision_") }, "no collision copy in \(names)")
        XCTAssertEqual(
            FileManager.default.contents(atPath: directory.appendingPathComponent(collision).path),
            FileManager.default.contents(atPath: job.sourcePath)
        )
        XCTAssertFalse(names.contains { $0.hasSuffix(".tmp") })
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 4
    func testLocalExclusiveRenameENOTSUPStillUsesPlaceholderFallback() throws {
        let env = try makeEnvironment(jobCount: 2)
        defer { env.close() }
        var executor = TransferExecutor()
        executor.retryPolicy = Self.noRetry
        executor.remotePolicyProvider = { _ in .local }
        executor.exclusiveRename = { _, _ in
            errno = ENOTSUP
            return -1
        }

        let result = try run(executor, env, verifyCopies: true)

        XCTAssertEqual(result.status, "COMPLETED")
        XCTAssertEqual(result.copiedCount, 2)
        for job in env.jobs {
            XCTAssertEqual(
                FileManager.default.contents(atPath: job.destinationPath),
                FileManager.default.contents(atPath: job.sourcePath)
            )
        }
        XCTAssertTrue(temporaryFilesUnder(env.destinationRoot).isEmpty)
    }

    // MARK: - Flush (D-NAS-41)

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 2
    func testRemoteFullFsyncUnsupportedFallsBackToFsync() throws {
        for unsupportedErrno in [ENOTSUP, EINVAL, ENOTTY] {
            let env = try makeEnvironment(jobCount: 1)
            defer { env.close() }
            let plainCalls = Counter()
            var executor = makeRemoteExecutor()
            executor.fullFsync = { _ in
                errno = unsupportedErrno
                return -1
            }
            executor.plainFsync = { _ in
                plainCalls.increment()
                return 0
            }

            let result = try run(executor, env, verifyCopies: true)

            XCTAssertEqual(result.copiedCount, 1, "errno \(unsupportedErrno) should fall back to fsync")
            XCTAssertEqual(plainCalls.value, 1)
            XCTAssertEqual(
                FileManager.default.contents(atPath: env.jobs[0].destinationPath),
                FileManager.default.contents(atPath: env.jobs[0].sourcePath)
            )
        }
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 2
    func testRemoteFsyncFailureFailsCopyAndLeavesNoFinalFile() throws {
        let env = try makeEnvironment(jobCount: 1)
        defer { env.close() }
        var executor = makeRemoteExecutor()
        executor.fullFsync = { _ in
            errno = ENOTSUP
            return -1
        }
        executor.plainFsync = { _ in
            errno = EIO
            return -1
        }

        let result = try run(executor, env, verifyCopies: true)

        XCTAssertEqual(result.copiedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.jobs[0].destinationPath))
        XCTAssertTrue(temporaryFilesUnder(env.destinationRoot).isEmpty)
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 2
    func testRemoteFullFsyncOtherErrorFailsCopy() throws {
        let env = try makeEnvironment(jobCount: 1)
        defer { env.close() }
        let plainCalls = Counter()
        var executor = makeRemoteExecutor()
        executor.fullFsync = { _ in
            errno = EIO
            return -1
        }
        executor.plainFsync = { _ in
            plainCalls.increment()
            return 0
        }

        let result = try run(executor, env, verifyCopies: true)

        XCTAssertEqual(result.copiedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(plainCalls.value, 0, "fsync is only a fallback for unsupported F_FULLFSYNC")
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.jobs[0].destinationPath))
        XCTAssertTrue(temporaryFilesUnder(env.destinationRoot).isEmpty)
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 2
    func testLocalFullFsyncFailureStillThrows() throws {
        let env = try makeEnvironment(jobCount: 1)
        defer { env.close() }
        let plainCalls = Counter()
        var executor = TransferExecutor()
        executor.retryPolicy = Self.noRetry
        executor.remotePolicyProvider = { _ in .local }
        executor.fullFsync = { _ in
            errno = ENOTSUP
            return -1
        }
        executor.plainFsync = { _ in
            plainCalls.increment()
            return 0
        }

        let result = try run(executor, env, verifyCopies: true)

        XCTAssertEqual(result.copiedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(plainCalls.value, 0, "the local flush has no fsync fallback")
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.jobs[0].destinationPath))
    }

    // MARK: - Copy primitives (D-NAS-43)

    // AGENTS-INVARIANT: 28
    func testRemoteMetadataFailureWarnsButCopies() throws {
        let env = try makeEnvironment(jobCount: 1)
        defer { env.close() }
        let metadataCalls = Counter()
        var strategy = TransferFileCopyStrategy.system
        strategy.copyMetadata = { _, _ in
            metadataCalls.increment()
            errno = EPERM
            return -1
        }
        var executor = makeRemoteExecutor(strategy: strategy)
        executor.remotePolicyProvider = { [remote = remotePolicy()] _ in remote }
        let issues = IssueRecorder()

        let result = try run(executor, env, verifyCopies: true, issues: issues)

        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(metadataCalls.value, 1)
        let job = env.jobs[0]
        XCTAssertEqual(FileManager.default.contents(atPath: job.destinationPath), FileManager.default.contents(atPath: job.sourcePath))
        let expected = "Chronoframe copied and verified this file, but the network folder didn't accept some of its Finder metadata (tags, permissions or dates): \(job.destinationPath)"
        XCTAssertTrue(
            issues.all.contains { $0.severity == .warning && $0.message == expected },
            "issues: \(issues.all.map(\.message))"
        )
        XCTAssertTrue(temporaryFilesUnder(env.destinationRoot).isEmpty)
    }

    // AGENTS-INVARIANT: 28
    func testRemoteDataFailureFailsCopy() throws {
        let env = try makeEnvironment(jobCount: 1)
        defer { env.close() }
        let metadataCalls = Counter()
        var strategy = TransferFileCopyStrategy.system
        strategy.copyData = { _, _ in
            errno = EIO
            return -1
        }
        strategy.copyMetadata = { _, _ in
            metadataCalls.increment()
            return 0
        }
        let executor = makeRemoteExecutor(strategy: strategy)

        let result = try run(executor, env, verifyCopies: true)

        XCTAssertEqual(result.copiedCount, 0)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(metadataCalls.value, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.jobs[0].destinationPath))
        XCTAssertTrue(temporaryFilesUnder(env.destinationRoot).isEmpty)
    }

    // AGENTS-INVARIANT: 28
    func testRemoteSkipsClone() throws {
        let remoteEnv = try makeEnvironment(jobCount: 2)
        defer { remoteEnv.close() }
        let cloneCalls = Counter()
        var strategy = TransferFileCopyStrategy.system
        strategy.clone = { _, _ in
            cloneCalls.increment()
            errno = ENOTSUP
            return -1
        }

        let remoteResult = try run(makeRemoteExecutor(strategy: strategy), remoteEnv, verifyCopies: true)

        XCTAssertEqual(remoteResult.copiedCount, 2)
        XCTAssertEqual(cloneCalls.value, 0, "a network copy never calls clonefile")
        for job in remoteEnv.jobs {
            XCTAssertEqual(FileManager.default.contents(atPath: job.destinationPath), FileManager.default.contents(atPath: job.sourcePath))
        }

        // Control: the same strategy on a local policy still tries to clone.
        let localEnv = try makeEnvironment(jobCount: 1)
        defer { localEnv.close() }
        var localExecutor = TransferExecutor(fileCopyStrategy: strategy)
        localExecutor.retryPolicy = Self.noRetry
        localExecutor.remotePolicyProvider = { _ in .local }
        _ = try run(localExecutor, localEnv, verifyCopies: true)
        XCTAssertEqual(cloneCalls.value, 1)
    }

    // MARK: - Volume guard

    // AGENTS-INVARIANT: 28
    func testRemoteVolumeChangeAbortsBeforeNextJob() throws {
        let env = try makeEnvironment(jobCount: 3, distinctDirectories: true)
        defer { env.close() }
        let checks = Counter()
        var executor = makeRemoteExecutor()
        executor.volumeFileSystemID = { _ in
            checks.incrementAndGet() == 1 ? Self.remoteFileSystemID : Self.remoteFileSystemID + 1
        }

        let result = try run(executor, env, verifyCopies: true)

        XCTAssertEqual(result.status, "ABORTED")
        XCTAssertEqual(
            result.abortReason,
            NASRemoteCopyError.destinationVolumeChanged(mountPoint: Self.remoteMountPoint).errorDescription
        )
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: env.jobs[0].destinationPath))
        for job in env.jobs.dropFirst() {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: URL(fileURLWithPath: job.destinationPath).deletingLastPathComponent().path),
                "no directory may be created once the volume has changed: \(job.destinationPath)"
            )
        }
        XCTAssertEqual(checks.value, 2, "the guard stops the run before the third job")
        XCTAssertEqual(try pendingJobCount(env), 2)
    }

    // AGENTS-INVARIANT: 28
    func testRemoteVolumeUnreadableAbortsAsChanged() throws {
        let env = try makeEnvironment(jobCount: 2, distinctDirectories: true)
        defer { env.close() }
        var executor = makeRemoteExecutor()
        executor.volumeFileSystemID = { _ in nil }

        let result = try run(executor, env, verifyCopies: true)

        XCTAssertEqual(result.status, "ABORTED")
        XCTAssertEqual(
            result.abortReason,
            NASRemoteCopyError.destinationVolumeChanged(mountPoint: Self.remoteMountPoint).errorDescription
        )
        XCTAssertEqual(result.copiedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: env.jobs[0].destinationPath).deletingLastPathComponent().path))
    }

    // AGENTS-INVARIANT: 28
    func testRemoteVolumeChangeAbortsParallelRunAndLeavesNoTemporaryFiles() throws {
        let env = try makeEnvironment(jobCount: 4, distinctDirectories: true)
        defer { env.close() }
        let checks = Counter()
        var executor = makeRemoteExecutor()
        executor.volumeFileSystemID = { _ in
            // The first two jobs of the first batch pass; later ones see a different volume.
            checks.incrementAndGet() <= 2 ? Self.remoteFileSystemID : Self.remoteFileSystemID + 1
        }

        let result = try run(executor, env, verifyCopies: true, maxConcurrentCopies: 2)

        XCTAssertEqual(result.status, "ABORTED")
        XCTAssertEqual(
            result.abortReason,
            NASRemoteCopyError.destinationVolumeChanged(mountPoint: Self.remoteMountPoint).errorDescription
        )
        XCTAssertEqual(result.copiedCount, 2)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(temporaryFilesUnder(env.destinationRoot).isEmpty)
    }

    // MARK: - AppleDouble companions

    // AGENTS-INVARIANT: 28
    func testRemoteAppleDoubleFilesCountedInOneInfoIssue() throws {
        let env = try makeEnvironment(jobCount: 3)
        defer { env.close() }
        var executor = makeRemoteExecutor()
        executor.exclusiveRename = { source, destination in
            let result = TransferExecutor.systemExclusiveRename(from: source, to: destination)
            if result == 0, !destination.hasSuffix("photo_2.jpg") {
                let url = URL(fileURLWithPath: destination)
                let companion = url.deletingLastPathComponent().appendingPathComponent("._" + url.lastPathComponent)
                FileManager.default.createFile(atPath: companion.path, contents: Data("appledouble".utf8))
            }
            return result
        }
        let issues = IssueRecorder()

        let result = try run(executor, env, verifyCopies: true, issues: issues)

        XCTAssertEqual(result.copiedCount, 3)
        let infoIssues = issues.all.filter { $0.severity == .info }
        XCTAssertEqual(infoIssues.count, 1)
        XCTAssertEqual(
            infoIssues.first?.message,
            "macOS created 2 hidden ._ metadata files beside copies on the network folder. They aren't photos or videos and aren't counted as copies."
        )
    }

    // AGENTS-INVARIANT: 28
    func testRemoteRunWithoutAppleDoubleFilesEmitsNoInfoIssue() throws {
        let env = try makeEnvironment(jobCount: 2)
        defer { env.close() }
        let issues = IssueRecorder()

        let result = try run(makeRemoteExecutor(), env, verifyCopies: true, issues: issues)

        XCTAssertEqual(result.copiedCount, 2)
        XCTAssertTrue(issues.all.filter { $0.severity == .info }.isEmpty)
    }

    // MARK: - Run-fatal errors

    // AGENTS-INVARIANT: 28
    func testRemoteRunFatalErrorDoesNotCountTowardFailureThresholds() throws {
        let env = try makeEnvironment(jobCount: 3)
        defer { env.close() }
        let renameCalls = Counter()
        var executor = makeRemoteExecutor()
        executor.failureThresholds = FailureThresholds(consecutive: 1, total: 1)
        executor.retryPolicy = RetryPolicy(maxAttempts: 3, minimumBackoffSeconds: 0, maximumBackoffSeconds: 0, nonRetryableErrnos: [])
        executor.exclusiveRename = { _, _ in
            renameCalls.increment()
            errno = ENOTSUP
            return -1
        }
        let issues = IssueRecorder()

        let result = try run(executor, env, verifyCopies: true, issues: issues)

        let expected = NASRemoteCopyError.atomicNoReplaceUnsupported(destinationPath: env.jobs[0].destinationPath).errorDescription
        XCTAssertEqual(result.abortReason, expected)
        XCTAssertFalse(result.abortReason?.hasPrefix("Aborting:") ?? true, "the failure-threshold abort must not have fired")
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(renameCalls.value, 1, "a run-fatal error is not retried")
        XCTAssertFalse(issues.all.contains { $0.message.hasPrefix("Aborting:") })
        let receipt = try readAuditPayload(in: env.destinationRoot)
        XCTAssertEqual(receipt["failed_jobs"] as? Int, 0)
        XCTAssertEqual(receipt["abortReason"] as? String, expected)
    }

    // AGENTS-INVARIANT: 28
    func testRemoteRunFatalErrorAbortsParallelRunAndRemovesPreparedCopies() throws {
        let env = try makeEnvironment(jobCount: 3)
        defer { env.close() }
        var executor = makeRemoteExecutor()
        executor.failureThresholds = FailureThresholds(consecutive: 1, total: 1)
        executor.exclusiveRename = { _, _ in
            errno = ENOTSUP
            return -1
        }

        let result = try run(executor, env, verifyCopies: true, maxConcurrentCopies: 3)

        XCTAssertEqual(
            result.abortReason,
            NASRemoteCopyError.atomicNoReplaceUnsupported(destinationPath: env.jobs[0].destinationPath).errorDescription
        )
        XCTAssertEqual(result.copiedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        let directory = URL(fileURLWithPath: env.jobs[0].destinationPath).deletingLastPathComponent().path
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory), [])
    }

    // MARK: - Helpers

    private func remotePolicy() -> NASRemoteCopyPolicy {
        NASRemoteCopyPolicy(
            isRemote: true,
            volume: NASVolumeObservation(
                kind: .remote,
                fileSystemType: "smbfs",
                mountPoint: Self.remoteMountPoint,
                serverHost: "nas.local",
                shareName: "Photos",
                fileSystemID: Self.remoteFileSystemID,
                observedPath: Self.remoteMountPoint
            )
        )
    }

    private func makeRemoteExecutor(strategy: TransferFileCopyStrategy = .system) -> TransferExecutor {
        var executor = TransferExecutor(fileCopyStrategy: strategy)
        executor.retryPolicy = Self.noRetry
        let policy = remotePolicy()
        executor.remotePolicyProvider = { _ in policy }
        executor.volumeFileSystemID = { _ in Self.remoteFileSystemID }
        return executor
    }

    private func run(
        _ executor: TransferExecutor,
        _ env: Environment,
        verifyCopies: Bool,
        maxConcurrentCopies: Int = 1,
        issues: IssueRecorder = IssueRecorder()
    ) throws -> TransferExecutionResult {
        try executor.executeQueuedJobs(
            database: env.database,
            destinationRoot: env.destinationRoot,
            verifyCopies: verifyCopies,
            runLogger: env.logger,
            maxConcurrentCopies: maxConcurrentCopies,
            observer: TransferExecutionObserver(onIssue: { issues.record($0) }),
            runID: UUID()
        )
    }

    private func makeEnvironment(jobCount: Int, distinctDirectories: Bool = false) throws -> Environment {
        let testRoot = temporaryDirectoryURL.appendingPathComponent("env-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = testRoot.appendingPathComponent("source", isDirectory: true)
        let destinationRoot = testRoot.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let database = try OrganizerDatabase(url: destinationRoot.appendingPathComponent(".organize_cache.db"))
        var jobs: [QueuedCopyJob] = []
        for index in 0..<jobCount {
            let sourceURL = sourceRoot.appendingPathComponent("photo_\(index).jpg")
            try Data(String(repeating: "abc-\(index)-", count: 64 * (index + 1)).utf8).write(to: sourceURL)
            let hash = try FileIdentityHasher().hashIdentity(at: sourceURL).rawValue
            let destinationURL = distinctDirectories
                ? destinationRoot.appendingPathComponent("2024/01/dir_\(index)/photo_\(index).jpg")
                : destinationRoot.appendingPathComponent("2024/01/01/photo_\(index).jpg")
            jobs.append(QueuedCopyJob(
                sourcePath: sourceURL.path,
                destinationPath: destinationURL.path,
                hash: hash,
                status: .pending
            ))
        }
        try database.enqueueQueuedJobs(jobs)

        let logger = PersistentRunLogger(logURL: destinationRoot.appendingPathComponent(".organize_log.txt"))
        try logger.open()
        return Environment(destinationRoot: destinationRoot, database: database, logger: logger, jobs: jobs)
    }

    private func pendingJobCount(_ env: Environment) throws -> Int {
        try env.database.loadQueuedJobs(orderByInsertion: true).filter { $0.status == .pending }.count
    }

    private func readAuditPayload(in destinationRoot: URL) throws -> [String: Any] {
        let logsDirectory = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        let receiptURL = try FileManager.default
            .contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("audit_receipt_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .last
        let url = try XCTUnwrap(receiptURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func temporaryFilesUnder(_ root: URL) -> [String] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var files: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent.hasSuffix(".tmp") {
                files.append(url.path)
            }
        }
        return files.sorted()
    }

    private struct Environment {
        let destinationRoot: URL
        let database: OrganizerDatabase
        let logger: PersistentRunLogger
        let jobs: [QueuedCopyJob]

        func close() {
            database.close()
            logger.close()
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func incrementAndGet() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

private final class IssueRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var issues: [RunIssue] = []

    var all: [RunIssue] {
        lock.lock()
        defer { lock.unlock() }
        return issues
    }

    func record(_ issue: RunIssue) {
        lock.lock()
        issues.append(issue)
        lock.unlock()
    }
}
