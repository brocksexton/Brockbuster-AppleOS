import SwiftUI

/// Global design tokens and reusable view modifiers for the Brockbuster app.  This
/// file encapsulates colour definitions, type styles and custom button styles so
/// that the look and feel remains consistent across platforms.  The palette
/// deliberately references the iconic Blockbuster colours—deep blue and warm
/// gold—while taking cues from Apple's modern system designs (e.g. tinted
/// materials, rounded corners and dynamic type).
struct BrockbusterTheme {
    // MARK: - Colours
    // Primary brand colours.  These values were chosen to evoke the retro
    // Blockbuster aesthetic while remaining accessible and modern.
    static let brockBlue = Color(red: 3.0/255.0, green: 51.0/255.0, blue: 156.0/255.0)
    static let brockGold = Color(red: 245.0/255.0, green: 197.0/255.0, blue: 24.0/255.0)
    static let brockDark = Color(red: 14.0/255.0, green: 16.0/255.0, blue: 33.0/255.0)
    static let brockLight = Color(red: 229.0/255.0, green: 230.0/255.0, blue: 233.0/255.0)

    // Text colours.  Use light colours to ensure readability on dark backgrounds.  The
    // primary text colour is bright and the secondary is slightly subdued.
    static let textPrimary = brockLight
    static let textSecondary = brockLight.opacity(0.8)

    // MARK: - Convenience aliases (used by several views)
    /// Primary "ticket" accent used for buttons, chevrons, and highlights.
    static let ticketYellow = brockGold

    /// Standard app background gradient.
    static let Background = LinearGradient(
        gradient: Gradient(colors: [brockDark, brockBlue]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Typography
    struct Fonts {
        /// The app's display typeface for large titles.  Uses SF Pro Rounded when
        /// available, falling back to the system font.
        static var largeTitle: Font {
            #if os(macOS)
            return .system(size: 32, weight: .bold, design: .rounded)
            #else
            return .system(.largeTitle, design: .rounded).bold()
            #endif
        }

        /// Title font for section headers
        static var title: Font {
            .system(size: 24, weight: .semibold, design: .rounded)
        }

        /// Body font for regular text
        static var body: Font {
            .system(size: 16, weight: .regular, design: .rounded)
        }
    }

    // MARK: - Button Styles
    /// A button style resembling a golden ticket.  Applies the brockGold colour,
    /// rounded corners and subtle shadow.  When pressed the button darkens
    /// slightly and scales down to give tactile feedback.
    struct TicketButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(BrockbusterTheme.brockGold)
                .foregroundColor(BrockbusterTheme.brockDark)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    // MARK: - View Modifiers
    /// A modifier that applies a liquid glass effect using system materials.  On
    /// iOS/iPadOS/tvOS the system provides `Material` which automatically
    /// adapts to dark mode and vibrancy.  On macOS we emulate a similar effect
    /// using a translucent background and blur.
    struct LiquidGlass: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(
                    Group {
                        #if os(macOS)
                        VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        #else
                        // Use Apple’s new ultra thin material for a blurred glass look
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                        #endif
                    }
                )
        }
    }
}

// MARK: - VisualEffectView for macOS
// On macOS `Material` is not available outside of Catalyst, so we bridge
// NSVisualEffectView into SwiftUI via this representable.  This is used in
// BrockbusterTheme.LiquidGlass to simulate the frosted glass look.
#if os(macOS)
import AppKit
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
#endif

// Convenience extension to apply liquid glass effect
extension View {
    func liquidGlass() -> some View {
        modifier(BrockbusterTheme.LiquidGlass())
    }
}
