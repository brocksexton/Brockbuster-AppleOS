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

