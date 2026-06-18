import Foundation

/// One labeled video in the calibration corpus. Items sharing a `truthGroup`
/// of size > 1 are ground-truth duplicates of one another; a singleton group is
/// a non-duplicate. `class` is free-form (see the rubric's class names) and is
/// used only for the per-class recall breakdown.
struct CalibrationItem: Decodable {
    let path: String
    let truthGroup: String
    let `class`: String?
}

/// The external manifest the labeler maintains locally. See
/// `docs/video-dedupe-calibration-rubric.md` for the format and labeling rules.
struct CalibrationManifest: Decodable {
    let items: [CalibrationItem]

    static func load(from path: String) throws -> CalibrationManifest {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CalibrationManifest.self, from: data)
    }

    /// Every unordered index pair `(i, j)` with `i < j` and whether the two
    /// items are a ground-truth match (same non-singleton `truthGroup`).
    func truthPairs() -> [(i: Int, j: Int, isMatch: Bool)] {
        var pairs: [(i: Int, j: Int, isMatch: Bool)] = []
        for i in items.indices {
            for j in (i + 1)..<items.count {
                pairs.append((i, j, items[i].truthGroup == items[j].truthGroup))
            }
        }
        return pairs
    }
}
