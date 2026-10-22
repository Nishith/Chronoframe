import ChronoframeAppCore
import ChronoframeCore
import Combine
import XCTest
@testable import ChronoframeApp

@MainActor
final class SettingsUnlockSafetyTests: XCTestCase {
    private enum SettingsAction: CaseIterable {
        case purchase, sheetRestore, licenseRestore
    }

    func testDismissedRefusalCannotRetryAfterVoluntaryPurchaseOrRestore() async {
        for mode: RunMode in [.preview, .transfer] {
            for action in SettingsAction.allCases {
                let harness = AppStateHarness()
                let entitlementStore = UITestAppStateFactory.make(scenario: .settingsLicense).entitlementStore
                let state = harness.makeAppState(performInitialBootstrap: false, entitlementStore: entitlementStore)
                await refuse(mode, harness: harness)
                XCTAssertNotNil(state.unlockRefusal)

                // Both windows observe this publication. The refusal must
                // already be gone when ownership changes, regardless of
                // which window's onChange runs first.
                var observedUnlock = false
                let observation = entitlementStore.$state.sink { entitlement in
                    if entitlement.isUnlocked {
                        observedUnlock = true
                        XCTAssertNil(state.unlockRefusal)
                    }
                }

                // Exercise the actions wired by the actual License view,
                // including Restore both on the pane and in its sheet.
                let license = LicenseSettingsTab(appState: state, entitlementStore: entitlementStore)
                await entitlementStore.loadProduct()
                switch action {
                case .purchase:
                    await license.purchaseSheet.purchase()
                case .sheetRestore:
                    await license.purchaseSheet.restorePurchases()
                case .licenseRestore:
                    await license.restorePurchases()
                }
                XCTAssertTrue(entitlementStore.state.isUnlocked)
                XCTAssertTrue(observedUnlock)
                observation.cancel()
                XCTAssertNil(state.unlockRefusal)
                XCTAssertNil(state.offeredFreeTestBatch)

                // Simulate an onUnlocked Task already queued by that sheet.
                await state.retryAfterUnlock()
                XCTAssertEqual(harness.engine.preflightConfigurations.count, 1)
                XCTAssertTrue(harness.engine.startConfigurations.isEmpty)
                XCTAssertTrue(harness.engine.resumeConfigurations.isEmpty)
                XCTAssertNil(harness.runSessionStore.prompt)
                XCTAssertNil(harness.runSessionStore.summary)
                XCTAssertFalse(harness.deduplicateSessionStore.isWorking)
            }
        }
    }

    func testVoluntaryLicenseUnlockClearsDedupeRefusalWithoutCommittingAgain() async {
        for action in SettingsAction.allCases {
            let harness = AppStateHarness()
            let entitlementStore = UITestAppStateFactory.make(scenario: .settingsLicense).entitlementStore
            let state = harness.makeAppState(performInitialBootstrap: false, entitlementStore: entitlementStore)
            let members = [
                PhotoCandidate(path: "/tmp/dest/keep.jpg", size: 20, modificationTime: 0),
                PhotoCandidate(path: "/tmp/dest/delete.jpg", size: 20, modificationTime: 0)
            ]
            let cluster = DuplicateCluster(kind: .exactDuplicate, members: members,
                suggestedKeeperIDs: [members[0].id], bytesIfPruned: 20)
            harness.deduplicateEngine.clustersToEmit = [cluster]
            harness.deduplicateEngine.commitError = TrialAuthorizationError(
                refusal: .allowanceSpent(TrialRefusal(meter: .dedupe, requested: 1, remaining: 0))
            )
            let configuration = DeduplicateConfiguration(destinationPath: "/tmp/dest")
            harness.deduplicateSessionStore.startScan(configuration: configuration)
            let ready = await waitForCondition { harness.deduplicateSessionStore.status == .readyToReview }
            XCTAssertTrue(ready)
            harness.deduplicateSessionStore.acceptSuggestionsForCluster(cluster)
            harness.deduplicateSessionStore.commitReviewed(configuration: configuration)
            let refused = await waitForCondition { state.unlockRefusal != nil }
            XCTAssertTrue(refused)

            var observedUnlock = false
            let observation = entitlementStore.$state.sink { entitlement in
                if entitlement.isUnlocked {
                    observedUnlock = true
                    XCTAssertNil(state.unlockRefusal)
                }
            }
            let license = LicenseSettingsTab(appState: state, entitlementStore: entitlementStore)
            await entitlementStore.loadProduct()
            switch action {
            case .purchase: await license.purchaseSheet.purchase()
            case .sheetRestore: await license.purchaseSheet.restorePurchases()
            case .licenseRestore: await license.restorePurchases()
            }
            XCTAssertTrue(observedUnlock)
            observation.cancel()
            await state.retryAfterUnlock()
            XCTAssertNil(state.unlockRefusal)
            XCTAssertEqual(harness.deduplicateEngine.commitCallCount, 1)
            XCTAssertTrue(harness.deduplicateSessionStore.hasPausedReview)
            XCTAssertEqual(harness.deduplicateSessionStore.clusters.map(\.id), [cluster.id])
            XCTAssertTrue(harness.engine.preflightConfigurations.isEmpty)
            XCTAssertTrue(harness.engine.startConfigurations.isEmpty)
        }
    }

    func testOperationUnlockStillRetriesAnActiveRefusalFromPreflight() async {
        for mode: RunMode in [.preview, .transfer] {
            let harness = AppStateHarness()
            let state = harness.makeAppState(performInitialBootstrap: false)
            await refuse(mode, harness: harness)
            XCTAssertNotNil(state.unlockRefusal)
            harness.engine.preflightResult = .success(RunPreflight(
                configuration: configuration(mode),
                resolvedSourcePath: "/tmp/source", resolvedDestinationPath: "/tmp/destination"
            ))

            await state.retryAfterUnlock()

            XCTAssertNil(state.unlockRefusal)
            XCTAssertEqual(harness.engine.preflightConfigurations.count, 2)
            XCTAssertEqual(harness.engine.preflightConfigurations.last?.mode, mode)
            if mode == .transfer {
                XCTAssertEqual(harness.runSessionStore.prompt?.kind, .confirmTransfer)
            } else {
                let started = await waitForCondition { harness.engine.startConfigurations.count == 1 }
                XCTAssertTrue(started)
            }
        }
    }

    private func refuse(_ mode: RunMode, harness: AppStateHarness) async {
        harness.setupStore.sourcePath = "/tmp/source"
        harness.setupStore.destinationPath = "/tmp/destination"
        harness.engine.preflightResult = .failure(TrialAuthorizationError(
            refusal: .allowanceSpent(TrialRefusal(meter: .organize, requested: 501, remaining: 0))
        ))
        await harness.runSessionStore.requestRun(mode: mode, configuration: configuration(mode))
    }

    private func configuration(_ mode: RunMode) -> RunConfiguration {
        RunConfiguration(mode: mode, sourcePath: "/tmp/source", destinationPath: "/tmp/destination")
    }
}
