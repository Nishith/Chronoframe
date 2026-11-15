#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import SwiftUI

/// Two lanes over the review list: groups Chronoframe can accept together
/// ("safe") and groups that need a look ("check"). A pure view over the store's
/// clusters; it decides nothing about what is accepted.
///
/// A group counts as safe only when `DeduplicationPlanner.isAutomaticCommitEligible`
/// says so, so a high-confidence group the planner refuses to auto-select
/// (for example a perceptual video match) lands in the check lane.
struct DeduplicateReviewLanes: Equatable {
    /// Eligible and not yet reviewed.
    let safeGroupCount: Int
    /// Not eligible and not yet reviewed.
    let checkGroupCount: Int
    let reviewedGroupCount: Int

    init(
        clusters: [DuplicateCluster],
        reviewedIDs: Set<DuplicateCluster.ID>,
        isEligible: (DuplicateCluster) -> Bool = DeduplicationPlanner.isAutomaticCommitEligible
    ) {
        var safe = 0
        var check = 0
        var reviewed = 0
        for cluster in clusters {
            if reviewedIDs.contains(cluster.id) {
                reviewed += 1
            } else if isEligible(cluster) {
                safe += 1
            } else {
                check += 1
            }
        }
        safeGroupCount = safe
        checkGroupCount = check
        reviewedGroupCount = reviewed
    }

    var safeText: String? {
        switch safeGroupCount {
        case ..<1: return nil
        case 1: return "1 group is a safe match. Accept it now."
        default: return "\(safeGroupCount.formatted()) groups are safe matches. Accept them together."
        }
    }

    var checkText: String? {
        switch checkGroupCount {
        case ..<1: return nil
        case 1: return "1 group is a look-alike or less certain. Take a look."
        default: return "\(checkGroupCount.formatted()) groups are look-alikes or less certain. Look at each one."
        }
    }

    var doneText: String? {
        guard safeGroupCount == 0, checkGroupCount == 0, reviewedGroupCount > 0 else { return nil }
        return "Every group has been reviewed."
    }

    /// One line for the stacked (narrow) layout, where a two-row bar with
    /// buttons would take the height the photo preview needs.
    var compactText: String? {
        var parts: [String] = []
        if safeGroupCount == 1 {
            parts.append("1 safe match")
        } else if safeGroupCount > 1 {
            parts.append("\(safeGroupCount.formatted()) safe matches")
        }
        if checkGroupCount == 1 {
            parts.append("1 group to check")
        } else if checkGroupCount > 1 {
            parts.append("\(checkGroupCount.formatted()) groups to check")
        }
        // No trailing full stop: the counts above have none either.
        if parts.isEmpty {
            return doneText == nil ? nil : "Every group has been reviewed"
        }
        return parts.joined(separator: " · ")
    }
}

/// Single-row band above the review body. The buttons only forward to the
/// caller: "Accept All Safe" is the store's `acceptAllSuggestions()` and
/// "Quick Review" opens the existing Quick Review sheet.
///
/// In the stacked layout the bar is one line of text with no buttons: the
/// commit footer already has Accept Safe and the Options menu has Quick Review.
struct DeduplicateReviewLanesBar: View {
    let lanes: DeduplicateReviewLanes
    var isCompact = false
    let onAcceptSafe: () -> Void
    let onQuickReview: () -> Void

    var body: some View {
        if isCompact {
            if let text = lanes.compactText {
                VStack(spacing: 0) {
                    Text(verbatim: text)
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        // A minimum, not a fixed height: the label grows with
                        // Dynamic Type and the row grows with it. The divider
                        // below takes the last point.
                        .frame(
                            maxWidth: .infinity,
                            minHeight: DesignTokens.DeduplicateLayout.compactLanesBarMinHeight - 1,
                            alignment: .leading
                        )
                    Divider()
                }
                .background(DesignTokens.ColorSystem.panel)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityIdentifiers.dedupeLanes)
            }
        } else if lanes.safeText != nil || lanes.checkText != nil || lanes.doneText != nil {
            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: DesignTokens.Spacing.lg) {
                        safeLane
                        checkLane
                        doneLane
                    }
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        safeLane
                        checkLane
                        doneLane
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            .background(DesignTokens.ColorSystem.panel)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityIdentifiers.dedupeLanes)
        }
    }

    @ViewBuilder
    private var safeLane: some View {
        if let text = lanes.safeText {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(verbatim: text)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Accept All Safe") {
                    onAcceptSafe()
                }
                .buttonStyle(.borderedMicroDelight)
                .fixedSize()
                .accessibilityIdentifier(AccessibilityIdentifiers.dedupeLanesAcceptSafe)
            }
        }
    }

    @ViewBuilder
    private var checkLane: some View {
        if let text = lanes.checkText {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(verbatim: text)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Quick Review") {
                    onQuickReview()
                }
                .buttonStyle(.borderedMicroDelight)
                .fixedSize()
                .accessibilityIdentifier(AccessibilityIdentifiers.dedupeLanesQuickReview)
            }
        }
    }

    @ViewBuilder
    private var doneLane: some View {
        if let text = lanes.doneText {
            Text(verbatim: text)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
        }
    }
}
