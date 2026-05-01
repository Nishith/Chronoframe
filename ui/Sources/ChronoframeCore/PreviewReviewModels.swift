import Foundation

public enum DateResolutionSource: String, Codable, Sendable, CaseIterable {
    case photoMetadata
    case filename
    case fileSystemCreation
    case fileSystemModification
    case userOverride
    case unknown

    public var title: String {
        switch self {
        case .photoMetadata:
            return "Photo Metadata"
        case .filename:
            return "Filename"
        case .fileSystemCreation:
            return "Created Date"
        case .fileSystemModification:
            return "Modified Date"
        case .userOverride:
            return "Edited"
        case .unknown:
            return "Unknown"
        }
    }
}

public enum DateResolutionConfidence: String, Codable, Sendable, CaseIterable {
    case high
    case medium
    case low
    case unknown

    public var title: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Low"
        case .unknown:
            return "Unknown"
        }
    }
}

public struct ResolvedMediaDate: Equatable, Codable, Sendable {
    public var date: Date?
    public var source: DateResolutionSource
    public var confidence: DateResolutionConfidence

    public init(
        date: Date?,
        source: DateResolutionSource,
        confidence: DateResolutionConfidence
    ) {
        self.date = date
        self.source = source
        self.confidence = confidence
    }

    public static let unknown = ResolvedMediaDate(
        date: nil,
        source: .unknown,
        confidence: .unknown
    )

    public func applying(_ override: ReviewOverride?) -> ResolvedMediaDate {
        guard let override, let captureDate = override.captureDate else {
            return self
        }
        return ResolvedMediaDate(
            date: captureDate,
            source: .userOverride,
            confidence: .high
        )
    }
}

public enum EventSuggestionMode: String, Codable, Sendable, CaseIterable {
    case off
    case suggest
}

public enum EventSuggestionSource: String, Codable, Sendable {
    case sourceFolder
    case timeCluster
    case userOverride
}

public struct EventSuggestion: Equatable, Codable, Sendable {
    public var groupID: String
    public var suggestedName: String?
    public var source: EventSuggestionSource
    public var confidence: DateResolutionConfidence

    public init(
        groupID: String,
        suggestedName: String?,
        source: EventSuggestionSource,
        confidence: DateResolutionConfidence
    ) {
        self.groupID = groupID
        self.suggestedName = suggestedName
        self.source = source
        self.confidence = confidence
    }
}

public struct EventSuggestionCandidate: Equatable, Sendable {
    public var sourcePath: String
    public var sourceRoot: String
    public var capturedAt: Date
    public var dateBucket: String

    public init(
        sourcePath: String,
        sourceRoot: String,
        capturedAt: Date,
        dateBucket: String
    ) {
        self.sourcePath = sourcePath
        self.sourceRoot = sourceRoot
        self.capturedAt = capturedAt
        self.dateBucket = dateBucket
    }
}

public enum PreviewReviewStatus: String, Codable, Sendable, CaseIterable {
    case ready
    case alreadyInDestination
    case duplicate
    case hashError

    public var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .alreadyInDestination:
            return "Already There"
        case .duplicate:
            return "Duplicate"
        case .hashError:
            return "Needs Attention"
        }
    }
}

public enum PreviewReviewIssueKind: String, Codable, Sendable, CaseIterable {
    case unknownDate
    case lowConfidenceDate
    case duplicate
    case alreadyInDestination
    case hashError

    public var title: String {
        switch self {
        case .unknownDate:
            return "Unknown date"
        case .lowConfidenceDate:
            return "Low confidence date"
        case .duplicate:
            return "Duplicate"
        case .alreadyInDestination:
            return "Already in destination"
        case .hashError:
            return "Could not read file"
        }
    }
}

public struct PreviewReviewItem: Identifiable, Equatable, Codable, Sendable {
    public var sourcePath: String
    public var identityRawValue: String?
    public var resolvedDate: Date?
    public var dateSource: DateResolutionSource
    public var dateConfidence: DateResolutionConfidence
    public var plannedDestinationPath: String?
    public var status: PreviewReviewStatus
    public var issues: [PreviewReviewIssueKind]
    public var eventSuggestion: EventSuggestion?
    public var acceptedEventName: String?

    public var id: String { sourcePath }

    public init(
        sourcePath: String,
        identityRawValue: String?,
        resolvedDate: Date?,
        dateSource: DateResolutionSource,
        dateConfidence: DateResolutionConfidence,
        plannedDestinationPath: String?,
        status: PreviewReviewStatus,
        issues: [PreviewReviewIssueKind],
        eventSuggestion: EventSuggestion? = nil,
        acceptedEventName: String? = nil
    ) {
        self.sourcePath = sourcePath
        self.identityRawValue = identityRawValue
        self.resolvedDate = resolvedDate
        self.dateSource = dateSource
        self.dateConfidence = dateConfidence
        self.plannedDestinationPath = plannedDestinationPath
        self.status = status
        self.issues = issues
        self.eventSuggestion = eventSuggestion
        self.acceptedEventName = acceptedEventName
    }

    public var needsAttention: Bool {
        issues.contains(.unknownDate)
            || issues.contains(.lowConfidenceDate)
            || issues.contains(.hashError)
    }
}

public struct PreviewReviewSummary: Equatable, Codable, Sendable {
    public var totalCount: Int
    public var readyCount: Int
    public var needsAttentionCount: Int
    public var unknownDateCount: Int
    public var lowConfidenceDateCount: Int
    public var duplicateCount: Int
    public var alreadyInDestinationCount: Int
    public var hashErrorCount: Int

    public init(items: [PreviewReviewItem]) {
        totalCount = items.count
        readyCount = items.filter { $0.status == .ready }.count
        needsAttentionCount = items.filter(\.needsAttention).count
        unknownDateCount = items.filter { $0.issues.contains(.unknownDate) }.count
        lowConfidenceDateCount = items.filter { $0.issues.contains(.lowConfidenceDate) }.count
        duplicateCount = items.filter { $0.status == .duplicate }.count
        alreadyInDestinationCount = items.filter { $0.status == .alreadyInDestination }.count
        hashErrorCount = items.filter { $0.status == .hashError }.count
    }

    public init(
        totalCount: Int = 0,
        readyCount: Int = 0,
        needsAttentionCount: Int = 0,
        unknownDateCount: Int = 0,
        lowConfidenceDateCount: Int = 0,
        duplicateCount: Int = 0,
        alreadyInDestinationCount: Int = 0,
        hashErrorCount: Int = 0
    ) {
        self.totalCount = totalCount
        self.readyCount = readyCount
        self.needsAttentionCount = needsAttentionCount
        self.unknownDateCount = unknownDateCount
        self.lowConfidenceDateCount = lowConfidenceDateCount
        self.duplicateCount = duplicateCount
        self.alreadyInDestinationCount = alreadyInDestinationCount
        self.hashErrorCount = hashErrorCount
    }
}

public struct ReviewOverride: Equatable, Codable, Sendable {
    public var identity: FileIdentity
    public var sourcePath: String
    public var captureDate: Date?
    public var eventName: String?
    public var updatedAt: Date

    public init(
        identity: FileIdentity,
        sourcePath: String,
        captureDate: Date? = nil,
        eventName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.identity = identity
        self.sourcePath = sourcePath
        self.captureDate = captureDate
        self.eventName = Self.normalizedEventName(eventName)
        self.updatedAt = updatedAt
    }

    public static func normalizedEventName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public enum EventSuggestionEngine {
    public static let defaultGapSeconds: TimeInterval = 8 * 60 * 60

    public static func suggestions(
        for candidates: [EventSuggestionCandidate],
        gapSeconds: TimeInterval = defaultGapSeconds
    ) -> [String: EventSuggestion] {
        guard !candidates.isEmpty else { return [:] }

        let grouped = Dictionary(grouping: candidates) { $0.dateBucket }
        var suggestionsByPath: [String: EventSuggestion] = [:]

        for dateBucket in grouped.keys.sorted() {
            let sorted = (grouped[dateBucket] ?? []).sorted {
                if $0.capturedAt == $1.capturedAt {
                    return $0.sourcePath < $1.sourcePath
                }
                return $0.capturedAt < $1.capturedAt
            }

            var clusters: [[EventSuggestionCandidate]] = []
            for candidate in sorted {
                guard var current = clusters.popLast() else {
                    clusters.append([candidate])
                    continue
                }

                let previous = current[current.count - 1]
                if candidate.capturedAt.timeIntervalSince(previous.capturedAt) > gapSeconds {
                    clusters.append(current)
                    clusters.append([candidate])
                } else {
                    current.append(candidate)
                    clusters.append(current)
                }
            }

            for (index, cluster) in clusters.enumerated() {
                let groupID = "\(dateBucket)-\(index + 1)"
                let suggestedName = bestSourceFolderName(for: cluster)
                let suggestion = EventSuggestion(
                    groupID: groupID,
                    suggestedName: suggestedName,
                    source: suggestedName == nil ? .timeCluster : .sourceFolder,
                    confidence: suggestedName == nil ? .low : .medium
                )

                for candidate in cluster {
                    suggestionsByPath[candidate.sourcePath] = suggestion
                }
            }
        }

        return suggestionsByPath
    }

    private static func bestSourceFolderName(for cluster: [EventSuggestionCandidate]) -> String? {
        var counts: [String: Int] = [:]
        for candidate in cluster {
            let name = sourceFolderName(sourcePath: candidate.sourcePath, sourceRoot: candidate.sourceRoot)
            guard let name, !isGenericFolderName(name) else { continue }
            counts[name, default: 0] += 1
        }

        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .first?
            .key
    }

    private static func sourceFolderName(sourcePath: String, sourceRoot: String) -> String? {
        let parentURL = URL(fileURLWithPath: sourcePath)
            .deletingLastPathComponent()
            .standardizedFileURL
        let rootURL = URL(fileURLWithPath: sourceRoot, isDirectory: true)
            .standardizedFileURL

        guard parentURL.path != rootURL.path else { return nil }
        let name = parentURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func isGenericFolderName(_ value: String) -> Bool {
        genericFolderNames.contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static let genericFolderNames: Set<String> = [
        "dcim",
        "camera",
        "photos",
        "photo",
        "imports",
        "import",
        "downloads",
        "download",
        "100apple",
        "101apple",
        "102apple",
        "100media",
    ]
}
