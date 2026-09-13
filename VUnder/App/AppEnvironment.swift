import Foundation

final class AppEnvironment {
    let sessionStore: SessionStore
    let api: VKAPIClient
    let oauth: VKOAuthClient
    let authEndpoints: VKAuthEndpoints
    let authFlow: VKAuthFlow
    let appearance: AppearanceSettings

    init() {
        sessionStore = SessionStore(service: Bundle.main.bundleIdentifier ?? "VUnder")
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpShouldSetCookies = false
        api = VKAPIClient(urlSession: URLSession(configuration: configuration), store: sessionStore)
        oauth = VKOAuthClient(store: sessionStore)
        authEndpoints = VKAuthEndpoints(api: api)
        authFlow = VKAuthFlow(oauth: oauth, endpoints: authEndpoints, store: sessionStore)
        appearance = AppearanceSettings()
    }
}
