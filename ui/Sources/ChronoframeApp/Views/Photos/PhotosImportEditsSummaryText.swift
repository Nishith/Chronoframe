#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation

/// Copy for the "Include edited versions" import: the pre-transfer line and the
/// import summary. Pure so the exact wording is unit-tested. Nothing here
/// shows a byte total, because PhotoKit exposes no public size for a render.
enum PhotosImportEditsSummaryText {
    /// Summary lines for an import that ran with edited versions on; empty
    /// otherwise.
    static func lines(
        for counts: PhotosImportEditedVersionCounts?,
        locale: Locale = .current,
        bundle: Bundle = .module
    ) -> [String] {
        guard let counts, counts.includedEditedVersions else { return [] }
        var lines = [
            countsLine(
                originals: counts.originals,
                edited: counts.editedVersions,
                couldNotSave: counts.couldNotSave,
                locale: locale,
                bundle: bundle
            )
        ]
        if counts.notIncluded > 0 {
            lines.append(PluralPhrases.editedVideosNotIncluded(counts.notIncluded, locale: locale, bundle: bundle))
        }
        return lines
    }

    /// Shown before the transfer when the prepared import holds edited photos.
    static func previewLine(
        for counts: PhotosImportEditedVersionCounts?,
        locale: Locale = .current,
        bundle: Bundle = .module
    ) -> String? {
        guard let counts, counts.includedEditedVersions, counts.editedVersions > 0 else { return nil }
        return PluralPhrases.editedPhotosWillAlsoBeSaved(counts.editedVersions, locale: locale, bundle: bundle)
    }

    static func countsLine(
        originals: Int,
        edited: Int,
        couldNotSave: Int,
        locale: Locale = .current,
        bundle: Bundle = .module
    ) -> String {
        String(
            format: AppLocalization.string("Originals: %@ · Edited versions: %@ · Could not save: %@", bundle: bundle),
            originals.formatted(.number.locale(locale)),
            edited.formatted(.number.locale(locale)),
            couldNotSave.formatted(.number.locale(locale))
        )
    }
}
