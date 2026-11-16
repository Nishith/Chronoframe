import Foundation

/// Resolves app-authored keys supplied by presentation models. User content
/// such as paths and filenames must continue to be rendered verbatim.
enum AppLocalization {
    static var resourceBundle: Bundle { .module }

    static func string(_ key: String, bundle: Bundle = .module) -> String {
        String(localized: String.LocalizationValue(key), bundle: bundle)
    }
}
