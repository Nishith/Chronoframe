import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class NetworkDestinationAdvisoryTests: XCTestCase {
    private func scratchDefaults() -> UserDefaults {
        let suite = "NetworkDestinationAdvisory-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // Capture only the suite name (a Sendable String); rebuild a handle in
        // the teardown so the non-Sendable `defaults` isn't sent across actors.
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return defaults
    }

    func testWarnsOnceForRemoteDestinationThenStaysSilent() {
        let advisory = NetworkDestinationAdvisory(defaults: scratchDefaults(), isRemote: { _ in true })
        let root = URL(fileURLWithPath: "/Volumes/Share/Library", isDirectory: true)

        XCTAssertEqual(advisory.warningIfNeeded(for: root), NetworkDestinationAdvisory.warningMessage)
        XCTAssertNil(advisory.warningIfNeeded(for: root), "the same destination must warn at most once")
    }

    func testNeverWarnsForLocalDestination() {
        let advisory = NetworkDestinationAdvisory(defaults: scratchDefaults(), isRemote: { _ in false })
        let root = URL(fileURLWithPath: "/Users/me/Pictures/Library", isDirectory: true)

        XCTAssertNil(advisory.warningIfNeeded(for: root))
    }

    func testWarnsSeparatelyPerDistinctRemoteDestination() {
        let advisory = NetworkDestinationAdvisory(defaults: scratchDefaults(), isRemote: { _ in true })

        XCTAssertNotNil(advisory.warningIfNeeded(for: URL(fileURLWithPath: "/Volumes/A/Lib", isDirectory: true)))
        XCTAssertNotNil(advisory.warningIfNeeded(for: URL(fileURLWithPath: "/Volumes/B/Lib", isDirectory: true)))
        XCTAssertNil(advisory.warningIfNeeded(for: URL(fileURLWithPath: "/Volumes/A/Lib", isDirectory: true)))
    }

    func testWarnedSetPersistsAcrossAdvisoryInstances() {
        let defaults = scratchDefaults()
        let root = URL(fileURLWithPath: "/Volumes/Share/Library", isDirectory: true)

        XCTAssertNotNil(
            NetworkDestinationAdvisory(defaults: defaults, isRemote: { _ in true }).warningIfNeeded(for: root)
        )
        // A fresh advisory backed by the same defaults must see the recorded path.
        XCTAssertNil(
            NetworkDestinationAdvisory(defaults: defaults, isRemote: { _ in true }).warningIfNeeded(for: root)
        )
    }

    /// Wiring: a dedupe scan against a remote destination surfaces the warning
    /// as the first emitted issue, exactly once.
    @MainActor
    func testDeduplicateScanEmitsNetworkWarningOnceForRemoteDestination() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DedupeNetworkWarn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = NativeDeduplicateEngine()
        engine.networkAdvisory = NetworkDestinationAdvisory(defaults: scratchDefaults(), isRemote: { _ in true })
        defer { engine.cancelCurrentScan() }

        let config = DeduplicateConfiguration(destinationPath: directory.path)

        let firstWarnings = try await collectWarnings(engine.scan(config))
        XCTAssertEqual(firstWarnings, [NetworkDestinationAdvisory.warningMessage])

        // Second scan on the same destination must not re-warn.
        let secondWarnings = try await collectWarnings(engine.scan(config))
        XCTAssertEqual(secondWarnings, [])
    }

    @MainActor
    private func collectWarnings(
        _ stream: AsyncThrowingStream<DeduplicateEvent, Error>
    ) async throws -> [String] {
        var warnings: [String] = []
        for try await event in stream {
            if case let .issue(issue) = event, issue.severity == .warning {
                warnings.append(issue.message)
            }
        }
        return warnings
    }
}
