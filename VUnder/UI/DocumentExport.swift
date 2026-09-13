import UIKit

@MainActor
final class DocumentExport: NSObject, UIDocumentPickerDelegate {
    private static var active: Set<DocumentExport> = []
    private let fileURL: URL

    private init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func present(fileURL: URL, from presenter: UIViewController) {
        let export = DocumentExport(fileURL: fileURL)
        active.insert(export)
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = export
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish()
    }

    private func finish() {
        try? FileManager.default.removeItem(at: fileURL)
        DocumentExport.active.remove(self)
    }
}
