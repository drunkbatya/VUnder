import Foundation
import os

final class AppEnvironment {
    let sessionStore: SessionStore
    let api: VKAPIClient
    let oauth: VKOAuthClient
    let authEndpoints: VKAuthEndpoints
    let authFlow: VKAuthFlow
    let settings: AppSettings
    let network: NetworkMonitor
    let database: AppDatabase
    let library: TrackLibrary
    let audioAPI: AudioAPI
    let cache: AudioCache

    init() {
        sessionStore = SessionStore(service: Bundle.main.bundleIdentifier ?? "VUnder")
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpShouldSetCookies = false
        api = VKAPIClient(urlSession: URLSession(configuration: configuration), store: sessionStore)
        oauth = VKOAuthClient(store: sessionStore)
        authEndpoints = VKAuthEndpoints(api: api)
        authFlow = VKAuthFlow(oauth: oauth, endpoints: authEndpoints, store: sessionStore)
        settings = AppSettings()
        network = NetworkMonitor()
        do {
            database = try AppDatabase(path: AppDatabase.defaultPath())
        } catch {
            Log.storage.fault("database open failed: \(error.localizedDescription, privacy: .public)")
            fatalError("database open failed: \(error)")
        }
        library = TrackLibrary(database: database)
        audioAPI = AudioAPI(api: api, settings: settings)
        do {
            cache = try AudioCache(library: library)
        } catch {
            Log.cache.fault("cache directory setup failed: \(error.localizedDescription, privacy: .public)")
            fatalError("cache directory setup failed: \(error)")
        }
    }
}
