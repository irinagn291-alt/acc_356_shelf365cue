import Foundation

struct CompanionItem: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let detail: String
}

struct CompanionSnapshot: Codable, Equatable {
    let title: String
    let value: String
    let detail: String
    let items: [CompanionItem]
    let updated: Date

    static let empty = CompanionSnapshot(title: Brand.section, value: "Nothing saved yet", detail: Brand.hint, items: [], updated: .distantPast)
    static let key = "companion.snapshot.v1"
    static var defaults: UserDefaults {
        UserDefaults(suiteName: Brand.group) ?? .standard
    }
    static func read() -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .empty }
        return value
    }
}
