import SwiftUI
import AVFoundation

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// A lightweight `AVPlayerLayer` host for SwiftUI.
///
/// This is the foundation for Brockbuster's custom player chrome. Video is
/// rendered by `AVPlayerLayer`, while all controls are implemented in SwiftUI.
#if os(iOS) || os(tvOS)
struct PlayerSurfaceView: UIViewRepresentable {
    let player: AVPlayer
    var onLayerReady: ((AVPlayerLayer) -> Void)?

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        context.coordinator.bind(layer: view.playerLayer, onLayerReady: onLayerReady)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        context.coordinator.bind(layer: uiView.playerLayer, onLayerReady: onLayerReady)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var didSendLayer = false

        func bind(layer: AVPlayerLayer, onLayerReady: ((AVPlayerLayer) -> Void)?) {
            guard !didSendLayer else { return }
            didSendLayer = true
            onLayerReady?(layer)
        }
    }
}

#endif

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }
}
