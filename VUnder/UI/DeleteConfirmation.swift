import UIKit

enum DeleteConfirmation {
    @MainActor
    static func present(track: Track, from presenter: UIViewController, onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: "Delete \"\(track.artist) - \(track.title)\" from my music?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in onConfirm() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presenter.present(alert, animated: true)
    }
}
