import OTAUpdater
import UIKit
import os

final class SettingsViewController: UITableViewController {
    var onSignOut: (() -> Void)?

    private enum Section: Int, CaseIterable {
        case appearance
        case music
        case cache
        case account
        case about
        case debug

        var title: String {
            switch self {
            case .appearance: return "Appearance"
            case .music: return "Music"
            case .cache: return "Cache"
            case .account: return "Account"
            case .about: return "About"
            case .debug: return "Debug"
            }
        }
    }

    private enum ToggleRow: Int, CaseIterable {
        case history
        case cacheEnabled
        case cacheOnlyMine
        case preferHLS

        var title: String {
            switch self {
            case .history: return "Listening history"
            case .cacheEnabled: return "Save played tracks"
            case .cacheOnlyMine: return "Only my tracks"
            case .preferHLS: return "Request HLS streams (v=5.92)"
            }
        }

        static let music: [ToggleRow] = [.history, .cacheEnabled, .cacheOnlyMine]
        static let debug: [ToggleRow] = [.preferHLS]
    }

    private let settings: AppSettings
    private let cache: AudioCache
    private let updater: OTAUpdater
    private var cacheSizeText = "..."

    init(settings: AppSettings, cache: AudioCache, updater: OTAUpdater) {
        self.settings = settings
        self.cache = cache
        self.updater = updater
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView.backgroundColor = Theme.groupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        reloadCacheSize()
    }

    private func reloadCacheSize() {
        Task { [weak self] in
            guard let self else { return }
            let size = await cache.totalSize()
            cacheSizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            tableView.reloadSections(IndexSet(integer: Section.cache.rawValue), with: .none)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .appearance: return Appearance.allCases.count
        case .music: return ToggleRow.music.count
        case .cache: return 2
        case .account: return 1
        case .about: return 2
        case .debug: return ToggleRow.debug.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        switch Section(rawValue: indexPath.section)! {
        case .appearance:
            let appearance = Appearance.allCases[indexPath.row]
            content.text = appearance.title
            cell.accessoryType = settings.appearance == appearance ? .checkmark : .none
        case .music, .debug:
            let row = (Section(rawValue: indexPath.section) == .music ? ToggleRow.music : ToggleRow.debug)[indexPath.row]
            content.text = row.title
            let toggle = UISwitch()
            toggle.isOn = value(for: row)
            toggle.tag = row.rawValue
            toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .cache:
            if indexPath.row == 0 {
                content.text = "Saved tracks size"
                content.secondaryText = cacheSizeText
                cell.selectionStyle = .none
            } else {
                content.text = "Remove all saved tracks"
                content.textProperties.color = .systemRed
            }
        case .account:
            content.text = "Sign out"
            content.textProperties.color = .systemRed
        case .about:
            if indexPath.row == 0 {
                content.text = "Version"
                content.secondaryText = SettingsViewController.versionText
                cell.selectionStyle = .none
            } else {
                content.text = "Check for updates"
            }
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .appearance:
            settings.appearance = Appearance.allCases[indexPath.row]
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        case .music, .debug:
            break
        case .cache:
            if indexPath.row == 1 {
                confirm(title: "Remove all saved tracks?", action: "Remove") { [weak self] in
                    guard let self else { return }
                    Task {
                        await self.cache.clear()
                        self.reloadCacheSize()
                    }
                }
            }
        case .account:
            confirm(title: "Sign out?", action: "Sign out") { [weak self] in
                self?.onSignOut?()
            }
        case .about:
            if indexPath.row == 1 {
                Log.app.info("manual update check")
                updater.checkNow(from: self)
            }
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func value(for row: ToggleRow) -> Bool {
        switch row {
        case .history: return settings.historyEnabled
        case .cacheEnabled: return settings.cacheEnabled
        case .cacheOnlyMine: return settings.cacheOnlyMine
        case .preferHLS: return settings.preferHLS
        }
    }

    @objc private func toggleChanged(_ toggle: UISwitch) {
        guard let row = ToggleRow(rawValue: toggle.tag) else { return }
        Log.app.info("setting \(row.title, privacy: .public) = \(toggle.isOn, privacy: .public)")
        switch row {
        case .history: settings.historyEnabled = toggle.isOn
        case .cacheEnabled: settings.cacheEnabled = toggle.isOn
        case .cacheOnlyMine: settings.cacheOnlyMine = toggle.isOn
        case .preferHLS: settings.preferHLS = toggle.isOn
        }
    }

    private func confirm(title: String, action: String, handler: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: action, style: .destructive) { _ in handler() })
        present(alert, animated: true)
    }
}
