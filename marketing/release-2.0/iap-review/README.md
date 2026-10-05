# IAP review screenshot

`Chronoframe-Unlock-Review.jpg` is a native 1440×900 screenshot of the real production UnlockSheet after the price-label layout fix. It is review-only, separate from the seven public listing screenshots.

This is an isolated developer test-state capture, not the signed release app or a real purchase. `CaptureApp.swift` supplies the exact configured US product name/price through the existing StoreKitClient seam. Purchase returns userCancelled, restore does nothing, and no live StoreKit request is made. Metadata matches `ui/Chronoframe.storekit` and the inspected App Store Connect IAP; other storefront prices remain StoreKit-localized in production.

To reproduce, create a temporary Swift package depending on the local `ui` package's ChronoframeCore and ChronoframeAppCore products. Copy `CaptureApp.swift` plus the **unchanged current** `ui/Sources/ChronoframeApp/Views/Purchase/UnlockSheet.swift` and `ui/Sources/ChronoframeApp/App/DesignTokens.swift` into its executable target. Build with the current Xcode toolchain, wrap as a separate ad hoc macOS app, open it and capture its native window. The 720×422-point content plus 28-point titlebar yields 1440×900 at 2×. Verify actual dimensions and visible price. Source hashes/environment are recorded in `capture-provenance.json`.

Disclose this developer test-state provenance in IAP review notes. Upload only after specific confirmation; do not claim production purchase/restore passed based on this image.

The native capture returns JPEG bytes. The `.jpg` extension matches the actual encoding; only the filename was corrected after Apple rejected a `.png` extension. The image bytes and recorded hash are unchanged.
