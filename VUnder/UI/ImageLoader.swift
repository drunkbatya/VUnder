import UIKit

final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    var localCoverURL: (@Sendable (Track) -> URL?)?

    private let cache = NSCache<NSString, UIImage>()

    func cover(for track: Track) async -> UIImage? {
        let key = track.storageID as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let local = localCoverURL?(track), let image = UIImage(contentsOfFile: local.path) {
            cache.setObject(image, forKey: key)
            return image
        }
        guard let url = track.coverURL.flatMap(URL.init) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
