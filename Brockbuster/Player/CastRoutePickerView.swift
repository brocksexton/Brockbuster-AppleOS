import SwiftUI

/// A lightweight system route picker.
///
/// On iOS/iPadOS this presents the standard AirPlay / system output routes.
/// On tvOS this is intentionally unavailable (Apple does not support the same
/// route picker UI there).
#if canImport(UIKit) && !os(tvOS)
import UIKit
import AVKit

struct CastRoutePickerView: UIViewRepresentable {
    var activeTintColor: UIColor = .white
    var tintColor: UIColor = UIColor.white.withAlphaComponent(0.85)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.activeTintColor = activeTintColor
        view.tintColor = tintColor
        view.prioritizesVideoDevices = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = activeTintColor
        uiView.tintColor = tintColor
    }
}

#else

/// tvOS fallback so shared code can compile.
struct CastRoutePickerView: View {
    var body: some View { EmptyView() }
}

#endif
