import Foundation
import WidgetKit

@MainActor
final class WidgetPublisher {
    static let shared = WidgetPublisher()
    private var snapshot = CompanionSnapshot.read()
    private init() {}

    func publish(title: String, value: String, detail: String, items: [CompanionItem]) {
        // Keep widget snapshots small and readable.
        let items = items.prefix(24).map {
            CompanionItem(id: $0.id, title: String($0.title.prefix(120)), detail: String($0.detail.prefix(180)))
        }
        let value = String(value.prefix(160))
        let now = Date()
        guard snapshot.title != title || snapshot.value != value || snapshot.detail != detail ||
                snapshot.items != items || !Calendar.current.isDate(snapshot.updated, inSameDayAs: now) else { return }
        let next = CompanionSnapshot(title: title, value: value, detail: detail, items: items, updated: now)
        guard let data = try? JSONEncoder().encode(next) else { return }
        CompanionSnapshot.defaults.set(data, forKey: CompanionSnapshot.key)
        snapshot = next
        WidgetCenter.shared.reloadTimelines(ofKind: Brand.widget)
    }

}
