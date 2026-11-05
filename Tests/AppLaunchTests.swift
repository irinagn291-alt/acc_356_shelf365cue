import XCTest
@testable import ShelfCue

final class AppLaunchTests: XCTestCase {
    @MainActor private func cache() -> LaunchPreferences {
        let name = "AppLaunchTests.\(UUID().uuidString)"
        let storage = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return LaunchPreferences(storage: storage)
    }

    @MainActor private func service(_ path: String, cache: LaunchPreferences) -> RegistrationClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RegistrationFixture.self]
        return RegistrationClient(session: URLSession(configuration: config), dataCache: cache,
                              endpoint: "https://logic-test.invalid/\(path)")
    }

    @MainActor private func register(_ service: RegistrationClient) async -> (LaunchMode, String?) {
        await withCheckedContinuation { continuation in
            service.performRegistration { mode, url in continuation.resume(returning: (mode, url)) }
        }
    }

    @MainActor func testAppLaunchUsesSavedNativeDestination() {
        let cache = cache()
        cache.wasRegistrationAttempted = true
        let launch = AppLaunch(registration: service("offline", cache: cache))
        XCTAssertEqual(launch.mode, .loading)
        launch.start()
        XCTAssertEqual(launch.mode, .nativeInterface)
        XCTAssertNil(launch.contentURL)
        launch.start()
        XCTAssertEqual(launch.mode, .nativeInterface)
    }

    @MainActor func testAppLaunchUsesSavedWebDestination() {
        let cache = cache()
        cache.saveContentURL("https://content.example/saved")
        let launch = AppLaunch(registration: service("offline", cache: cache))
        launch.start()
        XCTAssertEqual(launch.mode, .webContent)
        XCTAssertEqual(launch.contentURL, "https://content.example/saved")
    }

    @MainActor func testRegistrationSendsJSONAndCachesContentAcrossServiceInstances() async {
        let cache = cache()
        let first = await register(service("web", cache: cache))
        XCTAssertEqual(first.0, .webContent)
        XCTAssertEqual(first.1, "https://content.example/home")
        XCTAssertTrue(cache.wasRegistrationAttempted)
        let nextLaunch = await register(service("offline", cache: cache))
        XCTAssertEqual(nextLaunch.0, .webContent)
        XCTAssertEqual(nextLaunch.1, first.1)
    }

    @MainActor func testNativeResponseIsRemembered() async {
        for path in ["native", "rejected", "invalid-url"] {
            let cache = cache()
            let result = await register(service(path, cache: cache))
            XCTAssertEqual(result.0, .nativeInterface)
            XCTAssertNil(result.1)
            XCTAssertTrue(cache.wasRegistrationAttempted)
            let next = await register(service("web", cache: cache))
            XCTAssertEqual(next.0, .nativeInterface)
        }
    }

    @MainActor func testTransportServerAndJSONErrorsCanRetryOnNextLaunch() async {
        for path in ["offline", "server-error", "malformed"] {
            let cache = cache()
            let result = await register(service(path, cache: cache))
            XCTAssertEqual(result.0, .nativeInterface)
            XCTAssertFalse(cache.wasRegistrationAttempted)
            let retry = await register(service("web", cache: cache))
            XCTAssertEqual(retry.0, .webContent)
        }
    }

    @MainActor func testGateCoalescesAndReplaysWithoutAnotherRequest() {
        let gate = RegistrationGate()
        var modes: [LaunchMode] = []
        XCTAssertTrue(gate.begin { mode, _ in modes.append(mode) })
        XCTAssertFalse(gate.begin { mode, _ in modes.append(mode) })
        XCTAssertTrue(modes.isEmpty)
        gate.finish(.webContent, "https://example.com")
        XCTAssertFalse(gate.begin { mode, _ in modes.append(mode) })
        XCTAssertEqual(modes, [.webContent, .webContent, .webContent])
    }

    @MainActor func testInvalidCachedURLCannotOpenWebContent() async {
        let cache = cache()
        cache.contentURL = "javascript:alert(1)"
        XCTAssertFalse(cache.hasContentURL)
        let result = await register(service("web", cache: cache))
        XCTAssertEqual(result.0, .webContent)
    }

    @MainActor func testSessionCookieSurvivesRestore() throws {
        let original = UserDefaults.standard.data(forKey: "session_cookies_archive")
        let url = URL(string: "https://cookie-test.invalid/")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Set-Cookie": "logic_test=returning; Path=/; Secure; HttpOnly"])!
        defer {
            for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
            if let original { UserDefaults.standard.set(original, forKey: "session_cookies_archive") }
            else { UserDefaults.standard.removeObject(forKey: "session_cookies_archive") }
        }
        BrowserSession.store(response: response)
        BrowserSession.persist()
        let cookie = try XCTUnwrap(HTTPCookieStorage.shared.cookies(for: url)?.first { $0.name == "logic_test" })
        HTTPCookieStorage.shared.deleteCookie(cookie)
        BrowserSession.restore()
        let restored = try XCTUnwrap(HTTPCookieStorage.shared.cookies(for: url)?.first { $0.name == "logic_test" })
        XCTAssertEqual(restored.value, "returning")
        XCTAssertGreaterThan(try XCTUnwrap(restored.expiresDate), Date())
    }

    func testWebURLValidation() {
        for input in ["", "relative/path", "https://", "file:///private/test", "javascript:alert(1)", "https://user:pass@example.com"] {
            XCTAssertNil(ContentURL.validated(input), input)
        }
        XCTAssertNotNil(ContentURL.validated("https://example.com/path?q=1"))
    }
}

private final class RegistrationFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url!.lastPathComponent
        if path == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            body = data
        }
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        let validRequest = request.httpMethod == "POST"
            && request.value(forHTTPHeaderField: "Content-Type") == "application/json"
            && request.value(forHTTPHeaderField: "User-Agent")?.contains("Safari") == true
            && Set(json?.keys.map { $0 } ?? []) == Set(["bundle", "push_token", "advertising_id", "appsflyer_id"])
            && json?["bundle"]?.isEmpty == false
        guard validRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let payload: String
        switch path {
        case "native": payload = #"{"success":true,"app_data":null}"#
        case "rejected": payload = #"{"success":false,"app_data":"https://content.example/home"}"#
        case "invalid-url": payload = #"{"success":true,"app_data":"javascript:alert(1)"}"#
        case "malformed": payload = "not JSON"
        default: payload = #"{"success":true,"app_data":"https://content.example/home"}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: path == "server-error" ? 503 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
