import SwiftUI

/// A container view that wraps its content in a rounded, translucent card.  The
/// card uses the `liquidGlass` modifier from the design system and adds a
/// coloured stroke and shadow to subtly delineate it from the background.  Use
/// `GlassCard` to group related controls such as forms or loading states.
struct GlassCard<Content: View>: View {
    private let content: Content
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .background(
                        // Use the design system's liquid glass effect
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BrockbusterTheme.brockBlue.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)
    }
}
