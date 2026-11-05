import Foundation

/// The gate identifies a returning install by the session cookie on
/// `POST /register`. That cookie is a session cookie, so URLSession drops it
/// when the process dies and the next launch looks like a new user.
@MainActor
enum BrowserSession {
    private static let storageKey = "session_cookies_archive"
    private static let lifetime: TimeInterval = 60 * 60 * 24 * 400

    static func restore() {
        guard let archived = UserDefaults.standard.data(forKey: storageKey),
              let rows = try? PropertyListSerialization.propertyList(from: archived, format: nil) as? [[String: Any]]
        else { return }
        for row in rows {
            let properties = Dictionary(uniqueKeysWithValues: row.map { (HTTPCookiePropertyKey($0.key), $0.value) })
            guard let cookie = HTTPCookie(properties: properties),
                  cookie.expiresDate.map({ $0 > Date() }) ?? true else { continue }
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    static func persist() {
        let durable = (HTTPCookieStorage.shared.cookies ?? []).compactMap(durableCookie)
        guard !durable.isEmpty else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        // HTTPCookie does not conform to NSSecureCoding. Persist its documented
        // property dictionary instead of archiving the object (which raises an exception).
        let rows: [[String: Any]] = durable.compactMap { cookie in
            guard let properties = cookie.properties else { return nil }
            return Dictionary(uniqueKeysWithValues: properties.map { key, value in
                (key.rawValue, (value as? URL)?.absoluteString as Any? ?? value)
            })
        }
        guard let archived = try? PropertyListSerialization.data(fromPropertyList: rows, format: .binary, options: 0)
        else { return }
        for cookie in durable { HTTPCookieStorage.shared.setCookie(cookie) }
        UserDefaults.standard.set(archived, forKey: storageKey)
    }

    static func store(response: HTTPURLResponse?) {
        guard let response, let url = response.url else { return }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let header = value as? String else { continue }
            headers[name] = header
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private static func durableCookie(_ cookie: HTTPCookie) -> HTTPCookie? {
        guard var props = cookie.properties else { return cookie }
        if cookie.expiresDate == nil || cookie.isSessionOnly {
            props.removeValue(forKey: .discard)
            props[.expires] = Date().addingTimeInterval(lifetime)
        }
        return HTTPCookie(properties: props) ?? cookie
    }
}

