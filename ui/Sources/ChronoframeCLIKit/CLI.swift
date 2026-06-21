import ChronoframeAppCore
import ChronoframeCore
import Foundation

public enum CLIError: LocalizedError, Equatable {
    case usage(String)
    case help(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .usage(message):
            return message
        case let .help(message):
            return message
        case .cancelled:
            return "Cancelled."
        }
    }
}

public struct CLIOptions: Equatable, Sendable {
    public static let defaultWorkerCount = 8

    public var sourcePath: String?
    public var destinationPath: String?
    public var profileName: String?
    public var dryRun: Bool
    public var rebuildCache: Bool
    public var verifyCopies: Bool
    public var workerCount: Int
    public var assumeYes: Bool
    public var jsonOutput: Bool
    public var folderStructure: FolderStructure
    public var revertReceiptPath: String?
    public var startFresh: Bool

    public init(
        sourcePath: String? = nil,
        destinationPath: String? = nil,
        profileName: String? = nil,
        dryRun: Bool = false,
        rebuildCache: Bool = false,
        verifyCopies: Bool = true,
        workerCount: Int = CLIOptions.defaultWorkerCount,
        assumeYes: Bool = false,
        jsonOutput: Bool = false,
        folderStructure: FolderStructure = .default,
        revertReceiptPath: String? = nil,
        startFresh: Bool = false
    ) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.profileName = profileName
        self.dryRun = dryRun
        self.rebuildCache = rebuildCache
        self.verifyCopies = verifyCopies
        self.workerCount = workerCount
        self.assumeYes = assumeYes
        self.jsonOutput = jsonOutput
        self.folderStructure = folderStructure
        self.revertReceiptPath = revertReceiptPath
        self.startFresh = startFresh
    }

    public var mode: RunMode {
        revertReceiptPath == nil ? (dryRun ? .preview : .transfer) : .revert
    }

    public func runConfiguration() -> RunConfiguration {
        RunConfiguration(
            mode: mode,
            sourcePath: sourcePath ?? "",
            destinationPath: destinationPath ?? "",
            profileName: profileName,
            verifyCopies: verifyCopies,
            parallelTransferEnabled: true,
            workerCount: workerCount,
            folderStructure: folderStructure
        )
    }
}

public enum CLIParser {
    public static let usage = """
    Usage:
      chronoframe --source PATH --dest PATH [--dry-run] [options]
      chronoframe --profile NAME [--dry-run] [options]
      chronoframe --revert RECEIPT_JSON [--dest DEST_ROOT] [--json]

    Options:
      --source PATH
      --dest PATH
      --profile NAME
      --dry-run
      --rebuild-cache
      --skip-verify
      --workers N
      -y, --yes
      --json
      --folder-structure YYYY/MM/DD|YYYY/MM|YYYY|YYYY/Mon/Event|Flat
      --revert RECEIPT_JSON
      --start-fresh
      -h, --help
    """

    /// Recognised flag names. `requireValue` consults this to tell
    /// "user supplied a value that starts with `-`" (legitimate — paths
    /// like `/Volumes/-Backup` exist) apart from "user forgot the value
    /// and the parser would otherwise consume the next flag as a path".
    private static let knownFlags: Set<String> = [
        "-h", "--help",
        "--source", "--dest", "--profile",
        "--dry-run", "--rebuild-cache", "--skip-verify",
        "--workers", "-y", "--yes",
        "--json",
        "--folder-structure",
        "--revert",
        "--start-fresh",
    ]

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var index = 0

        func requireValue(after flag: String) throws -> String {
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw CLIError.usage("Missing value for \(flag).")
            }
            let value = arguments[valueIndex]
            // Reject only when the next arg is itself a known flag — paths
            // and identifiers that legitimately start with `-` (for example
            // `/Volumes/-Backup` or a receipt path the user named with a
            // leading dash) are accepted as values verbatim.
            if knownFlags.contains(value) {
                throw CLIError.usage("Missing value for \(flag); got \(value).")
            }
            index = valueIndex
            return value
        }

        while index < arguments.count {
            let argument = arguments[index]

            // Support `--flag=value` form so values containing arbitrary
            // characters (including a leading `-`) can be passed
            // unambiguously.
            if argument.hasPrefix("--"), let eq = argument.firstIndex(of: "=") {
                let flagName = String(argument[..<eq])
                let value = String(argument[argument.index(after: eq)...])
                try applyInlineValue(flagName: flagName, value: value, into: &options)
                index += 1
                continue
            }

            switch argument {
            case "-h", "--help":
                throw CLIError.help(usage)
            case "--source":
                options.sourcePath = try requireValue(after: argument)
            case "--dest":
                options.destinationPath = try requireValue(after: argument)
            case "--profile":
                options.profileName = try requireValue(after: argument)
            case "--dry-run":
                options.dryRun = true
            case "--rebuild-cache":
                options.rebuildCache = true
            case "--skip-verify":
                options.verifyCopies = false
            case "--workers":
                let rawValue = try requireValue(after: argument)
                guard let workerCount = Int(rawValue) else {
                    throw CLIError.usage("--workers must be an integer.")
                }
                options.workerCount = workerCount
            case "-y", "--yes":
                options.assumeYes = true
            case "--json":
                options.jsonOutput = true
            case "--folder-structure":
                let rawValue = try requireValue(after: argument)
                guard let folderStructure = FolderStructure(rawValue: rawValue) else {
                    throw CLIError.usage("Unsupported folder structure: \(rawValue).")
                }
                options.folderStructure = folderStructure
            case "--revert":
                options.revertReceiptPath = try requireValue(after: argument)
            case "--start-fresh":
                options.startFresh = true
            default:
                throw CLIError.usage("Unknown option: \(argument).")
            }

            index += 1
        }

        normalizePaths(&options)
        try validate(options)
        return options
    }

    /// Applies tilde expansion and Unicode NFC normalization to every
    /// path option after parsing. Scripts launched outside a shell
    /// (`launchd`, the Codex environment) pass `~/Photos` verbatim
    /// rather than the expanded path; APFS returns NFD-decomposed
    /// filenames while CLI consumers commonly pass NFC — both cases
    /// produce silently-wrong destinations without normalization.
    private static func normalizePaths(_ options: inout CLIOptions) {
        options.sourcePath = options.sourcePath.map(normalizedPath)
        options.destinationPath = options.destinationPath.map(normalizedPath)
        options.revertReceiptPath = options.revertReceiptPath.map(normalizedPath)
    }

    private static func normalizedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return expanded.precomposedStringWithCanonicalMapping
    }

    /// Routes a `--flag=value` parse step through the same option-
    /// assignment path the bare `--flag value` form uses. Throws
    /// `CLIError.usage` for flags that don't take a value.
    private static func applyInlineValue(
        flagName: String,
        value: String,
        into options: inout CLIOptions
    ) throws {
        switch flagName {
        case "--source": options.sourcePath = value
        case "--dest": options.destinationPath = value
        case "--profile": options.profileName = value
        case "--workers":
            guard let workerCount = Int(value) else {
                throw CLIError.usage("--workers must be an integer.")
            }
            options.workerCount = workerCount
        case "--folder-structure":
            guard let folderStructure = FolderStructure(rawValue: value) else {
                throw CLIError.usage("Unsupported folder structure: \(value).")
            }
            options.folderStructure = folderStructure
        case "--revert": options.revertReceiptPath = value
        case "-h", "--help", "--dry-run", "--rebuild-cache", "--skip-verify",
             "-y", "--yes", "--json", "--start-fresh":
            throw CLIError.usage("\(flagName) does not take a value.")
        default:
            throw CLIError.usage("Unknown option: \(flagName).")
        }
    }

    private static func validate(_ options: CLIOptions) throws {
        let maxWorkers = max(CLIOptions.defaultWorkerCount, ProcessInfo.processInfo.processorCount * 2)
        guard (1...maxWorkers).contains(options.workerCount) else {
            throw CLIError.usage("--workers must be between 1 and \(maxWorkers) (got \(options.workerCount)).")
        }

        if options.revertReceiptPath != nil {
            // Positive whitelist: `--revert` is compatible only with the
            // explicitly-listed flags. The previous deny-list missed
            // `--skip-verify` and `--folder-structure`, which the revert
            // path silently ignored.
            var rejected: [String] = []
            if options.sourcePath != nil { rejected.append("--source") }
            if options.profileName != nil { rejected.append("--profile") }
            if options.dryRun { rejected.append("--dry-run") }
            if options.rebuildCache { rejected.append("--rebuild-cache") }
            if options.startFresh { rejected.append("--start-fresh") }
            if !options.verifyCopies { rejected.append("--skip-verify") }
            if options.folderStructure != .default { rejected.append("--folder-structure") }
            if !rejected.isEmpty {
                throw CLIError.usage(
                    "--revert can be combined only with --dest, --json, --workers, and --yes. "
                        + "Incompatible flag(s): \(rejected.joined(separator: ", "))."
                )
            }
            return
        }

        if let profileName = options.profileName, !profileName.isEmpty {
            return
        }

        guard let source = options.sourcePath, !source.isEmpty else {
            throw CLIError.usage("Provide --source and --dest, or use --profile.")
        }
        guard let destination = options.destinationPath, !destination.isEmpty else {
            throw CLIError.usage("Provide --dest, or use --profile.")
        }
    }
}

public struct ChronoframeCLI {
    public typealias Output = @Sendable (String) -> Void
    public typealias Input = () -> String?

    @MainActor
    public static func run(
        arguments: [String],
        output: Output = { print($0) },
        input: Input = { readLine() }
    ) async -> Int32 {
        // Detect `--json` before parsing so error output can be formatted
        // as a JSON line in every failure mode (including parse errors
        // for malformed argv). Pipeline consumers in --json mode used to
        // receive free-form English on stdout, corrupting the parse.
        let jsonRequested = arguments.contains("--json")
        do {
            let options = try CLIParser.parse(arguments)
            let terminalStatus = try await run(options: options, output: output, input: input)
            // Finding #4: the exit code must reflect the run's terminal status.
            // A run that completed without throwing can still be incomplete —
            // failed/skipped copies or unreadable sources are surfaced as
            // `.failed` — and automation must be able to detect that. Any other
            // terminal status (or a command that streamed no run) is a success.
            return terminalStatus == .failed ? 1 : 0
        } catch let error as CLIError {
            if case .help = error {
                // --help intentionally bypasses JSON formatting: the help
                // text is meant for humans and is rendered through the
                // same channel either way.
                output(error.localizedDescription)
                return 0
            }
            // PHASE2_FINDINGS.md NEW22 — `.cancelled` deserves its own
            // exit code so callers can tell "user said no at the prompt"
            // apart from "argument parse failed". Both used to return 2.
            if case .cancelled = error {
                if jsonRequested {
                    output(JSONLineEmitter.errorLine(kind: "cancelled", message: error.localizedDescription))
                } else {
                    output(error.localizedDescription)
                }
                return 3
            }
            if jsonRequested {
                output(JSONLineEmitter.errorLine(kind: "usage", message: error.localizedDescription))
            } else {
                output(error.localizedDescription)
            }
            return 2
        } catch {
            let message = UserFacingErrorMessage.message(for: error)
            if jsonRequested {
                output(JSONLineEmitter.errorLine(kind: "operational", message: message))
            } else {
                output(message)
            }
            return 1
        }
    }

    @MainActor
    /// Runs the requested command and returns the run's terminal `RunStatus`
    /// (or `nil` for commands that don't stream a run, e.g. cache rebuild).
    /// Finding #4: the public `run(arguments:)` entry point turns this into the
    /// process exit code.
    @discardableResult
    public static func run(
        options: CLIOptions,
        output: Output = { print($0) },
        input: Input = { readLine() }
    ) async throws -> RunStatus? {
        if let receiptPath = options.revertReceiptPath {
            return try await runRevert(options: options, receiptPath: receiptPath, output: output)
        }

        let profilesRepository = ProfilesRepository()
        if options.rebuildCache {
            let destination = try destinationForCacheRebuild(options: options, profilesRepository: profilesRepository)
            try clearHashCache(destinationRoot: destination)
            if !options.jsonOutput {
                output("Rebuilt hash cache for \(destination).")
            }
        }

        let engine = SwiftOrganizerEngine(profilesRepository: profilesRepository)
        let configuration = options.runConfiguration()
        let preflight = try await engine.preflight(configuration)
        let stream: AsyncThrowingStream<RunEvent, Error>

        if configuration.mode == .transfer {
            let resumePendingJobs = try transferDecision(
                options: options,
                preflight: preflight,
                output: output,
                input: input
            )
            if options.startFresh || (!resumePendingJobs && preflight.pendingJobCount > 0) {
                try clearCopyJobs(destinationRoot: preflight.resolvedDestinationPath)
            }
            stream = try resumePendingJobs
                ? engine.resume(preflight.configuration)
                : engine.start(preflight.configuration)
        } else {
            stream = try engine.start(preflight.configuration)
        }

        return try await consume(stream: stream, jsonOutput: options.jsonOutput, output: output)
    }

    private static func transferDecision(
        options: CLIOptions,
        preflight: RunPreflight,
        output: Output,
        input: Input
    ) throws -> Bool {
        if options.startFresh {
            return false
        }

        // JSON-output mode must not block on interactive prompts. The
        // remaining branches in this function would write a human-language
        // prompt string to `output` (the same stdout channel JSON events
        // use) and then block on `input()` waiting for a `readLine()`.
        // A pipeline consumer like Codex or `jq -c .` would receive a
        // non-JSON line mid-stream (corrupting the parse) and the CLI
        // would hang indefinitely on stdin. Fail fast with a usage error
        // when `--json` is set without `--yes`.
        if options.jsonOutput && !options.assumeYes {
            throw CLIError.usage(
                "--json requires --yes; interactive prompts would otherwise corrupt the JSON output stream."
            )
        }

        if preflight.pendingJobCount > 0 {
            if options.assumeYes {
                return true
            }
            output("Found \(preflight.pendingJobCount) pending copy jobs. Resume them? [Y/n/fresh]")
            let answer = input()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            switch answer {
            case "", "y", "yes":
                return true
            case "fresh", "f", "start-fresh":
                return false
            default:
                throw CLIError.cancelled
            }
        }

        if !options.assumeYes {
            output("Chronoframe will leave the source untouched and transfer into \(preflight.resolvedDestinationPath). Continue? [y/N]")
            let answer = input()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                throw CLIError.cancelled
            }
        }
        return false
    }

    @MainActor
    private static func runRevert(options: CLIOptions, receiptPath: String, output: Output) async throws -> RunStatus? {
        let receiptURL = URL(fileURLWithPath: receiptPath)
        let destinationRoot = options.destinationPath ?? destinationBoundary(for: receiptURL)
        let engine = SwiftOrganizerEngine()
        let stream = try engine.revert(receiptURL: receiptURL, destinationRoot: destinationRoot)
        return try await consume(stream: stream, jsonOutput: options.jsonOutput, output: output)
    }

    /// Streams events to `output` and returns the run's terminal status (from
    /// the final `.complete` event), or `nil` if the stream produced none.
    /// Finding #4: the caller maps this to the process exit code so automation
    /// can tell a genuine success from a partial/failed run.
    @discardableResult
    private static func consume(
        stream: AsyncThrowingStream<RunEvent, Error>,
        jsonOutput: Bool,
        output: Output
    ) async throws -> RunStatus? {
        var terminalStatus: RunStatus?
        for try await event in stream {
            if case let .complete(summary) = event {
                terminalStatus = summary.status
            }
            if jsonOutput {
                output(try JSONLineEmitter.line(for: event))
            } else if let line = HumanLineEmitter.line(for: event) {
                output(line)
            }
        }
        return terminalStatus
    }

    private static func destinationForCacheRebuild(
        options: CLIOptions,
        profilesRepository: ProfilesRepository
    ) throws -> String {
        if let destination = options.destinationPath, !destination.isEmpty {
            return destination
        }

        guard let profileName = options.profileName, !profileName.isEmpty else {
            throw CLIError.usage("--rebuild-cache requires --dest or --profile.")
        }
        guard let profile = try profilesRepository.loadProfiles().first(where: { $0.name == profileName }) else {
            throw OrganizerEngineError.profileNotFound(profileName)
        }
        return profile.destinationPath
    }

    private static func clearHashCache(destinationRoot: String) throws {
        let databaseURL = URL(fileURLWithPath: destinationRoot, isDirectory: true)
            .appendingPathComponent(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename)
        let database = try OrganizerDatabase(url: databaseURL)
        defer { database.close() }
        try database.clearCache()
    }

    private static func clearCopyJobs(destinationRoot: String) throws {
        let databaseURL = URL(fileURLWithPath: destinationRoot, isDirectory: true)
            .appendingPathComponent(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
        let database = try OrganizerDatabase(url: databaseURL)
        defer { database.close() }
        try database.clearAllJobs()
    }

    private static func destinationBoundary(for receiptURL: URL) -> String {
        let directory = receiptURL.deletingLastPathComponent()
        if directory.lastPathComponent == EngineArtifactLayout.chronoframeDefault.logsDirectoryName {
            return directory.deletingLastPathComponent().path
        }
        return directory.path
    }
}
