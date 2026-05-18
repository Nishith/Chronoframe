import ChronoframeCLIKit
import ChronoframeCore
import XCTest

final class CLIParserTests: XCTestCase {
    func testParsesTransferOptions() throws {
        let options = try CLIParser.parse([
            "--source", "/photos/in",
            "--dest", "/photos/out",
            "--skip-verify",
            "--workers", "4",
            "--folder-structure", "YYYY/MM",
            "--json",
            "--yes",
        ])

        XCTAssertEqual(options.sourcePath, "/photos/in")
        XCTAssertEqual(options.destinationPath, "/photos/out")
        XCTAssertFalse(options.verifyCopies)
        XCTAssertEqual(options.workerCount, 4)
        XCTAssertEqual(options.folderStructure, .yyyyMM)
        XCTAssertTrue(options.jsonOutput)
        XCTAssertTrue(options.assumeYes)
        XCTAssertEqual(options.mode, .transfer)
    }

    func testParsesProfilePreview() throws {
        let options = try CLIParser.parse(["--profile", "travel", "--dry-run"])

        XCTAssertEqual(options.profileName, "travel")
        XCTAssertTrue(options.dryRun)
        XCTAssertEqual(options.mode, .preview)
    }

    func testParsesDefaultWorkerCountWithoutExplicitWorkerFlag() throws {
        let options = try CLIParser.parse(["--source", "/photos/in", "--dest", "/photos/out"])

        XCTAssertEqual(options.workerCount, CLIOptions.defaultWorkerCount)
    }

    func testParsesRevertWithBoundaryOverride() throws {
        let options = try CLIParser.parse(["--revert", "/tmp/receipt.json", "--dest", "/tmp/destination"])

        XCTAssertEqual(options.revertReceiptPath, "/tmp/receipt.json")
        XCTAssertEqual(options.destinationPath, "/tmp/destination")
        XCTAssertEqual(options.mode, .revert)
    }

    func testRejectsNormalRunWithoutSourceDestinationOrProfile() {
        XCTAssertThrowsError(try CLIParser.parse(["--dry-run"])) { error in
            XCTAssertEqual(error as? CLIError, .usage("Provide --source and --dest, or use --profile."))
        }
    }

    func testRejectsUnsupportedFolderStructure() {
        XCTAssertThrowsError(
            try CLIParser.parse(["--source", "/in", "--dest", "/out", "--folder-structure", "Month"])
        ) { error in
            XCTAssertEqual(error as? CLIError, .usage("Unsupported folder structure: Month."))
        }
    }

    func testRejectsRevertWithNormalRunOptions() {
        XCTAssertThrowsError(
            try CLIParser.parse(["--revert", "/tmp/receipt.json", "--source", "/in"])
        ) { error in
            guard case let .usage(message) = error as? CLIError else {
                XCTFail("Expected CLIError.usage, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("--revert"))
            XCTAssertTrue(message.contains("--source"))
        }
    }

    func testRejectsRevertWithSkipVerifyOrFolderStructure() {
        // Regression for PHASE2_FINDINGS.md NEW13: the old guard had an
        // explicit deny-list that missed --skip-verify and
        // --folder-structure, so the revert path silently ignored them.
        XCTAssertThrowsError(
            try CLIParser.parse(["--revert", "/tmp/r.json", "--skip-verify"])
        ) { error in
            guard case let .usage(message) = error as? CLIError else {
                XCTFail("Expected CLIError.usage, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("--skip-verify"))
        }
        XCTAssertThrowsError(
            try CLIParser.parse(["--revert", "/tmp/r.json", "--folder-structure", "Flat"])
        ) { error in
            guard case let .usage(message) = error as? CLIError else {
                XCTFail("Expected CLIError.usage, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("--folder-structure"))
        }
    }

    // MARK: - PHASE2_FINDINGS regressions

    /// NEW11: paths and identifiers that legitimately start with `-`
    /// must be accepted as values rather than misreported as
    /// "Missing value for …".
    func testAcceptsValuesThatStartWithDash() throws {
        let options = try CLIParser.parse([
            "--source", "/Volumes/-Backup",
            "--dest", "/dest",
            "--yes",
        ])
        XCTAssertEqual(options.sourcePath, "/Volumes/-Backup")
        XCTAssertEqual(options.destinationPath, "/dest")
    }

    /// NEW11: when the next argument is itself a known flag, we DO
    /// still report a missing value rather than silently consuming the
    /// next flag as a path.
    func testRejectsMissingValueWhenNextArgIsAnotherKnownFlag() {
        XCTAssertThrowsError(
            try CLIParser.parse(["--source", "--dest", "/dest"])
        ) { error in
            guard case let .usage(message) = error as? CLIError else {
                XCTFail("Expected CLIError.usage, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("--source"))
        }
    }

    /// NEW11: `--flag=value` form supports values that look like flags.
    func testSupportsEqualsSyntaxForOptionsWithValues() throws {
        let options = try CLIParser.parse([
            "--source=/Volumes/-Photos",
            "--dest=/Volumes/dest",
            "--workers=2",
            "--yes",
        ])
        XCTAssertEqual(options.sourcePath, "/Volumes/-Photos")
        XCTAssertEqual(options.destinationPath, "/Volumes/dest")
        XCTAssertEqual(options.workerCount, 2)
    }

    /// NEW14: tilde-prefixed paths must expand even when the CLI is
    /// invoked outside a shell (launchd, the Codex environment).
    func testExpandsTildePathsAfterParse() throws {
        let options = try CLIParser.parse([
            "--source", "~/Pictures/source",
            "--dest", "~/Pictures/dest",
            "--yes",
        ])
        let home = NSString(string: "~/Pictures/source").expandingTildeInPath
        XCTAssertEqual(options.sourcePath, home)
        XCTAssertFalse(options.destinationPath?.hasPrefix("~") ?? true)
    }

    /// NEW14: filenames must be NFC-normalized so destinationBoundary
    /// comparisons agree across runs.
    func testNormalizesNFDInputToNFC() throws {
        // `é` as the NFD pair `e` + U+0301.
        let nfd = "/tmp/cafe\u{0301}"
        let options = try CLIParser.parse([
            "--source", nfd,
            "--dest", "/dest",
            "--yes",
        ])
        XCTAssertEqual(options.sourcePath, "/tmp/café")
    }
}
