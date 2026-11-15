import Foundation

/// Whether a destination takes the remote (network folder) copy rules, and the
/// volume it was observed on. A volume that can't be classified is remote.
public struct NASRemoteCopyPolicy: Sendable, Equatable {
    public var isRemote: Bool
    public var volume: NASVolumeObservation

    public init(isRemote: Bool, volume: NASVolumeObservation) {
        self.isRemote = isRemote
        self.volume = volume
    }

    public static func resolve(destinationRoot: URL, classifier: NASVolumeClassifier = .live) -> NASRemoteCopyPolicy {
        let volume = classifier.classify(destinationRoot)
        return NASRemoteCopyPolicy(isRemote: volume.kind != .local, volume: volume)
    }

    public static let local = NASRemoteCopyPolicy(
        isRemote: false,
        volume: NASVolumeObservation(
            kind: .local,
            fileSystemType: "",
            mountPoint: "",
            serverHost: nil,
            shareName: nil,
            fileSystemID: 0,
            observedPath: ""
        )
    )
}
