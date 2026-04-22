import SwiftUI

struct HelpView: View {
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                ForEach(HelpContent.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)

                        VStack(spacing: 0) {
                            ForEach(section.items) { item in
                                FAQRow(
                                    item: item,
                                    isExpanded: expanded.contains(item.id)
                                ) {
                                    if expanded.contains(item.id) {
                                        expanded.remove(item.id)
                                    } else {
                                        expanded.insert(item.id)
                                    }
                                }
                                if item.id != section.items.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 420, idealHeight: 640)
        .navigationTitle("Chronoframe Help")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chronoframe Help")
                .font(.largeTitle.weight(.semibold))
            Text("Answers to the questions people ask most often. If something here is unclear, the Run workspace's Console and Issues tabs are also a good place to look.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FAQRow: View {
    let item: HelpContent.Item
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isExpanded)
                    Text(item.question)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(item.answer)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.leading, 21)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

enum HelpContent {
    struct Item: Identifiable, Equatable {
        let id: String
        let question: String
        let answer: String
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let items: [Item]
    }

    static let sections: [Section] = [
        Section(
            id: "getting-started",
            title: "Getting started",
            items: [
                Item(
                    id: "what-is-chronoframe",
                    question: "What is Chronoframe?",
                    answer: "Chronoframe copies photos and videos from one folder (your Source) into another folder (your Destination), sorting them into year / month / event folders based on when each file was captured. It never moves or deletes the originals — it only copies."
                ),
                Item(
                    id: "preview-vs-transfer",
                    question: "What is the difference between Preview and Transfer?",
                    answer: "Preview is a rehearsal. Chronoframe scans your Source, works out exactly what it would copy and where, and shows you the plan — without touching any files. Transfer is the real run that actually writes files to the Destination. Running a Preview first is the safest way to catch surprises."
                ),
                Item(
                    id: "what-is-a-profile",
                    question: "What is a profile?",
                    answer: "A profile is a saved configuration: a Source, a Destination, and the options you chose. Once you have a run set up the way you like, save it as a profile so you can start the same run again later with one click. Profiles live in the sidebar under Profiles."
                ),
            ]
        ),
        Section(
            id: "safety",
            title: "Your files are safe",
            items: [
                Item(
                    id: "will-it-move-or-delete",
                    question: "Will Chronoframe move or delete my original files?",
                    answer: "No. Chronoframe only copies. After a run, every file in your Source is still exactly where it started — and a copy now exists in the organized Destination. You can always go back to the originals."
                ),
                Item(
                    id: "cancel-safely",
                    question: "Can I safely cancel a run?",
                    answer: "Yes. Click Cancel Run at any time. Files that have already been copied remain in place at the Destination. Files that had not yet started copying are untouched in the Source. Run a Preview afterwards to see where things stand."
                ),
                Item(
                    id: "folder-access",
                    question: "Why does Chronoframe keep asking for access to my folders?",
                    answer: "macOS requires explicit permission for any app to read or write outside its sandbox. Chronoframe remembers your choice per folder, but unplugging a drive, moving the app, or updating macOS can sometimes reset those permissions. Reselect the folder in Setup and permission will be granted again."
                ),
            ]
        ),
        Section(
            id: "organization",
            title: "How files are organized",
            items: [
                Item(
                    id: "folder-layout",
                    question: "How does Chronoframe decide which folder a photo goes into?",
                    answer: "Chronoframe reads each file's capture date from its embedded metadata (often called EXIF). The file is then placed at: Destination / YEAR / MONTH / EVENT, where EVENT is taken from the name of the folder the file lived in at the Source. If no capture date can be read, Chronoframe falls back to the file's modification date."
                ),
                Item(
                    id: "already-vs-duplicates",
                    question: "What do \"Already There\" and \"Duplicates\" mean in the metrics?",
                    answer: "Already There means a file with the same content is already at the Destination where Chronoframe would put it, so no copy is needed. Duplicates means multiple files in your Source have identical content — one is copied and the others are logged, so nothing is silently dropped."
                ),
                Item(
                    id: "wrong-date",
                    question: "A photo landed in the wrong month or year. What happened?",
                    answer: "The photo's embedded capture date is the source of truth. If it was taken on a camera whose clock was wrong, or edited in a way that cleared the metadata, Chronoframe will sort it by whatever date is actually in the file. Fixing the date in Photos or exiftool and re-running will move it to the correct folder on the next Transfer."
                ),
            ]
        ),
        Section(
            id: "troubleshooting",
            title: "Troubleshooting",
            items: [
                Item(
                    id: "progress-stuck",
                    question: "The progress bar is not moving. Is something wrong?",
                    answer: "A run moves through several phases before it starts copying: Discover, Hash Source, Index Destination, Classify, then Transfer. On a large library the early phases can take minutes with no visible movement in the main progress bar. The phase strip beneath the bar shows which phase is running — the current one is highlighted in yellow."
                ),
                Item(
                    id: "drive-missing",
                    question: "My external drive or SD card is not available.",
                    answer: "If you unplugged and re-inserted the drive, macOS may have forgotten the access permission. Open Setup, click Choose Source or Choose Destination, and pick the folder again. Chronoframe will store a fresh bookmark and the folder will reopen automatically next time."
                ),
                Item(
                    id: "file-failed",
                    question: "What happens when a file cannot be copied?",
                    answer: "The error is recorded in the Issues tab with the file path and the reason, and the run continues with the remaining files. Nothing is silently dropped — every file is either copied, marked already-there, logged as a duplicate, or listed as an issue."
                ),
            ]
        ),
        Section(
            id: "after-a-run",
            title: "After a run",
            items: [
                Item(
                    id: "find-report-logs",
                    question: "Where can I find the report and logs?",
                    answer: "The Run workspace has three buttons under Artifacts: Open Destination reveals the organized folder in Finder, Open Report opens a CSV detailing every planned and copied file, and Open Logs opens the folder containing the full console log for the run. Reports and logs are kept per-run, so older runs remain inspectable."
                ),
                Item(
                    id: "nothing-to-copy",
                    question: "The result said \"Destination already up to date\" — is that bad?",
                    answer: "No, that is a success. Chronoframe looked at your Source and the Destination, compared them, and found nothing new to copy. This is the expected outcome when you run the same configuration twice in a row."
                ),
            ]
        ),
    ]
}
