import UIKit

final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url.absoluteString as NSString) {
            return cached
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: url.absoluteString as NSString)
        return image
    }
}
