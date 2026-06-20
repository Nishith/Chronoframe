import ChronoframeCore
import Foundation

// MARK: - ChronoframeVideoCalibrationTool
//
// Offline, local-only harness (Milestone 2c) to choose the perceptual-video
// thresholds from a labeled corpus rather than intuition. It extracts features
// for every video in an external manifest, runs the pure matcher, and prints
// precision/recall/purity/throughput/stability plus a threshold-sensitivity
// sweep. NOT a CI dependency — see docs/video-dedupe-calibration-rubric.md.
//
//   swift run --package-path ui ChronoframeVideoCalibrationTool \
//       --manifest /corpus/manifest.json [--duration-tolerance 1.0] \
//       [--frame-hamming 8] [--median 6] [--aspect-tolerance 0.10] \
//       [--low-variance 12.0] [--output-json /path/to/report.json]

func failHard(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Argument parsing

let arguments = Array(CommandLine.arguments.dropFirst())
@MainActor func value(for flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

guard let manifestPath = value(for: "--manifest") else {
    failHard("missing required --manifest <path>. See docs/video-dedupe-calibration-rubric.md")
}

let matchConfig = VideoPerceptualMatchConfiguration(
    durationToleranceSeconds: value(for: "--duration-tolerance").flatMap(Double.init) ?? 1.0,
    frameHammingThreshold: value(for: "--frame-hamming").flatMap(Int.init) ?? 8,
    aggregateMedianThreshold: value(for: "--median").flatMap(Int.init) ?? 6,
    aspectRatioTolerance: value(for: "--aspect-tolerance").flatMap(Double.init) ?? 0.10
)
let extractionConfig = VideoFeatureExtractionConfiguration(
    lowVarianceThreshold: value(for: "--low-variance").flatMap(Double.init) ?? 12.0,
    frameTimeToleranceSeconds: value(for: "--frame-tolerance").flatMap(Double.init) ?? 0.25
)
let jsonOutputPath = value(for: "--output-json")

let manifest: CalibrationManifest
do {
    manifest = try CalibrationManifest.load(from: manifestPath)
} catch {
    failHard("could not load manifest at \(manifestPath): \(error.localizedDescription)")
}
guard !manifest.items.isEmpty else { failHard("manifest contains no items") }

// MARK: - Feature extraction (cold)

let extractor = AVFoundationVideoFeatureExtractor(configuration: extractionConfig)

@MainActor func extractAll() -> (features: [String: VideoPerceptualFeatures], seconds: Double) {
    let started = Date()
    var features: [String: VideoPerceptualFeatures] = [:]
    for item in manifest.items {
        var size: Int64 = 0
        var mtime: TimeInterval = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: item.path) {
            size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        }
        features[item.path] = extractor.extractFeatures(
            path: item.path,
            size: size,
            modificationTime: mtime,
            folderRoot: nil,
            isCancelled: { false }
        )
    }
    return (features, Date().timeIntervalSince(started))
}

let cold = extractAll()
let features = cold.features

// MARK: - Status breakdown

var statusCounts: [VideoDecodeStatus: Int] = [:]
for value in features.values { statusCounts[value.status, default: 0] += 1 }

@MainActor func cluster(with config: VideoPerceptualMatchConfiguration) -> [DuplicateCluster] {
    VideoPerceptualMatcher.cluster(features: Array(features.values), configuration: config)
}

let clusters = cluster(with: matchConfig)
let predictedByPath = CalibrationMetrics.predictedClusterByPath(clusters)

// MARK: - Metrics

let pairScore = CalibrationMetrics.pairScore(manifest: manifest, predictedClusterByPath: predictedByPath)
let candidateRecall = CalibrationMetrics.candidateIndexRecall(
    manifest: manifest, features: features, configuration: matchConfig
)
let purity = CalibrationMetrics.clusterPurity(manifest: manifest, clusters: clusters)
let perClass = CalibrationMetrics.perClassRecall(manifest: manifest, predictedClusterByPath: predictedByPath)
let throughput = cold.seconds > 0 ? Double(manifest.items.count) / cold.seconds : 0

// Warm-vs-cold rescan stability (extraction + clustering determinism).
let warm = extractAll()
let warmClusters = VideoPerceptualMatcher.cluster(features: Array(warm.features.values), configuration: matchConfig)
let stable = CalibrationMetrics.normalizedSignature(clusters) == CalibrationMetrics.normalizedSignature(warmClusters)
let residentBytes = residentMemoryBytes()

if let jsonOutputPath {
    let configurationReport: [String: Any] = [
        "durationToleranceSeconds": matchConfig.durationToleranceSeconds,
        "frameHammingThreshold": matchConfig.frameHammingThreshold,
        "aggregateMedianThreshold": matchConfig.aggregateMedianThreshold,
        "aspectRatioTolerance": matchConfig.aspectRatioTolerance,
        "lowVarianceThreshold": extractionConfig.lowVarianceThreshold,
        "analyzerVersion": VideoPerceptualAnalysis.analyzerVersion,
        "sampleStrategyVersion": VideoPerceptualAnalysis.sampleStrategyVersion,
    ]
    let metricsReport: [String: Any] = [
        "candidateIndexRecall": candidateRecall,
        "pairPrecision": pairScore.precision,
        "pairRecall": pairScore.recall,
        "hardNegativeFalsePositiveRate": pairScore.hardNegativeFalsePositiveRate,
        "clusterPurity": purity,
        "predictedClusterCount": clusters.count,
        "coldThroughputVideosPerSecond": throughput,
        "residentMemoryBytes": residentBytes,
        "warmColdStable": stable,
    ]
    let report: [String: Any] = [
        "generatedAt": ISO8601DateFormatter().string(from: Date()),
        "manifest": manifestPath,
        "itemCount": manifest.items.count,
        "configuration": configurationReport,
        "metrics": metricsReport,
        "decodeStatus": Dictionary(uniqueKeysWithValues: statusCounts.map { ($0.key.rawValue, $0.value) }),
    ]
    do {
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: jsonOutputPath), options: .atomic)
    } catch {
        failHard("could not write JSON report at \(jsonOutputPath): \(error.localizedDescription)")
    }
}

// MARK: - Report

func pct(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }

print("ChronoframeVideoCalibrationTool")
print("================================")
print("manifest:                  \(manifestPath)")
print("items:                     \(manifest.items.count)")
print("operating point:           T=\(matchConfig.durationToleranceSeconds)s  H=\(matchConfig.frameHammingThreshold)  A=\(matchConfig.aggregateMedianThreshold)  aspectTol=\(matchConfig.aspectRatioTolerance)")
print("low-variance threshold:    \(extractionConfig.lowVarianceThreshold)")
print("")
print("Decode status:")
for status in [VideoDecodeStatus.ready, .unsupported, .decodeFailed, .insufficientVisualEvidence] {
    let label = status.rawValue.padding(toLength: 28, withPad: " ", startingAt: 0)
    print("  \(label)\(statusCounts[status] ?? 0)")
}
print("")
print("Match quality:")
print("  candidate-index recall:  \(pct(candidateRecall))   (prune ceiling)")
print("  pair precision:          \(pct(pairScore.precision))")
print("  pair recall:             \(pct(pairScore.recall))")
print("  hard-negative FP rate:   \(pct(pairScore.hardNegativeFalsePositiveRate))")
print("  cluster purity:          \(pct(purity))")
print("  predicted clusters:      \(clusters.count)")
print("")
if !perClass.isEmpty {
    print("Per-class recall (pairs touching the class):")
    for entry in perClass {
        let label = entry.className.padding(toLength: 24, withPad: " ", startingAt: 0)
        print("  \(label)\(pct(entry.recall))  (n=\(entry.support))")
    }
    print("")
}
print("Performance:")
print(String(format: "  throughput:              %.2f videos/sec (cold)", throughput))
print(String(format: "  resident memory:         %@", formatBytes(residentBytes)))
print("  warm-vs-cold stable:     \(stable ? "yes" : "NO — nondeterministic!")")
if let jsonOutputPath { print("  JSON report:             \(jsonOutputPath)") }
print("")

// MARK: - Threshold sensitivity sweep

print("Threshold sensitivity (precision / recall / hard-neg FP):")
print("  H \\ A   " + sweepValues(around: matchConfig.aggregateMedianThreshold).map { String(format: "A=%-2d", $0) }.joined(separator: "        "))
for h in sweepValues(around: matchConfig.frameHammingThreshold) {
    var row = String(format: "  H=%-2d  ", h)
    for a in sweepValues(around: matchConfig.aggregateMedianThreshold) {
        var swept = matchConfig
        swept.frameHammingThreshold = h
        swept.aggregateMedianThreshold = a
        let sweptClusters = cluster(with: swept)
        let score = CalibrationMetrics.pairScore(
            manifest: manifest,
            predictedClusterByPath: CalibrationMetrics.predictedClusterByPath(sweptClusters)
        )
        row += String(format: "%3.0f/%3.0f/%-3.0f  ", score.precision * 100, score.recall * 100, score.hardNegativeFalsePositiveRate * 100)
    }
    print(row)
}
print("")
print("Reminder: perceptual video stays review-only (medium-capped, never")
print("auto-selected). Calibration only tunes which clusters are surfaced.")

// MARK: - Helpers

/// Five values centered on `center`, clamped at 0, for the sweep grid.
func sweepValues(around center: Int) -> [Int] {
    [center - 2, center - 1, center, center + 1, center + 2].filter { $0 >= 0 }
}

func residentMemoryBytes() -> UInt64 {
    var info = proc_taskinfo()
    let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, pointer, expectedSize)
    }
    return result == expectedSize ? info.pti_resident_size : 0
}

func formatBytes(_ bytes: UInt64) -> String {
    guard bytes > 0 else { return "n/a" }
    let mb = Double(bytes) / (1024 * 1024)
    return String(format: "%.1f MB", mb)
}
