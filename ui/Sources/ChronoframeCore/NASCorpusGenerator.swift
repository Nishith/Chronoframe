import Foundation

/// Deterministic pseudo-random generator (SplitMix64) for probe payloads and
/// corpus bytes. The same seed always yields the same bytes.
struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform-enough value in `0..<bound` (bound > 0) for corpus layout choices.
    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    mutating func fill(_ buffer: inout [UInt8]) {
        var index = 0
        while index < buffer.count {
            var word = next()
            var take = 0
            while take < 8, index < buffer.count {
                buffer[index] = UInt8(truncatingIfNeeded: word)
                word >>= 8
                index += 1
                take += 1
            }
        }
    }
}

public struct NASCorpusManifest: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        /// Path relative to the corpus root, exactly as written to disk (a
        /// decomposed Unicode name stays decomposed).
        public var relativePath: String
        public var size: Int64
        /// `FileIdentityHasher` digest (BLAKE2b over the decimal size, then the bytes).
        public var digest: String
        /// True for files inside `@eaDir`, `#recycle` or `#snapshot`, which an assessment must exclude.
        public var excluded: Bool

        public init(relativePath: String, size: Int64, digest: String, excluded: Bool) {
            self.relativePath = relativePath
            self.size = size
            self.digest = digest
            self.excluded = excluded
        }
    }

    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var seed: UInt64
    public var requestedFileCount: Int
    public var duplicatePercent: Int
    public var files: [File]
    /// Exact groups an assessment must find: NFC relative paths sorted ascending inside
    /// each group, groups sorted by first member. Excluded and zero-byte files never appear.
    public var expectedGroups: [[String]]

    public init(
        schemaVersion: Int = NASCorpusManifest.currentSchemaVersion,
        seed: UInt64,
        requestedFileCount: Int,
        duplicatePercent: Int,
        files: [File],
        expectedGroups: [[String]]
    ) {
        self.schemaVersion = schemaVersion
        self.seed = seed
        self.requestedFileCount = requestedFileCount
        self.duplicatePercent = duplicatePercent
        self.files = files
        self.expectedGroups = expectedGroups
    }
}

public enum NASCorpusError: LocalizedError, Sendable, Equatable {
    case invalidArguments(String)
    case destinationUnavailable(path: String)
    case destinationNotEmpty(path: String)
    case manifestInsideDestination(path: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            return "The corpus settings aren't valid: \(message). Nothing was created."
        case let .destinationUnavailable(path):
            return "The corpus folder can't be used: \(path). Nothing was created."
        case let .destinationNotEmpty(path):
            return "The corpus folder must be empty: \(path). Nothing was created."
        case let .manifestInsideDestination(path):
            return "The manifest can't be saved inside the corpus folder: \(path). Nothing was created."
        }
    }
}

/// Writes a deterministic test corpus (C-14 `make-corpus`) for the NAS parity gate.
public enum NASCorpusGenerator {
    private static let minimumFileCount = 16
    private static let maximumDuplicatePercent = 90

    private struct Spec {
        var relativePath: String
        var size: Int
        var contentSeed: UInt64
        var excluded: Bool
    }

    @discardableResult
    public static func generate(
        destination: URL,
        manifestURL: URL,
        fileCount: Int,
        duplicatePercent: Int,
        seed: UInt64
    ) throws -> NASCorpusManifest {
        guard fileCount >= minimumFileCount else {
            throw NASCorpusError.invalidArguments("--files must be at least \(minimumFileCount)")
        }
        guard (0...maximumDuplicatePercent).contains(duplicatePercent) else {
            throw NASCorpusError.invalidArguments("--duplicate-percent must be between 0 and \(maximumDuplicatePercent)")
        }
        guard !NASPathContainment.isInside(manifestURL, of: destination) else {
            throw NASCorpusError.manifestInsideDestination(path: manifestURL.path)
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw NASCorpusError.destinationUnavailable(path: destination.path)
            }
            guard let existing = try? fileManager.contentsOfDirectory(atPath: destination.path) else {
                throw NASCorpusError.destinationUnavailable(path: destination.path)
            }
            guard existing.isEmpty else {
                throw NASCorpusError.destinationNotEmpty(path: destination.path)
            }
        } else {
            do {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                throw NASCorpusError.destinationUnavailable(path: destination.path)
            }
        }

        let specs = plan(fileCount: fileCount, duplicatePercent: duplicatePercent, seed: seed)

        var createdDirectories = Set<String>()
        var entries: [NASCorpusManifest.File] = []
        entries.reserveCapacity(specs.count)
        for spec in specs {
            let fileURL = URL(fileURLWithPath: destination.path + "/" + spec.relativePath)
            let parent = fileURL.deletingLastPathComponent()
            if createdDirectories.insert(parent.path).inserted {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            var bytes = [UInt8](repeating: 0, count: spec.size)
            var generator = SplitMix64(seed: spec.contentSeed)
            generator.fill(&bytes)
            try Data(bytes).write(to: fileURL, options: .withoutOverwriting)

            entries.append(NASCorpusManifest.File(
                relativePath: spec.relativePath,
                size: Int64(spec.size),
                digest: digest(of: bytes),
                excluded: spec.excluded
            ))
        }
        entries.sort { $0.relativePath < $1.relativePath }

        let manifest = NASCorpusManifest(
            seed: seed,
            requestedFileCount: fileCount,
            duplicatePercent: duplicatePercent,
            files: entries,
            expectedGroups: expectedGroups(for: entries)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        try fileManager.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: manifestURL, options: .atomic)
        return manifest
    }

    // MARK: Layout

    private static func plan(fileCount: Int, duplicatePercent: Int, seed: UInt64) -> [Spec] {
        var rng = SplitMix64(seed: seed ^ 0x4E41_5343_4F52_5055)
        let folderCount = max(4, fileCount / 40)
        let folders = (0..<folderCount).map { index in
            "Library-\(pad(index / 6, 2))/Album-\(pad(index % 6, 2))"
        }

        var specs: [Spec] = []

        // Zero-byte files: never read, never grouped.
        specs.append(Spec(relativePath: "\(folders[0])/IMG_ZERO_0001.jpg", size: 0, contentSeed: 0, excluded: false))
        specs.append(Spec(relativePath: "\(folders[1])/IMG_ZERO_0002.heic", size: 0, contentSeed: 0, excluded: false))

        // Same size, different bytes: both hash as candidates but never group.
        let sameA = rng.next()
        let sameB = rng.next()
        specs.append(Spec(relativePath: "\(folders[2])/IMG_SAME_A.jpg", size: 4096, contentSeed: sameA, excluded: false))
        specs.append(Spec(relativePath: "\(folders[3])/IMG_SAME_B.jpg", size: 4096, contentSeed: sameB, excluded: false))

        // A decomposed (NFD) name and a precomposed (NFC) exact duplicate in another folder.
        let unicodeSeed = rng.next()
        specs.append(Spec(relativePath: "\(folders[0])/Cafe\u{0301} Re\u{0301}sume\u{0301}.jpg", size: 9000, contentSeed: unicodeSeed, excluded: false))
        specs.append(Spec(relativePath: "\(folders[1])/Caf\u{00E9} R\u{00E9}sum\u{00E9} copy.jpg", size: 9000, contentSeed: unicodeSeed, excluded: false))

        // Synology system containers holding duplicates that an assessment must exclude.
        specs.append(Spec(relativePath: "\(folders[2])/@eaDir/IMG_SAME_A.jpg/SYNOPHOTO_THUMB_M.jpg", size: 4096, contentSeed: sameA, excluded: true))
        specs.append(Spec(relativePath: "\(folders[3])/@eaDir/IMG_SAME_B.jpg/SYNOPHOTO_THUMB_M.jpg", size: 4096, contentSeed: sameB, excluded: true))
        let recycleSeed = rng.next()
        specs.append(Spec(relativePath: "#recycle/Deleted-1.jpg", size: 5000, contentSeed: recycleSeed, excluded: true))
        specs.append(Spec(relativePath: "#recycle/Deleted-2.jpg", size: 5000, contentSeed: recycleSeed, excluded: true))
        specs.append(Spec(relativePath: "#snapshot/GMT-2026.11.07/IMG_COPY.jpg", size: 9000, contentSeed: unicodeSeed, excluded: true))

        let remaining = fileCount - specs.count
        let duplicateCount = min(remaining * duplicatePercent / 100, remaining - 1)
        let baseCount = remaining - duplicateCount

        struct Base { var folderIndex: Int; var ext: String; var size: Int; var contentSeed: UInt64 }
        var bases: [Base] = []
        var index = 1
        for _ in 0..<baseCount {
            let kind = rng.next(below: 10)
            let ext = kind < 6 ? "jpg" : (kind < 8 ? "heic" : "mov")
            let size = ext == "mov" ? 16_384 + rng.next(below: 80_000) : 1024 + rng.next(below: 47_000)
            let base = Base(folderIndex: rng.next(below: folderCount), ext: ext, size: size, contentSeed: rng.next())
            specs.append(Spec(
                relativePath: "\(folders[base.folderIndex])/IMG_\(pad(index, 6)).\(ext)",
                size: size,
                contentSeed: base.contentSeed,
                excluded: false
            ))
            bases.append(base)
            index += 1
        }
        for _ in 0..<duplicateCount {
            let base = bases[rng.next(below: bases.count)]
            var folderIndex = rng.next(below: folderCount)
            if folderIndex == base.folderIndex { folderIndex = (folderIndex + 1) % folderCount }
            specs.append(Spec(
                relativePath: "\(folders[folderIndex])/IMG_\(pad(index, 6)).\(base.ext)",
                size: base.size,
                contentSeed: base.contentSeed,
                excluded: false
            ))
            index += 1
        }
        return specs
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    private static func digest(of bytes: [UInt8]) -> String {
        var hasher = BLAKE2bHasher()
        hasher.update(Data(String(bytes.count).utf8))
        if !bytes.isEmpty {
            bytes.withUnsafeBytes { hasher.update($0) }
        }
        return hasher.finalizeHexDigest()
    }

    private static func expectedGroups(for files: [NASCorpusManifest.File]) -> [[String]] {
        var byDigest: [String: [String]] = [:]
        for file in files where !file.excluded && file.size > 0 {
            byDigest[file.digest, default: []].append(file.relativePath.precomposedStringWithCanonicalMapping)
        }
        return byDigest.values
            .filter { $0.count >= 2 }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
    }
}
