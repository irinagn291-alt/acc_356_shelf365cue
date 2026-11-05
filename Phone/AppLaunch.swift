import SwiftUI

enum LaunchMode: Sendable {
    case nativeInterface
    case webContent
    case loading
}

/// Only absolute web URLs can be selected by the registration response or cache.
enum ContentURL {
    static func validated(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}


@MainActor
final class LaunchPreferences {
    static let shared = LaunchPreferences()

    private let storage: UserDefaults

    private static let contentURLKey = "cached_content_url"
    private static let registrationAttemptedKey = "registration_attempted"

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        BrowserSession.restore()
    }

    var contentURL: String? {
        get { storage.string(forKey: Self.contentURLKey) }
        set {
            if let value = newValue {
                storage.set(value, forKey: Self.contentURLKey)
            } else {
                storage.removeObject(forKey: Self.contentURLKey)
            }
        }
    }

    var hasContentURL: Bool {
        guard let url = contentURL, ContentURL.validated(url) != nil else { return false }
        return true
    }

    var wasRegistrationAttempted: Bool {
        get { storage.bool(forKey: Self.registrationAttemptedKey) }
        set { storage.set(newValue, forKey: Self.registrationAttemptedKey) }
    }

    func saveContentURL(_ url: String?) {
        wasRegistrationAttempted = true
        guard let url, !url.isEmpty else { return }
        contentURL = url
    }

    func clearCache() {
        contentURL = nil
        wasRegistrationAttempted = false
    }
}

@MainActor
final class AppLaunch: ObservableObject {
    @Published private(set) var mode: LaunchMode = .loading
    @Published private(set) var contentURL: String?
    private let registration: RegistrationClient
    private var started = false

    init(registration: RegistrationClient = .shared) {
        self.registration = registration
    }

    func start() {
        guard !started else { return }
        started = true
        registration.performRegistration { [weak self] mode, url in
            self?.contentURL = url
            self?.mode = mode
        }
    }
}
