#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation

enum LibraryHealthCopy {
    static func message(_ card: LibraryHealthCard, bundle: Bundle = .module) -> String {
        switch card.messageDetails {
        case let .unknownDateBytes(bytes):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return String(localized: "\(size) of files need a date.", bundle: bundle)
        case let .duplicateBytes(bytes):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return String(localized: "\(size) could be freed after you review them.", bundle: bundle)
        case let .unfinishedCopies(pending, failed):
            return String(localized: "\(pending) waiting, \(failed) failed. Open Preview & Copy to finish them.", bundle: bundle)
        case nil:
            return AppLocalization.string(card.message, bundle: bundle)
        }
    }
}
