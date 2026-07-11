#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Guardian schedule persistence (Phase 4)
//
// The per-library next-run / last-attempted / last-succeeded state is a tiny JSON
// file in the library's Guardian state directory (Application Support). The
// protocol lets tests inject an in-memory double so the scheduling contract is
// verified without the filesystem.

public protocol GuardianSchedulePersisting: Sendable {
    func load(for identity: GuardianLibraryIdentity) -> GuardianScheduleState
    func save(_ state: GuardianScheduleState, for identity: GuardianLibraryIdentity)
}

/// Default file-backed persistence: `schedule.json` under the library's Guardian
/// state directory. A missing or unreadable file reads as a fresh state (never
/// scheduled), so a corrupt schedule can only cost a catch-up run, never data.
public struct GuardianFileSchedulePersistence: GuardianSchedulePersisting {
    public init() {}

    public func load(for identity: GuardianLibraryIdentity) -> GuardianScheduleState {
        let url = GuardianPaths.scheduleURL(for: identity)
        guard
            let data = try? Data(contentsOf: url),
            let state = try? Self.decoder.decode(GuardianScheduleState.self, from: data)
        else {
            return GuardianScheduleState()
        }
        return state
    }

    public func save(_ state: GuardianScheduleState, for identity: GuardianLibraryIdentity) {
        try? GuardianPaths.ensureStateDirectory(for: identity)
        let url = GuardianPaths.scheduleURL(for: identity)
        guard let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
