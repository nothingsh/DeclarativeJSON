import Combine
import UIKit

/// The images loaded by `ImageLoader.urlSession`, shared by every page.
@MainActor
private enum ImageCache {
    static let images = NSCache<NSURL, UIImage>()
}

/// Loads the image of an `image` node's `url`.
///
/// `load` starts loading and calls `completion` on the main actor with the
/// image, or with nil when it could not be loaded. The view cancels the
/// returned token when the URL changes or the view goes away, and ignores a
/// completion that comes after that.
///
/// ```swift
/// let loader = ImageLoader { url, completion in
///     let request = imagePipeline.load(url) { image in completion(image) }
///     return AnyCancellable { request.cancel() }
/// }
/// ```
public struct ImageLoader: Sendable {
    public typealias Load = @MainActor @Sendable (
        _ url: URL,
        _ completion: @escaping @MainActor @Sendable (UIImage?) -> Void
    ) -> AnyCancellable

    let load: Load

    public init(_ load: @escaping Load) {
        self.load = load
    }

    /// Loads with `URLSession.shared` and keeps the images in memory.
    public static var urlSession: ImageLoader {
        ImageLoader { url, completion in
            if let image = ImageCache.images.object(forKey: url as NSURL) {
                completion(image)
                return AnyCancellable {}
            }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                Task { @MainActor in
                    let image = data.flatMap { UIImage(data: $0) }
                    if let image {
                        ImageCache.images.setObject(image, forKey: url as NSURL)
                    }
                    completion(image)
                }
            }
            task.resume()
            return AnyCancellable { task.cancel() }
        }
    }
}
