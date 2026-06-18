import ChronoframeCore
import Foundation

/// Pure metric computations over extracted features + ground-truth labels.
/// Deterministic given its inputs so the harness's numbers are reproducible.
enum CalibrationMetrics {

    struct PairScore {
        var truePositives = 0
        var falsePositives = 0
        var falseNegatives = 0
        var trueNegatives = 0

        var precision: Double {
            let denominator = truePositives + falsePositives
            return denominator == 0 ? 1 : Double(truePositives) / Double(denominator)
        }
        var recall: Double {
            let denominator = truePositives + falseNegatives
            return denominator == 0 ? 1 : Double(truePositives) / Double(denominator)
        }
        /// Distinct-group pairs wrongly predicted as matches, over all
        /// distinct-group pairs. The error class we most want near zero.
        var hardNegativeFalsePositiveRate: Double {
            let denominator = falsePositives + trueNegatives
            return denominator == 0 ? 0 : Double(falsePositives) / Double(denominator)
        }
    }

    /// Map each path to the predicted cluster id it landed in (members of the
    /// same `DuplicateCluster` share an id). Paths absent from any cluster are
    /// unclustered (singletons).
    static func predictedClusterByPath(_ clusters: [DuplicateCluster]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (index, cluster) in clusters.enumerated() {
            for member in cluster.members {
                map[member.path] = index
            }
        }
        return map
    }

    static func pairScore(
        manifest: CalibrationManifest,
        predictedClusterByPath: [String: Int]
    ) -> PairScore {
        var score = PairScore()
        for pair in manifest.truthPairs() {
            let pathA = manifest.items[pair.i].path
            let pathB = manifest.items[pair.j].path
            let predictedMatch: Bool
            if let a = predictedClusterByPath[pathA], let b = predictedClusterByPath[pathB] {
                predictedMatch = a == b
            } else {
                predictedMatch = false
            }
            switch (pair.isMatch, predictedMatch) {
            case (true, true): score.truePositives += 1
            case (false, true): score.falsePositives += 1
            case (true, false): score.falseNegatives += 1
            case (false, false): score.trueNegatives += 1
            }
        }
        return score
    }

    /// Recall ceiling of the pre-match prune: of all true duplicate pairs, the
    /// fraction where both videos decoded to `.ready`, agree on aspect within
    /// tolerance, and fall within the duration window. A pair pruned here can
    /// never be recovered by frame-threshold tuning.
    static func candidateIndexRecall(
        manifest: CalibrationManifest,
        features: [String: VideoPerceptualFeatures],
        configuration: VideoPerceptualMatchConfiguration
    ) -> Double {
        var total = 0
        var survived = 0
        for pair in manifest.truthPairs() where pair.isMatch {
            total += 1
            guard let a = features[manifest.items[pair.i].path],
                  let b = features[manifest.items[pair.j].path],
                  a.status == .ready, b.status == .ready else { continue }
            if survivesPrune(a, b, configuration: configuration) { survived += 1 }
        }
        return total == 0 ? 1 : Double(survived) / Double(total)
    }

    /// Replicates the matcher's prune (the matcher's own helper is internal):
    /// aspect gate + duration window.
    static func survivesPrune(
        _ a: VideoPerceptualFeatures,
        _ b: VideoPerceptualFeatures,
        configuration: VideoPerceptualMatchConfiguration
    ) -> Bool {
        let la = a.aspectRatio
        let lb = b.aspectRatio
        guard la > 0, lb > 0 else { return false }
        let aspectOK = abs(la - lb) / max(la, lb) <= configuration.aspectRatioTolerance
        let durationOK = abs(a.durationSeconds - b.durationSeconds) <= configuration.durationToleranceSeconds
        return aspectOK && durationOK
    }

    /// Standard cluster purity: over all clustered items, the fraction that
    /// belong to the dominant `truthGroup` of their predicted cluster. 1.0 when
    /// every predicted cluster is pure.
    static func clusterPurity(
        manifest: CalibrationManifest,
        clusters: [DuplicateCluster]
    ) -> Double {
        let groupByPath = Dictionary(uniqueKeysWithValues: manifest.items.map { ($0.path, $0.truthGroup) })
        var clusteredItems = 0
        var dominantSum = 0
        for cluster in clusters {
            var counts: [String: Int] = [:]
            for member in cluster.members {
                guard let group = groupByPath[member.path] else { continue }
                counts[group, default: 0] += 1
                clusteredItems += 1
            }
            dominantSum += counts.values.max() ?? 0
        }
        return clusteredItems == 0 ? 1 : Double(dominantSum) / Double(clusteredItems)
    }

    /// Per-class recall: for each `class`, the fraction of true-match pairs that
    /// touch an item of that class which were predicted as matches. A pair can
    /// count toward two classes (one per endpoint); this is a diagnostic
    /// breakdown, not a partition.
    static func perClassRecall(
        manifest: CalibrationManifest,
        predictedClusterByPath: [String: Int]
    ) -> [(className: String, recall: Double, support: Int)] {
        var matched: [String: Int] = [:]
        var total: [String: Int] = [:]
        for pair in manifest.truthPairs() where pair.isMatch {
            let pathA = manifest.items[pair.i].path
            let pathB = manifest.items[pair.j].path
            let predictedMatch: Bool
            if let a = predictedClusterByPath[pathA], let b = predictedClusterByPath[pathB] {
                predictedMatch = a == b
            } else {
                predictedMatch = false
            }
            for className in Set([manifest.items[pair.i].class, manifest.items[pair.j].class].compactMap { $0 }) {
                total[className, default: 0] += 1
                if predictedMatch { matched[className, default: 0] += 1 }
            }
        }
        return total.keys.sorted().map { className in
            let support = total[className] ?? 0
            let hits = matched[className] ?? 0
            return (className, support == 0 ? 1 : Double(hits) / Double(support), support)
        }
    }

    /// Normalize a cluster set to compare warm vs cold rescans: each cluster
    /// becomes its sorted member paths + sorted keeper paths; cluster UUIDs
    /// (random) are excluded. Returns a stable, comparable signature.
    static func normalizedSignature(_ clusters: [DuplicateCluster]) -> [[String]] {
        clusters.map { cluster in
            let members = cluster.members.map(\.path).sorted()
            let keepers = cluster.suggestedKeeperIDs.sorted()
            return members + ["::keepers::"] + keepers
        }
        .sorted { ($0.first ?? "") < ($1.first ?? "") }
    }
}
