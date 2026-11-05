import Foundation

struct RegistrationResponse: Decodable, Sendable {
    let success: Bool
    let app_data: String?

    var contentURL: String? {
        guard success, let value = app_data, ContentURL.validated(value) != nil else { return nil }
        return value
    }
}

struct RegistrationRequest: Codable, Sendable {
    let bundle: String
    let push_token: String
    let advertising_id: String
    let appsflyer_id: String
}

/// Registers this install once per launch and persists the selected app destination.
@MainActor
final class RegistrationClient {
    static let shared: RegistrationClient = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--browser-ui-test"),
           let value = ProcessInfo.processInfo.environment["BROWSER_TEST_REGISTRATION_URL"],
           let url = URL(string: value), url.scheme == "http", url.host == "127.0.0.1" {
            return RegistrationClient(endpoint: value)
        }
        #endif
        return RegistrationClient()
    }()
    private let session: URLSession
    private let dataCache: LaunchPreferences
    private let endpoint: String?
    private let registrationGate = RegistrationGate()

    init(session: URLSession? = nil, dataCache: LaunchPreferences = .shared, endpoint: String? = nil) {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = AppEndpoints.networkTimeout
        configuration.timeoutIntervalForResource = AppEndpoints.networkTimeout
        self.session = session ?? URLSession(configuration: configuration)
        self.dataCache = dataCache
        self.endpoint = endpoint
    }

    func performRegistration(
        pushToken: String = "", advertisingId: String = "", appsflyerId: String = "",
        completion: @escaping (LaunchMode, String?) -> Void
    ) {
        guard registrationGate.begin(completion) else { return }
        BrowserSession.restore()
        if dataCache.hasContentURL, let cached = dataCache.contentURL {
            registrationGate.finish(.webContent, cached)
            return
        }
        if dataCache.wasRegistrationAttempted {
            registrationGate.finish(.nativeInterface, nil)
            return
        }
        guard let url = ContentURL.validated(endpoint ?? AppEndpoints.registrationEndpoint) else {
            registrationGate.finish(.nativeInterface, nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppEndpoints.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        let body = RegistrationRequest(bundle: Bundle.main.bundleIdentifier ?? "",
                                       push_token: pushToken, advertising_id: advertisingId,
                                       appsflyer_id: appsflyerId)
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            registrationGate.finish(.nativeInterface, nil)
            return
        }
        Task {
            do {
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                BrowserSession.store(response: http)
                BrowserSession.persist()
                guard let http, (200..<300).contains(http.statusCode) else {
                    finishWithCache()
                    return
                }
                let registration = try JSONDecoder().decode(RegistrationResponse.self, from: data)
                if let url = registration.contentURL {
                    dataCache.saveContentURL(url)
                    registrationGate.finish(.webContent, url)
                } else {
                    dataCache.wasRegistrationAttempted = true
                    finishWithCache()
                }
            } catch {
                // A transport/decoding failure must not permanently select the native route.
                finishWithCache()
            }
        }
    }

    private func finishWithCache() {
        if dataCache.hasContentURL, let cached = dataCache.contentURL {
            registrationGate.finish(.webContent, cached)
        } else {
            registrationGate.finish(.nativeInterface, nil)
        }
    }

}

@MainActor
final class RegistrationGate {
    private var started = false
    private var finished = false
    private var result: (LaunchMode, String?)?
    private var waiters: [(LaunchMode, String?) -> Void] = []

    /// `true` only for the first caller in this process. Later callers share that result.
    func begin(_ completion: @escaping (LaunchMode, String?) -> Void) -> Bool {
        if let result, finished {
            let replay = result
            completion(replay.0, replay.1)
            return false
        }
        waiters.append(completion)
        if started { return false }
        started = true
        return true
    }

    func finish(_ mode: LaunchMode, _ url: String?) {
        finished = true
        result = (mode, url)
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter(mode, url)
        }
    }
}
