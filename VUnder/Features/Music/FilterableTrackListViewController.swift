import UIKit

class FilterableTrackListViewController: TrackListViewController, UISearchBarDelegate {
    let searchBar = UISearchBar()
    private var query = ""

    var allTracks: [Track] = [] {
        didSet {
            applyFilter()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchBar.placeholder = "Filter"
        searchBar.delegate = self
        searchBar.autocapitalizationType = .none
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Theme.background
        pinAboveTable(searchBar)
    }

    override var emptyMessage: String {
        query.isEmpty ? "" : "Nothing matches \"\(query)\""
    }

    private func applyFilter() {
        if query.isEmpty {
            tracks = allTracks
        } else {
            let lowered = query.lowercased()
            tracks = allTracks.filter { $0.matches(lowered) }
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilter()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
