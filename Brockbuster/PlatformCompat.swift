import SwiftUI

// MARK: - Navigation compat

extension View {
    /// tvOS does not support navigationBarTitleDisplayMode
    @ViewBuilder
    func bbNavigationTitleInline() -> some View {
        #if os(tvOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// If you ever need large titles on iOS but not tvOS.
    @ViewBuilder
    func bbNavigationTitleLarge() -> some View {
        #if os(tvOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.large)
        #endif
    }
}

// MARK: - TextField style compat

struct BrockbusterTextFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if os(tvOS)
        // tvOS: RoundedBorderTextFieldStyle / .roundedBorder are unavailable.
        // Use a custom "pill" surface that reads well under focus.
        content
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
            )
        #else
        // iOS/iPadOS/macOS: use the native rounded border style.
        content
            .textFieldStyle(RoundedBorderTextFieldStyle())
        #endif
    }
}

extension View {
    func bbTextFieldStyle() -> some View {
        self.modifier(BrockbusterTextFieldStyle())
    }
}

// MARK: - Optional: control size compat (if you used .controlSize(.large))

extension View {
    @ViewBuilder
    func bbControlSizeLargeIfAvailable() -> some View {
        #if os(tvOS)
        self
        #else
        self.controlSize(.large)
        #endif
    }
}

// MARK: - tvOS focus styling

#if os(tvOS)
private struct BrockbusterTVFocusCardModifier: ViewModifier {
    @FocusState private var isFocused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            // Disable the default oversized tvOS focus halo and draw a focused
            // state that matches Brockbuster's “glass + gold” language.
            .focused($isFocused)
            // `focusEffect(_:)` is not consistently available across SDKs.
            // Using the dedicated modifier avoids build breaks.
            .focusEffectDisabled()
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.30 : 0.18), radius: isFocused ? 16 : 10, x: 0, y: isFocused ? 10 : 6)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isFocused ? BrockbusterTheme.brockGold.opacity(0.95) : .white.opacity(0.08), lineWidth: isFocused ? 3 : 1)
            )
            .zIndex(isFocused ? 1 : 0)
            .animation(.easeInOut(duration: 0.16), value: isFocused)
    }
}

extension View {
    /// Applies a tvOS focus treatment with a modest scale and a gold stroke.
    /// On non-tvOS platforms this is a no-op.
    func bbTVFocusCard(cornerRadius: CGFloat = 22) -> some View {
        self.modifier(BrockbusterTVFocusCardModifier(cornerRadius: cornerRadius))
    }
}
#else
extension View {
    /// Non-tvOS no-op.
    func bbTVFocusCard(cornerRadius: CGFloat = 22) -> some View { self }
}
#endif


