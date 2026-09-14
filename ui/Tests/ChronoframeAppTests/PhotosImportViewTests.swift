import ChronoframeAppCore
import XCTest
@testable import ChronoframeApp

@MainActor
final class PhotosImportViewTests: XCTestCase {
    /// The Photos destination shipped as the only detail view without a
    /// navigation title. On macOS the unified toolbar is what insets a
    /// `NavigationSplitView`'s detail column below the window titlebar, so a
    /// destination that publishes neither a title nor a toolbar item leaves the
    /// toolbar empty: the column drew from the top of the window and the
    /// inherited "Chronoframe" window title overlapped the view's own header.
    func testPhotosDestinationPublishesANonEmptyNavigationTitle() {
        XCTAssertFalse(
            PhotosImportView.navigationTitle.trimmingCharacters(in: .whitespaces).isEmpty,
            "An empty navigation title collapses the window toolbar and lets the titlebar overlap the header"
        )
    }

    /// The window title has to name the destination the sidebar row named, not
    /// restate the app name — "Chronoframe" over "Import from Photos" is the
    /// overlap that made the bug visible in the first place.
    func testNavigationTitleMatchesTheSidebarDestination() {
        XCTAssertEqual(PhotosImportView.navigationTitle, SidebarDestination.photos.title)
        XCTAssertNotEqual(PhotosImportView.navigationTitle, "Chronoframe")
    }
}
