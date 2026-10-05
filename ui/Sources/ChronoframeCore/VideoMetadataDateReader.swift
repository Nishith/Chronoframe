import AVFoundation
import Foundation

/// Bridges AVFoundation's async metadata read to the existing synchronous
/// resolver. No decoding, external references, or unbounded waits. A timed-out
/// operation keeps its slot until AVFoundation actually finishes cancelling.
enum VideoMetadataDateReader {
    private static let slots = DispatchSemaphore(value: 4)

    private final class Load: @unchecked Sendable {
        let asset: AVURLAsset
        let finished = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var result: PhotoMetadataDate?

        init(url: URL) { asset = BoundedLivePhotoMetadataLoader.makeMetadataAsset(url: url) }
        func store(_ value: PhotoMetadataDate?) { lock.withLock { result = value } }
        func value() -> PhotoMetadataDate? { lock.withLock { result } }
    }

    static func read(
        at url: URL,
        timeoutSeconds: TimeInterval = 10,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        loader: @escaping @Sendable (AVURLAsset) async -> PhotoMetadataDate? = captureDate(from:)
    ) -> PhotoMetadataDate? {
        guard !isCancelled(), slots.wait(timeout: .now()) == .success else { return nil }
        let load = Load(url: url)
        let task = Task.detached(priority: .utility) {
            defer { slots.signal(); load.finished.signal() }
            load.store(await loader(load.asset))
        }
        let deadline = DispatchTime.now() + max(0.001, timeoutSeconds)
        repeat {
            if load.finished.wait(timeout: min(deadline, .now() + 0.05)) == .success {
                return load.value()
            }
        } while !isCancelled() && DispatchTime.now() < deadline
        task.cancel()
        load.asset.cancelLoading()
        return nil
    }

    private static func captureDate(from asset: AVURLAsset) async -> PhotoMetadataDate? {
        guard !Task.isCancelled else { return nil }
        let metadata = (try? await asset.load(.metadata)) ?? []
        // The explicit QuickTime capture timestamp (including its offset)
        // wins over a common creation-date projection without an offset.
        for item in metadata where item.identifier == .quickTimeMetadataCreationDate {
            guard !Task.isCancelled else { return nil }
            if let raw = try? await item.load(.stringValue), let parsed = parse(raw) { return parsed }
        }
        guard !Task.isCancelled else { return nil }
        let common = (try? await asset.load(.commonMetadata)) ?? []
        for item in common where item.commonKey == .commonKeyCreationDate {
            guard !Task.isCancelled else { return nil }
            if let raw = try? await item.load(.stringValue), let parsed = parse(raw) { return parsed }
        }
        return nil
    }

    /// Strict calendar validation avoids accepting rollover dates, pre-1900
    /// QuickTime sentinel dates, or malformed offsets as capture metadata.
    /// Offset-less timestamps retain the resolver's historical UTC convention.
    static func parse(_ raw: String) -> PhotoMetadataDate? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:?\d{2})?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        func field(_ index: Int) -> String? {
            Range(match.range(at: index), in: value).map { String(value[$0]) }
        }
        guard let year = field(1).flatMap(Int.init), (1900...2100).contains(year),
              let month = field(2).flatMap(Int.init), let day = field(3).flatMap(Int.init),
              let hour = field(4).flatMap(Int.init), let minute = field(5).flatMap(Int.init),
              let second = field(6).flatMap(Int.init),
              (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        let zone = field(8)
        let offset = zone.flatMap(NativeMediaMetadataDateReader.offsetSeconds(from:))
        guard zone == nil || offset != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offset ?? 0)!
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == components else { return nil }
        let fraction = field(7).flatMap { Double("0.\($0)") } ?? 0
        return PhotoMetadataDate(date: date.addingTimeInterval(fraction), bucketTimeZoneOffsetSeconds: offset)
    }
}
