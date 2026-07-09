import Foundation

/// Injection seam over `FileSystemMonitor` so the watch coordinator can
/// be tested against a scripted fake that yields deterministic outputs.
public protocol FileSystemMonitoring: AnyObject, Sendable {
    /// True while the reduced-fidelity polling fallback is active.
    var isDegraded: Bool { get }
    func start() -> AsyncStream<FileSystemMonitorOutput>
    func stop()
}

extension FileSystemMonitor: FileSystemMonitoring {}
