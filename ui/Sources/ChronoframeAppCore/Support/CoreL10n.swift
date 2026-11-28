import Foundation

/// App-facing copy always uses the Core catalog, including in SwiftPM's
/// separate resource bundle. Values keep their interpolation types so counts
/// and paths are formatted by Foundation rather than substituted manually.
enum CoreL10n {
    static func text(_ key: String.LocalizationValue, bundle: Bundle = .module) -> String {
        String(localized: key, table: "LocalizableCore", bundle: bundle)
    }

    static func files(_ count: Int, bundle: Bundle = .module) -> String {
        count == 1 ? text("\(count) file", bundle: bundle) : text("\(count) files", bundle: bundle)
    }

    static func duplicates(_ count: Int, bundle: Bundle = .module) -> String {
        count == 1 ? text("\(count) duplicate", bundle: bundle) : text("\(count) duplicates", bundle: bundle)
    }
}
