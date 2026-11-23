import Foundation

/// Count-dependent phrases for AppCore copy. A count of 1 chooses a complete
/// singular phrase instead of "1 files", and each phrase is looked up whole so
/// German can agree in case and number ("von 1 Datei", "0 von 1 Objekt ist
/// bereit"). Zero stays plural.
enum CorePlurals {
    /// "Scanning 1 file…" when the run reports a running count with no total.
    static func runningFileCount(phaseTitle: String, completed: Int, bundle: Bundle = .module) -> String {
        completed == 1
            ? CoreL10n.text("\(phaseTitle) 1 file…", bundle: bundle)
            : CoreL10n.text("\(phaseTitle) \(completed.formatted()) files…", bundle: bundle)
    }

    /// "3 of 10 files", "1 of 1 file". The noun follows the total.
    static func fileProgress(completed: Int, total: Int, bundle: Bundle = .module) -> String {
        total == 1
            ? CoreL10n.text("\(completed.formatted()) of 1 file", bundle: bundle)
            : CoreL10n.text("\(completed.formatted()) of \(total.formatted()) files", bundle: bundle)
    }

    static func cleanedTemporaryFiles(_ count: Int, bundle: Bundle = .module) -> String {
        count == 1
            ? CoreL10n.text("Cleaned 1 orphaned .tmp file", bundle: bundle)
            : CoreL10n.text("Cleaned \(count) orphaned .tmp files", bundle: bundle)
    }

    static func unreadableSourceFiles(_ count: Int, bundle: Bundle = .module) -> String {
        count == 1
            ? CoreL10n.text("Chronoframe could not read 1 source file, so nothing was copied. Originals were left untouched; check file access and try again.", bundle: bundle)
            : CoreL10n.text("Chronoframe could not read \(count) source files, so nothing was copied. Originals were left untouched; check file access and try again.", bundle: bundle)
    }

    static func photosItemsUnreadable(_ count: Int, bundle: Bundle = .module) -> String {
        count == 1
            ? CoreL10n.text("1 item couldn't be read and was skipped. Your Photos library was not changed.", bundle: bundle)
            : CoreL10n.text("\(count) items couldn't be read and were skipped. Your Photos library was not changed.", bundle: bundle)
    }

    static func importStopped(completed: Int, total: Int, bundle: Bundle = .module) -> String {
        let done = completed.formatted()
        return total == 1
            ? CoreL10n.text("Import stopped. \(done) of 1 item is ready and was kept. Resume whenever you like. Your Photos library was not changed.", bundle: bundle)
            : CoreL10n.text("Import stopped. \(done) of \(total.formatted()) items are ready and were kept. Resume whenever you like. Your Photos library was not changed.", bundle: bundle)
    }

    static func importPausedLowSpace(completed: Int, total: Int, bundle: Bundle = .module) -> String {
        let done = completed.formatted()
        return total == 1
            ? CoreL10n.text("Chronoframe paused the import because the drive holding its staging folder is almost full. \(done) of 1 item is ready and was kept. Free up space, then resume. Your Photos library was not changed.", bundle: bundle)
            : CoreL10n.text("Chronoframe paused the import because the drive holding its staging folder is almost full. \(done) of \(total.formatted()) items are ready and were kept. Free up space, then resume. Your Photos library was not changed.", bundle: bundle)
    }

    static func importProgressNotSaved(completed: Int, total: Int, bundle: Bundle = .module) -> String {
        let done = completed.formatted()
        return total == 1
            ? CoreL10n.text("Chronoframe stopped the import because it couldn't save its progress. The drive holding its staging folder may be full. \(done) of 1 item is ready and was kept. Free up space, then resume. Your Photos library was not changed.", bundle: bundle)
            : CoreL10n.text("Chronoframe stopped the import because it couldn't save its progress. The drive holding its staging folder may be full. \(done) of \(total.formatted()) items are ready and were kept. Free up space, then resume. Your Photos library was not changed.", bundle: bundle)
    }
}
