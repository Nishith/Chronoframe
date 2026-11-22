import Foundation

/// Resolves app-authored keys supplied by presentation models. User content
/// such as paths and filenames must continue to be rendered verbatim.
enum AppLocalization {
    static var resourceBundle: Bundle { .module }

    static func string(_ key: String, bundle: Bundle = .module) -> String {
        String(localized: String.LocalizationValue(key), bundle: bundle)
    }

    /// Looks up a `%@` template and fills it in afterwards. Use this when a
    /// string names a row (a profile, a history entry): looking up the already
    /// interpolated sentence can never match a catalog key.
    static func format(_ key: String, _ argument: String, bundle: Bundle = .module) -> String {
        String(format: string(key, bundle: bundle), argument)
    }
}
