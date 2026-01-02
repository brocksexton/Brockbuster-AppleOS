import SwiftUI
import ImageIO

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

/// A lightweight, aggressively cached replacement for `AsyncImage`.
///
/// Notes:
/// - Uses an in-memory `NSCache` for decoded images.
/// - Leverages `URLCache` implicitly via `URLSession`.
/// - Optionally downsamples images off the main thread to reduce decode cost.
struct BBCachedAsyncImage: View {

    enum Phase {
        case empty
        case success(Image)
        case failure(Error)
    }

    private let url: URL?
    private let targetSize: CGSize?
    private let scale: CGFloat
    private let transaction: Transaction
    private let content: (Phase) -> AnyView

    @State private var phase: Phase = .empty
    @State private var task: Task<Void, Never>?

    /// Generic initializer that type-erases `Content` to `AnyView`.
    /// This avoids “Generic parameter 'Content' could not be inferred” errors at call sites
    /// while keeping an `AsyncImage`-style API.
    init<Content: View>(
        url: URL?,
        targetSize: CGSize? = nil,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (Phase) -> Content
    ) {
        self.url = url
        self.targetSize = targetSize
        self.scale = scale
        self.transaction = transaction
        self.content = { phase in AnyView(content(phase)) }
    }

    var body: some View {
        content(phase)
            .onAppear { startIfNeeded() }
            .onChange(of: url) { _ in resetAndStart() }
            .onDisappear { task?.cancel() }
    }

    private func resetAndStart() {
        task?.cancel()
        phase = .empty
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard task == nil else { return }
        guard let url else {
            phase = .failure(NSError(domain: "BBCachedAsyncImage", code: -1))
            return
        }

        // In-memory decoded cache first
        if let cached = BBCachedImageStore.shared.image(for: url.absoluteString) {
            withTransaction(transaction) {
                phase = .success(Image(platformImage: cached))
            }
            return
        }

        task = Task(priority: .utility) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                let decoded: PlatformImage?
                if let targetSize, let downsampled = BBCachedImageDecoder.downsample(data: data, to: targetSize, scale: scale) {
                    decoded = downsampled
                } else {
                    decoded = PlatformImage(data: data)
                }

                guard let decoded else {
                    throw NSError(domain: "BBCachedAsyncImage", code: -2)
                }

                BBCachedImageStore.shared.insert(decoded, for: url.absoluteString)

                await MainActor.run {
                    withTransaction(transaction) {
                        phase = .success(Image(platformImage: decoded))
                    }
                }
            } catch {
                await MainActor.run {
                    withTransaction(transaction) {
                        phase = .failure(error)
                    }
                }
            }

            await MainActor.run { task = nil }
        }
    }
}

// MARK: - Cache

final class BBCachedImageStore {
    static let shared = BBCachedImageStore()

    private let cache = NSCache<NSString, PlatformImage>()

    private init() {
        cache.countLimit = 600
        cache.totalCostLimit = 60 * 1024 * 1024 // ~60MB
    }

    func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: PlatformImage, for key: String) {
        #if canImport(UIKit)
        let cost = image.pngData()?.count ?? 1
        #else
        let cost = 1
        #endif
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

// MARK: - Decoder / Downsampling

enum BBCachedImageDecoder {
    static func downsample(data: Data, to pointSize: CGSize, scale: CGFloat) -> PlatformImage? {
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale

        return data.withUnsafeBytes { rawBuffer -> PlatformImage? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }

            let cfData = CFDataCreate(kCFAllocatorDefault, baseAddress.assumingMemoryBound(to: UInt8.self), data.count)
            guard let cfData else { return nil }

            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ]

            guard let source = CGImageSourceCreateWithData(cfData, options as CFDictionary) else { return nil }

            let downsampleOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxDimensionInPixels)
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else { return nil }

            #if canImport(UIKit)
            return UIImage(cgImage: cgImage)
            #elseif canImport(AppKit)
            return NSImage(cgImage: cgImage, size: .zero)
            #else
            return nil
            #endif
        }
    }
}

// MARK: - Platform Image -> SwiftUI Image bridge

private extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self = Image(uiImage: platformImage)
        #elseif canImport(AppKit)
        self = Image(nsImage: platformImage)
        #else
        self = Image(systemName: "photo")
        #endif
    }
}
