import Foundation

/// Caption on the Photos import screen that says what an import keeps. Pure so
/// the exact wording is unit-tested. The `true` branch is the wording for the
/// "Include edited versions" option; the screen only passes `false` until that
/// option exists.
enum PhotosImportEditsCaption {
    static func text(includeEditedVersions: Bool, bundle: Bundle = .module) -> String {
        if includeEditedVersions {
            return String(localized: "Also saves the edited version of each edited photo as a separate file. Edited videos and Live Photos are not included.", bundle: bundle)
        }
        return String(localized: "Imports the original photo or video. Edits made in Photos, such as crops and filters, are not included.", bundle: bundle)
    }
}
