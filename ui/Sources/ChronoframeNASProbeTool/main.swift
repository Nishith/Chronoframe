import ChronoframeCore
import Foundation

// MARK: - ChronoframeNASProbeTool
//
// Local only; real-share qualification evidence. Not run in CI.
//
//   ChronoframeNASProbeTool probe --test-dir PATH [--trash]
//   ChronoframeNASProbeTool assess-parity --root PATH --state-dir PATH
//   ChronoframeNASProbeTool make-corpus --dest PATH --manifest PATH \
//       --files N --duplicate-percent P --seed S
//
// Each command prints one JSON document to stdout and a human summary to
// stderr. The probe writes only inside the test folder it is given and
// removes everything it created. Never point it at a folder of real media.

func say(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func failHard(_ message: String, code: Int32 = 1) -> Never {
    say("error: \(message)")
    exit(code)
}

func option(_ flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func requiredOption(_ flag: String, in arguments: [String]) -> String {
    guard let value = option(flag, in: arguments) else { failHard("missing required \(flag) <value>") }
    return value
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    do {
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        failHard("could not encode the result: \(error.localizedDescription)")
    }
}

func runProbe(_ arguments: [String]) {
    let testDirectory = URL(fileURLWithPath: requiredOption("--test-dir", in: arguments))
    let includeTrash = arguments.contains("--trash")
    do {
        let results = try NASProbe().run(testDirectory: testDirectory, includeTrash: includeTrash)
        for result in results {
            say("\(result.id) \(result.status.rawValue): \(result.detail)")
        }
        printJSON(NASProbeReport(generatedAt: Date(), testDirectory: testDirectory.path, results: results))
        if results.contains(where: { $0.id == "CLEANUP" }) {
            failHard("the probe could not remove everything it created; see the CLEANUP result", code: 3)
        }
    } catch {
        failHard(error.localizedDescription)
    }
}

func runParity(_ arguments: [String]) async {
    let root = URL(fileURLWithPath: requiredOption("--root", in: arguments))
    let stateDirectory = URL(fileURLWithPath: requiredOption("--state-dir", in: arguments))
    do {
        let report = try await NASParityCheck().run(rootURL: root, stateDirectory: stateDirectory)
        say("parity=\(report.parity) groups=\(report.scannerGroupCount)/\(report.exhaustiveGroupCount) withinBudget=\(report.withinBudget) wallSeconds=\(report.wallSeconds)")
        for line in report.differences { say("difference: \(line)") }
        printJSON(report)
        if !report.parity { exit(2) }
    } catch {
        failHard(error.localizedDescription)
    }
}

func runMakeCorpus(_ arguments: [String]) {
    let destination = URL(fileURLWithPath: requiredOption("--dest", in: arguments))
    let manifestURL = URL(fileURLWithPath: requiredOption("--manifest", in: arguments))
    guard let files = Int(requiredOption("--files", in: arguments)) else { failHard("--files must be a whole number") }
    guard let percent = Int(requiredOption("--duplicate-percent", in: arguments)) else { failHard("--duplicate-percent must be a whole number") }
    guard let seed = UInt64(requiredOption("--seed", in: arguments)) else { failHard("--seed must be a non-negative whole number") }
    do {
        let manifest = try NASCorpusGenerator.generate(
            destination: destination,
            manifestURL: manifestURL,
            fileCount: files,
            duplicatePercent: percent,
            seed: seed
        )
        let totalBytes = manifest.files.reduce(Int64(0)) { $0 + $1.size }
        say("wrote \(manifest.files.count) files (\(totalBytes) bytes), \(manifest.expectedGroups.count) expected groups; manifest: \(manifestURL.path)")
        printJSON(CorpusSummary(
            fileCount: manifest.files.count,
            totalBytes: totalBytes,
            expectedGroupCount: manifest.expectedGroups.count,
            seed: seed,
            manifestPath: manifestURL.path
        ))
    } catch {
        failHard(error.localizedDescription)
    }
}

struct CorpusSummary: Encodable {
    var fileCount: Int
    var totalBytes: Int64
    var expectedGroupCount: Int
    var seed: UInt64
    var manifestPath: String
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "probe":
    runProbe(arguments)
case "assess-parity":
    await runParity(arguments)
case "make-corpus":
    runMakeCorpus(arguments)
default:
    failHard("usage: ChronoframeNASProbeTool probe|assess-parity|make-corpus ... (see the header of main.swift)", code: 64)
}
