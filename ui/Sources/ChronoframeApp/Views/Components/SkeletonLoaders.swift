import SwiftUI

/// Shimmering placeholder primitive for loading states. A rounded fill with a
/// soft highlight sweeping left-to-right. The sweep is suppressed under Reduce
/// Motion (the static fill alone still reads as "content pending"). Decorative,
/// so hidden from VoiceOver — callers label the surrounding container.
struct SkeletonTile: View {
    var cornerRadius: CGFloat = 10
    /// Stagger index so a row/grid of tiles shimmers in a wave rather than in
    /// lockstep.
    var index: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(DesignTokens.ColorSystem.imageStage)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.16), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.8)
                    .offset(x: animating ? geo.size.width : -geo.size.width)
                }
                .clipShape(shape)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 1.1)
                        .repeatForever(autoreverses: false)
                        .delay(0.08 * Double(index))
                ) {
                    animating = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Staggered skeleton approximating the Library Health card grid while the
/// first scan runs and there is no prior summary to show.
struct HealthDashboardSkeleton: View {
    var rowCount: Int = 4

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12)],
            spacing: 12
        ) {
            ForEach(0..<rowCount, id: \.self) { index in
                SkeletonTile(cornerRadius: DesignTokens.Corner.card, index: index)
                    .frame(height: 96)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checking library health")
    }
}
